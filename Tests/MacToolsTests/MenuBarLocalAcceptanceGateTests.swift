// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarLocalAcceptanceGateTests: XCTestCase {
    func proof(_ session: UUID, receipt: UUID = UUID()) -> MenuBarLocalAcceptanceGate.StartProof {
        .init(session: session, receipt: receipt, window: 7, eventNumber: 20, timestamp: 10, targetPID: 123)
    }
    func armed() -> MenuBarLocalAcceptanceGate {
        let id = UUID(); var gate = MenuBarLocalAcceptanceGate(session: id); gate.prepared(pid: 123, window: 7)
        let p = proof(id); gate.start(appKit: p, tap: p, now: 1000); return gate
    }
    func testCannotStartBeforeReadyOrWithoutExactReceiptProof() {
        let id = UUID(); var g = MenuBarLocalAcceptanceGate(session: id); let p = proof(id)
        g.start(appKit: p, tap: p, now: 0); XCTAssertEqual(g.state, .preparing)
        g.prepared(pid: 123, window: 7); g.start(appKit: p, tap: proof(id), now: 0)
        XCTAssertEqual(g.triggerCount, 0); XCTAssertEqual(g.matchedStartCount, 0)
        guard case .terminal = g.state else { return XCTFail("must refuse") }
    }
    func testThreeSecondsIsMonotonicAndExactlyOneProposal() {
        var g = armed(); XCTAssertEqual(g.remainingSeconds(now: 1000), 3)
        for t in stride(from: UInt64(1100), through: 3900, by: 100) { g.tick(now: t, monitorHealthy: true) }
        XCTAssertEqual(g.triggerCount, 0); g.tick(now: 4000, monitorHealthy: true)
        XCTAssertEqual(g.state, .triggerProposed); XCTAssertEqual(g.triggerCount, 1)
        g.tick(now: 4100, monitorHealthy: true); XCTAssertEqual(g.triggerCount, 1)
    }
    func testEveryOtherActivityStopsAndLaterQuietCannotRestart() {
        var g = armed(); g.activity()
        for t in stride(from: UInt64(1100), through: 5000, by: 100) { g.tick(now: t, monitorHealthy: true) }
        XCTAssertEqual(g.triggerCount, 0); g.prepared(pid: 123, window: 7); XCTAssertNotEqual(g.state, .ready)
    }
    func testCancelAndHealthLossStopWithoutTrigger() {
        var g = armed(); g.cancel(); g.tick(now: 1200, monitorHealthy: true); XCTAssertEqual(g.triggerCount, 0)
        g = armed(); g.tick(now: 1100, monitorHealthy: false); XCTAssertEqual(g.triggerCount, 0)
        guard case .terminal = g.state else { return XCTFail("must refuse") }
    }
    func testStallBackwardClockAndDuplicateStartCannotExtendCountdown() {
        var g = armed(); g.tick(now: 999, monitorHealthy: true)
        guard case .terminal = g.state else { return XCTFail("must refuse backward clock") }
        g = armed(); g.tick(now: 1600, monitorHealthy: true)
        guard case .terminal = g.state else { return XCTFail("must refuse stall") }
        g = armed(); let p = proof(g.session); g.start(appKit: p, tap: p, now: 2000)
        XCTAssertEqual(g.remainingSeconds(now: 2000), 2); XCTAssertEqual(g.matchedStartCount, 1)
    }
    func testEqualPacketsForAnotherWindowDoNotProveOwnStart() {
        let id = UUID(); var g = MenuBarLocalAcceptanceGate(session: id); g.prepared(pid: 123, window: 8)
        let p = proof(id); g.start(appKit: p, tap: p, now: 1000)
        XCTAssertEqual(g.matchedStartCount, 0); XCTAssertEqual(g.triggerCount, 0)
        guard case .terminal = g.state else { return XCTFail("must refuse foreign window") }
    }
    func testSignedAndZeroEventNumbersRemainPartOfTheFullProof() {
        for number in [-32768, -20895, -1, 0, 32767] {
            let id = UUID(), receipt = UUID()
            let p = MenuBarLocalAcceptanceGate.StartProof(session: id, receipt: receipt, window: 7,
                eventNumber: number, timestamp: 10, targetPID: 123)
            var matched = MenuBarLocalAcceptanceGate(session: id); matched.prepared(pid: 123, window: 7)
            matched.start(appKit: p, tap: p, now: 1000)
            XCTAssertEqual(matched.state, .countdown)
            matched.activity(); matched.tick(now: 1100, monitorHealthy: true)
            XCTAssertEqual(matched.triggerCount, 0)
            var mismatch = MenuBarLocalAcceptanceGate(session: id); mismatch.prepared(pid: 123, window: 7)
            let other = MenuBarLocalAcceptanceGate.StartProof(session: id, receipt: receipt, window: 7,
                eventNumber: number + 1, timestamp: 10, targetPID: 123)
            mismatch.start(appKit: p, tap: other, now: 1000)
            XCTAssertEqual(mismatch.matchedStartCount, 0)
            guard case .terminal = mismatch.state else { return XCTFail("number must still match exactly") }
        }
    }

}
