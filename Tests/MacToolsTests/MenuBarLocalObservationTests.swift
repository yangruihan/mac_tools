// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

/// Offline replay and clock injection only. Never opens a native tap or window.
final class MenuBarLocalObservationTests: XCTestCase {
    typealias B = MenuBarLocalObservationBudget

    func testSetupSharesDeadlineAndLastWaitUsesRemainingBudget() throws {
        let budget = try B(began: 1_000_000_000)
        var now: UInt64 = 10_850_000_000 // Setup/earlier work already consumed 9.85 seconds.
        var polls = 0, waits: [Double] = []
        try budget.observe(now: { now }, poll: { polls += 1; now += 20_000_000 }, wait: {
            waits.append($0); now += UInt64(($0 * 1_000_000_000).rounded())
        })
        XCTAssertEqual(polls, 2)
        XCTAssertEqual(waits, [0.1, 0.01])
        XCTAssertEqual(now, budget.deadline) // No renewed ten seconds after setup.
    }

    func testSlowPollAndLateWakeDoNotAddWaitOrFinalSample() throws {
        let budget = try B(began: 1_000_000_000)
        for slowPoll in [true, false] {
            var now: UInt64 = budget.deadline - 50_000_000
            var polls = 0, waits: [Double] = []
            try budget.observe(now: { now }, poll: {
                polls += 1
                if slowPoll { now += 200_000_000 }
            }, wait: {
                waits.append($0); now = budget.deadline + 100_000_000 // Scheduler wakes late.
            })
            XCTAssertEqual(polls, 1)
            XCTAssertEqual(waits, slowPoll ? [] : [0.05])
        }
    }

    func testExhaustedSetupDoesNoWorkAndInvalidClockRefuses() throws {
        let budget = try B(began: 1_000_000_000)
        for now in [budget.deadline, budget.deadline + 1] {
            XCTAssertEqual(try budget.waitSeconds(at: now, maximum: 300_000_000), 0)
            try budget.observe(now: { now }, poll: { XCTFail("expired poll") }, wait: { _ in XCTFail("expired wait") })
        }
        XCTAssertThrowsError(try budget.observe(now: { 0 }, poll: { XCTFail("backward clock poll") }, wait: { _ in XCTFail("backward clock wait") }))
        XCTAssertThrowsError(try B(began: UInt64.max))
        XCTAssertThrowsError(try B(began: 0, duration: 0))
    }

    func testPollFailureStopsWithoutWaitingOrRetrying() throws {
        enum Injected: Error { case monitorLost }
        let budget = try B(began: 1_000_000_000)
        var polls = 0
        XCTAssertThrowsError(try budget.observe(now: { budget.began }, poll: {
            polls += 1; throw Injected.monitorLost
        }, wait: { _ in XCTFail("wait after loss") }))
        XCTAssertEqual(polls, 1)
    }

    func testCapturedIdleSamplesRemainReadyForBothPurposesWithoutAuthorization() throws {
        typealias L = MenuBarLocalContinuityLedger
        struct Capture: Decodable {
            let nonce: UUID, controllerPID: Int32, observationCompleted: Bool
            let inputValidationPassed: Bool, realMoveValidated: Bool
            let input: MenuBarLocalStartInput.Evidence
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repo.appendingPathComponent("docs/evidence/menu-bar-ready-observation-2026-10-05/observation")
        let bytes = try Data(contentsOf: directory.appendingPathComponent("terminal.json"))
        XCTAssertEqual(bytes, try Data(contentsOf: directory.appendingPathComponent("worker.stdout.json")))
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "f74d18215da9e8f90bb599214d040c4bce1d8f3336f6dc97a11d0f262b9304ba")
        let receipt = try JSONDecoder().decode(MenuBarLocalDiagnosticReceipt.Envelope.self, from: bytes)
        let capture = try JSONDecoder().decode(Capture.self, from: XCTUnwrap(receipt.payload))
        XCTAssertEqual(capture.nonce.uuidString, "9C13E26B-7E19-43AB-968A-67854589DCE6")
        XCTAssertEqual(capture.controllerPID, 39621)
        XCTAssertTrue(capture.observationCompleted)
        XCTAssertFalse(capture.inputValidationPassed); XCTAssertFalse(capture.realMoveValidated)
        XCTAssertEqual(capture.input.nodes.count, 185)
        XCTAssertEqual(capture.input.state, "ready")
        XCTAssertNil(capture.input.proof); XCTAssertNil(capture.input.firstFailure)
        for purpose in [L.Purpose.noMove, .realStart] {
            var ledger = L(session: capture.nonce, pid: capture.controllerPID, purpose: purpose)
            for node in capture.input.nodes {
                XCTAssertEqual(node.kind, .sample); XCTAssertNil(node.packet)
                ledger.sampled(try XCTUnwrap(node.sample))
                XCTAssertEqual(ledger.state, .ready)
                XCTAssertNil(ledger.proof); XCTAssertNil(ledger.firstFailure)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(ledger.nodes), try encoder.encode(capture.input.nodes))
            XCTAssertEqual(ledger.matchedStartCount, 0); XCTAssertEqual(ledger.validationCount, 0)
            XCTAssertEqual(ledger.tapCount, 0); XCTAssertEqual(ledger.epoch, 0)
        }
    }
}
