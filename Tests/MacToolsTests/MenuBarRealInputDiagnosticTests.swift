// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarRealInputDiagnosticTests: XCTestCase {
    final class Source: MenuBarHiddenInterferenceSource {
        let harness: MenuBarRealLocalAuthorizationTests.Harness
        var reads = 0, drains = 0, changeDuringArm = false
        init(_ harness: MenuBarRealLocalAuthorizationTests.Harness) { self.harness = harness }
        func read() -> MenuBarMoveInterference.Availability {
            reads += 1
            if changeDuringArm { harness.epoch = UUID() }
            return .available(.init(sequence: UInt64(reads), uptimeMilliseconds: harness.time / 1_000_000,
                continuity: harness.continuity, externalEpoch: harness.epoch,
                coverage: MenuBarMoveInterference.requiredCoverage, buttons: [], keys: [], modifiers: 0))
        }
        func drainEvents() -> [MenuBarMoveInterference.Event] { drains += 1; return [] }
    }
    func testSameHandoffArmsRealGateAndConsumesOnlyInProcessPermit() throws {
        let h = try MenuBarRealLocalAuthorizationTests.Harness(); try h.start(); try h.finish()
        let source = Source(h), permit = try h.broker.permit(); var gate = MenuBarMoveInterference.Gate()
        try MenuBarRealLocalAuthorization.armAndHandoff(h.fixture.plan(), permit: permit, input: source,
            gate: &gate, now: { h.time / 1_000_000 })
        XCTAssertEqual(gate.state, .armed); XCTAssertTrue(permit.handedOff)
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.drains, 1)
        XCTAssertThrowsError(try MenuBarRealLocalAuthorization.armAndHandoff(h.fixture.plan(), permit: permit, input: source,
            gate: &gate, now: { h.time / 1_000_000 }))
        XCTAssertEqual(source.reads, 1) // Used Permit refuses before another baseline.
    }
    func testArmTimeFenceChangeCannotBeHiddenBySharedHandoff() throws {
        let h = try MenuBarRealLocalAuthorizationTests.Harness(); try h.start(); try h.finish()
        let source = Source(h), permit = try h.broker.permit(); source.changeDuringArm = true
        var gate = MenuBarMoveInterference.Gate()
        XCTAssertThrowsError(try MenuBarRealLocalAuthorization.armAndHandoff(h.fixture.plan(), permit: permit, input: source,
            gate: &gate, now: { h.time / 1_000_000 }))
        XCTAssertFalse(permit.handedOff); XCTAssertTrue(permit.consumed)
        XCTAssertTrue(h.broker.monitor.ledger.stopped)
    }
    func testStoppedBeforeAndAfterFenceHaveDifferentReadCounts() throws {
        let before = try MenuBarRealLocalAuthorizationTests.Harness()
        var beforeReads = 0; before.fenceHook = { beforeReads += 1 }
        before.broker.monitor.cancel()
        XCTAssertThrowsError(try before.broker.poll())
        XCTAssertEqual(beforeReads, 0)

        let after = try MenuBarRealLocalAuthorizationTests.Harness()
        try after.start()
        var afterReads = 0
        after.fenceHook = { afterReads += 1; after.healthy = false }
        XCTAssertThrowsError(try after.broker.poll())
        XCTAssertEqual(afterReads, 1)
        XCTAssertEqual(after.broker.monitor.state, .stopped(.monitorLost))
        // The historical counter narrows the throw site only. This injected
        // monitor loss does not claim to be the historical ledger Cause.
    }
    func testRealSessionAndUnboundDirectoryCannotEnterDiagnosticNamespace() throws {
        for path in ["/tmp/mac-tools-hidden-driver-task7/session-", "/tmp/unbound/session-", "/tmp/mac-tools-real-input-diagnostic/other-"] {
            let nonce = UUID()
            XCTAssertThrowsError(try MenuBarRealInputDiagnosticScope.validate(URL(fileURLWithPath: path + nonce.uuidString.lowercased()), nonce: nonce))
        }
    }
}
