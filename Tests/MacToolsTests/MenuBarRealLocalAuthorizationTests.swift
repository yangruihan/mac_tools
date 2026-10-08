// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarRealLocalAuthorizationTests: XCTestCase {
    typealias A = MenuBarRealLocalAuthorization
    final class Harness {
        let fixture: MenuBarHiddenMoveFixture
        var time: UInt64 = 1_000_000_000, count: UInt32 = 100, hid: UInt64 = 900_000_000
        var healthy = true, fenceHealthy = true, buttons: UInt64 = 0
        var continuity = UUID(), epoch = UUID(), events = 2
        var pumpHook: (() -> Void)?, fenceHook: (() -> Void)?
        var broker: A!
        let binding: MenuBarDispatchWitness.Binding
        init(fixture: MenuBarHiddenMoveFixture = .init(), evidence: MenuBarMoveStageRecorder? = nil, expires: UInt64 = 10_000_000_000,
             wrongBinding: Bool = false, terminalBackupURL: URL? = nil) throws {
            self.fixture = fixture
            binding = .init(nonce: wrongBinding ? UUID() : fixture.original.owner.nonce, targetPID: fixture.original.owner.target.pid,
                controllerPID: 123, controllerLaunch: 10, controllerSHA256: String(repeating: "a", count: 64))
            let reads = MenuBarLocalStartInput.Reads(now: { self.time }, counter: { self.count },
                age: { Double(self.time - self.hid) / 1_000_000_000 }, buttons: { self.buttons }, modifiers: { 0 },
                healthy: { self.healthy }, pump: { self.pumpHook?() })
            broker = A(binding: binding, plan: try fixture.plan(), reads: reads, fence: {
                self.fenceHook?()
                guard self.fenceHealthy else { throw A.Failure.interference }
                return .init(continuity: self.continuity, epoch: self.epoch, eventCount: self.events)
            }, expires: expires, evidence: evidence, terminalBackupURL: terminalBackupURL)
            broker.monitor.configureLocalStart(window: 7)
        }
        func event(_ type: CGEventType = .leftMouseUp, at: UInt64 = 1_050_000_000) -> CGEvent {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .init(x: 864, y: 355), mouseButton: .left)!
            e.timestamp = at; e.setIntegerValueField(.mouseEventNumber, value: -20895)
            e.setIntegerValueField(.eventSourceUnixProcessID, value: 456); e.setIntegerValueField(.eventSourceStateID, value: 1690226100)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 7)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 7)
            return e
        }
        func start(appKitFirst: Bool = true) throws {
            time = 1_010_000_000; broker.monitor.receive(.leftMouseDown, event: event(.leftMouseDown, at: time))
            let up = event()
            if appKitFirst { time = 1_050_100_000; broker.begin(up) }
            time = 1_051_000_000; broker.monitor.receive(.leftMouseUp, event: up)
            time = 1_060_000_000
            if !appKitFirst { broker.begin(up) }
            try broker.poll()
            XCTAssertEqual(broker.monitor.state, .countdown)
        }
        func finish() throws {
            for t in stride(from: UInt64(1_160_000_000), through: 4_060_000_000, by: 100_000_000) {
                time = t; try broker.poll()
            }
            XCTAssertEqual(broker.monitor.state, .validatedRealInput)
        }
        var lease: MenuBarMoveInterference.Lease {
            .init(gesture: UUID(), continuity: continuity, externalEpoch: epoch, interferenceEpoch: UUID())
        }
    }
    func testBothCallbackOrdersProduceOnlySingleRealPermitAndHandoff() throws {
        for first in [true, false] {
            let h = try Harness(); try h.start(appKitFirst: first)
            XCTAssertThrowsError(try h.broker.permit())
            try h.finish()
            XCTAssertNotEqual(h.broker.monitor.state, .validatedNoMove)
            let permit = try h.broker.permit(), plan = try h.fixture.plan()
            XCTAssertThrowsError(try h.broker.permit())
            try permit.check(plan); try permit.handoff(plan, lease: h.lease)
            XCTAssertTrue(permit.consumed); XCTAssertTrue(permit.handedOff)
            XCTAssertFalse(h.broker.monitor.diagnostics().monitoringHealthy)
            XCTAssertThrowsError(try permit.handoff(plan, lease: h.lease)); XCTAssertThrowsError(try permit.check(plan))
        }
    }
    func testNoMoveResultAndVirtualStartCannotCreateRealPermit() throws {
        let old = MenuBarLocalNativeContinuityTests.Harness(); old.start(); old.finish()
        XCTAssertEqual(old.monitor.state, .validatedNoMove)
        let real = try Harness()
        XCTAssertNil(real.broker.monitor.ledger.proof); XCTAssertThrowsError(try real.broker.permit())
        real.broker.monitor.beginStart(.init(real.event()), virtual: true)
        XCTAssertThrowsError(try real.broker.permit())
    }
    func testSessionFenceChangeOrLossCannotBeErasedByLaterQuiet() throws {
        for failure in 0..<4 {
            let h = try Harness(); try h.start(); h.time += 100_000_000
            if failure == 0 { h.epoch = UUID() }
            if failure == 1 { h.continuity = UUID() }
            if failure == 2 { h.events += 1 }
            if failure == 3 { h.fenceHealthy = false }
            XCTAssertThrowsError(try h.broker.poll()); h.fenceHealthy = true
            XCTAssertThrowsError(try h.broker.permit()); XCTAssertTrue(h.broker.monitor.ledger.stopped)
        }
    }
    func testInputBetweenFinalSamplePermitAndHandoffRefuses() throws {
        for failure in 0..<5 {
            let h = try Harness(); try h.start(); try h.finish(); let permit = try h.broker.permit()
            h.time += 100_000_000
            if failure == 0 { h.count += 1 }
            if failure == 1 { h.healthy = false }
            if failure == 2 { h.broker.monitor.receive(.mouseMoved, event: h.event()) }
            if failure == 3 { h.buttons = 1 }
            if failure == 4 { h.hid = h.time }
            XCTAssertThrowsError(try permit.handoff(h.fixture.plan(), lease: h.lease))
            XCTAssertTrue(permit.consumed); XCTAssertFalse(permit.handedOff)
            XCTAssertThrowsError(try permit.check(h.fixture.plan()))
        }
    }
    func testDifferentGateLeaseOrPlanNeverHandsOff() throws {
        for wrongPlan in [false, true] {
            let h = try Harness(); try h.start(); try h.finish(); let permit = try h.broker.permit()
            let plan = try (wrongPlan ? MenuBarHiddenMoveFixture() : h.fixture).plan()
            let lease = wrongPlan ? h.lease : MenuBarMoveInterference.Lease(gesture: UUID(), continuity: UUID(), externalEpoch: UUID(), interferenceEpoch: UUID())
            XCTAssertThrowsError(try permit.handoff(plan, lease: lease))
            XCTAssertTrue(h.broker.monitor.diagnostics().monitoringHealthy) // No false successful handoff/stop.
        }
    }
    func testExpiryCancelStallAndWrongNonceHaveNoPermit() throws {
        for failure in 0..<4 {
            let h = try Harness(expires: failure == 0 ? 1_070_000_000 : 10_000_000_000, wrongBinding: failure == 3)
            try h.start()
            if failure == 0 { h.time = 1_080_000_000 }
            if failure == 1 { h.broker.cancel() }
            if failure == 2 { h.time += 600_000_000 }
            if failure == 3 { try h.finish() }
            XCTAssertThrowsError(try h.broker.permit())
        }
    }
    func testInputDuringOtherTapReadCannotFitIntoHandoffGap() throws {
        let h = try Harness(); try h.start(); try h.finish(); let permit = try h.broker.permit()
        h.fenceHook = { h.count += 1 }
        XCTAssertThrowsError(try permit.handoff(h.fixture.plan(), lease: h.lease))
        XCTAssertTrue(h.broker.monitor.ledger.stopped)
    }
    func testFailedInputReceiptPersistenceDoesNotIssuePermitOrAllowRetry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-auth-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        enum Disk: Error { case failed }
        let f = MenuBarHiddenMoveFixture()
        let recorder = try MenuBarMoveStageRecorder(directory: dir, nonce: f.original.owner.nonce, controllerPID: 123) { _, _ in throw Disk.failed }
        let h = try Harness(fixture: f, evidence: recorder); try h.start(); try h.finish()
        XCTAssertThrowsError(try h.broker.permit()); XCTAssertThrowsError(try h.broker.permit())
        XCTAssertTrue(recorder.poisoned)
    }
    func testReentrantPollCannotGrantPermitBeforeOuterSamplingCompletes() throws {
        let h = try Harness(); try h.start(); try h.finish()
        var attempts = 0
        h.pumpHook = {
            attempts += 1
            do { _ = try h.broker.permit(); XCTFail("reentrant permit must fail") }
            catch {}
        }
        let permit = try h.broker.permit(); XCTAssertGreaterThan(attempts, 0)
        h.pumpHook = nil; try permit.handoff(h.fixture.plan(), lease: h.lease)
    }

    func testRejectedHardwareLikeUpRetainsExactCauseAndPreCleanupLedger() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-terminal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = MenuBarHiddenMoveFixture()
        let recorder = try MenuBarMoveStageRecorder(directory: dir, nonce: fixture.original.owner.nonce, controllerPID: 123)
        let h = try Harness(fixture: fixture, evidence: recorder)
        h.time = 1_010_000_000; h.broker.monitor.receive(.leftMouseDown, event: h.event(.leftMouseDown, at: h.time))
        let up = h.event()
        h.time = 1_050_100_000; h.broker.begin(up)
        h.count += 1; h.time = 1_051_000_000; h.broker.monitor.receive(.leftMouseUp, event: up)
        h.time = 1_060_000_000
        var rejected: Error?
        do { try h.broker.poll(); XCTFail("HID increase across the start must still refuse") }
        catch { rejected = error }
        let error = try XCTUnwrap(rejected)
        guard case .stopped(let cause) = try XCTUnwrap(error as? A.Failure) else { return XCTFail("lost cause") }
        XCTAssertEqual(cause, .hidChangedAcrossStart)
        let samples = h.broker.monitor.diagnostics().sampleCount
        let nodes = h.broker.monitor.ledger.nodes.count
        try h.broker.recordTerminal(error)
        let saved = try XCTUnwrap(h.broker.terminalEvidence)
        XCTAssertEqual(saved.stoppedCause, .hidChangedAcrossStart)
        XCTAssertEqual(saved.capturedStart, .init(up))
        XCTAssertTrue(saved.input.nodes.contains { $0.kind == .ownUp })
        XCTAssertEqual(saved.input.nodes.count, nodes)
        XCTAssertEqual(h.broker.monitor.diagnostics().sampleCount, samples) // No new sampling/rebase.
        XCTAssertEqual(saved.matchedStartCount, 0); XCTAssertEqual(saved.validationCount, 0)
        XCTAssertFalse(saved.permitIssued); XCTAssertFalse(saved.handedOff); XCTAssertNil(saved.sourceFence)
        XCTAssertTrue(saved.diagnostics.monitoringHealthy)
        h.broker.cancel(); h.broker.monitor.stop()
        XCTAssertFalse(h.broker.monitor.diagnostics().monitoringHealthy)
        XCTAssertTrue(saved.diagnostics.monitoringHealthy) // Cleanup did not overwrite the snapshot.
        XCTAssertThrowsError(try h.broker.permit())
        let raw = try Data(contentsOf: dir.appendingPathComponent("0001-real-local-ui-terminal.json"))
        let record = try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: raw)
        let decoded = try JSONDecoder().decode(A.Terminal.self, from: record.payload)
        XCTAssertEqual(decoded.stoppedCause, .hidChangedAcrossStart)
        XCTAssertEqual(decoded.binding, h.binding)
    }

    func testTerminalDistinguishesBeforeStartLossFromLaterFenceFailure() throws {
        for beforeStart in [true, false] {
            let h = try Harness()
            if beforeStart { h.healthy = false }
            else { try h.start(); h.epoch = UUID(); h.time += 100_000_000 }
            var rejected: Error?
            do { try h.broker.poll(); XCTFail("expected refusal") } catch { rejected = error }
            try h.broker.recordTerminal(try XCTUnwrap(rejected))
            let saved = try XCTUnwrap(h.broker.terminalEvidence)
            XCTAssertEqual(saved.stoppedCause, beforeStart ? .monitorLost : .cancelled)
            XCTAssertEqual(saved.capturedStart == nil, beforeStart)
            XCTAssertEqual(saved.sourceFence == nil, beforeStart)
            XCTAssertEqual(saved.matchedStartCount, beforeStart ? 0 : 1)
            XCTAssertTrue(saved.failure?.contains(beforeStart ? "monitorLost" : "interference") == true)
            XCTAssertEqual(saved.input.scope, "isolatedRealStartAdapter")
            XCTAssertThrowsError(try h.broker.permit())
        }
    }

    func testTerminalWriteUncertaintyRetainsOriginalFailureAndNeverRetries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-terminal-disk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        enum Disk: Error { case uncertain }
        let fixture = MenuBarHiddenMoveFixture(); var attempts = 0
        let recorder = try MenuBarMoveStageRecorder(directory: dir, nonce: fixture.original.owner.nonce, controllerPID: 123) { bytes, url in
            attempts += 1; try MenuBarDispatchWitness.writeNew(bytes, to: url); throw Disk.uncertain
        }
        let h = try Harness(fixture: fixture, evidence: recorder)
        h.broker.cancel()
        XCTAssertThrowsError(try h.broker.recordTerminal(A.Failure.stopped(.cancelled)))
        let saved = try XCTUnwrap(h.broker.terminalEvidence)
        XCTAssertEqual(saved.stoppedCause, .cancelled)
        XCTAssertTrue(saved.failure?.contains("cancelled") == true)
        XCTAssertNotNil(h.broker.terminalEvidenceFailure); XCTAssertTrue(recorder.poisoned)
        try h.broker.recordTerminal(A.Failure.expired)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(h.broker.terminalEvidence?.failure, saved.failure)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
        XCTAssertThrowsError(try h.broker.permit())
    }

    func testCompletedHandoffTerminalDoesNotReopenEitherAuthorization() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-terminal-success-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = MenuBarHiddenMoveFixture()
        let recorder = try MenuBarMoveStageRecorder(directory: dir, nonce: fixture.original.owner.nonce, controllerPID: 123)
        let h = try Harness(fixture: fixture, evidence: recorder)
        try h.start(); try h.finish()
        let permit = try h.broker.permit(); try permit.handoff(h.fixture.plan(), lease: h.lease)
        try h.broker.recordTerminal(nil)
        let saved = try XCTUnwrap(h.broker.terminalEvidence)
        XCTAssertNil(saved.failure); XCTAssertNil(saved.stoppedCause)
        XCTAssertTrue(saved.permitIssued); XCTAssertTrue(saved.handedOff)
        XCTAssertEqual(saved.matchedStartCount, 1); XCTAssertEqual(saved.validationCount, 1)
        XCTAssertEqual(recorder.count, 3); XCTAssertFalse(recorder.poisoned)
        try h.broker.recordTerminal(A.Failure.expired)
        XCTAssertEqual(recorder.count, 3); XCTAssertNil(h.broker.terminalEvidence?.failure)
        XCTAssertThrowsError(try h.broker.permit())
        XCTAssertThrowsError(try permit.handoff(h.fixture.plan(), lease: h.lease))
    }

    func testIndependentTerminalPeerSurvivesUncertainStageAndCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-peer-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        enum Disk: Error { case uncertain }
        let f = MenuBarHiddenMoveFixture(); var attempts = 0
        let recorder = try MenuBarMoveStageRecorder(directory: root.appendingPathComponent("stages"), nonce: f.original.owner.nonce, controllerPID: 123) { bytes, url in
            attempts += 1; try MenuBarDispatchWitness.writeNew(bytes, to: url); throw Disk.uncertain
        }
        let backup = root.appendingPathComponent("local-input-terminal.json")
        let h = try Harness(fixture: f, evidence: recorder, terminalBackupURL: backup)
        h.broker.cancel()
        XCTAssertThrowsError(try h.broker.recordTerminal(MenuBarRealRunControl.Failure.invalidRequest))
        let bytes = try Data(contentsOf: backup)
        let saved = try JSONDecoder().decode(MenuBarLocalDiagnosticReceipt.Envelope.self, from: bytes)
        XCTAssertEqual(saved.context.failure, "invalidRequest")
        XCTAssertEqual(saved.context.firstFailure?.cause, .cancelled)
        XCTAssertEqual(saved.primaryWriteFailure, "uncertain")
        XCTAssertTrue(h.broker.terminalBackupWritten); XCTAssertTrue(recorder.poisoned)
        h.broker.monitor.stop(); h.broker.cancel(); try h.broker.recordTerminal(A.Failure.expired)
        XCTAssertEqual(attempts, 1); XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertEqual(h.broker.terminalEvidence?.failure, "invalidRequest")
        XCTAssertThrowsError(try h.broker.permit())
    }

    func testUnavailableBackupCannotOverwriteEitherOriginalErrorOrExistingReceipt() throws {
        for stageFails in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-peer-fail-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            enum Disk: Error { case primary }
            let f = MenuBarHiddenMoveFixture(), backup = root.appendingPathComponent("local-input-terminal.json")
            let existing = Data("existing bound receipt must not change".utf8)
            try MenuBarDispatchWitness.writeNew(existing, to: backup)
            let recorder = try MenuBarMoveStageRecorder(directory: root.appendingPathComponent("stages"), nonce: f.original.owner.nonce, controllerPID: 123) { bytes, url in
                if stageFails { throw Disk.primary }; try MenuBarDispatchWitness.writeNew(bytes, to: url)
            }
            let h = try Harness(fixture: f, evidence: recorder, terminalBackupURL: backup); h.broker.cancel()
            if stageFails { XCTAssertThrowsError(try h.broker.recordTerminal(A.Failure.expired)) { XCTAssertTrue($0 is Disk) } }
            else { try h.broker.recordTerminal(A.Failure.expired) }
            XCTAssertNotNil(h.broker.terminalBackupFailure); XCTAssertFalse(h.broker.terminalBackupWritten)
            XCTAssertEqual(h.broker.terminalEvidence?.failure, "expired")
            h.broker.monitor.stop(); try h.broker.recordTerminal(A.Failure.used)
            XCTAssertEqual(try Data(contentsOf: backup), existing)
            XCTAssertEqual(h.broker.terminalEvidence?.failure, "expired")
        }
    }

    func testBrokerFailureMatrixKeepsOriginAndFenceFactsAcrossCleanup() throws {
        for kind in ["expired", "binding", "fence", "lease", "used"] {
            let h = try Harness(expires: kind == "expired" ? 1_070_000_000 : 10_000_000_000, wrongBinding: kind == "binding")
            try h.start()
            var error: Error?
            do {
                switch kind {
                case "expired": h.time = 1_080_000_000; try h.broker.poll()
                case "fence": h.events += 1; try h.broker.poll()
                case "lease":
                    try h.finish(); let permit = try h.broker.permit()
                    let wrong = MenuBarMoveInterference.Lease(gesture: UUID(), continuity: UUID(), externalEpoch: UUID(), interferenceEpoch: UUID())
                    try permit.handoff(h.fixture.plan(), lease: wrong)
                default:
                    try h.finish(); _ = try h.broker.permit()
                    if kind == "used" { _ = try h.broker.permit() }
                }
                XCTFail("expected \(kind) refusal")
            } catch let caught { error = caught }
            let original = try XCTUnwrap(error)
            try h.broker.recordTerminal(original)
            let saved = try XCTUnwrap(h.broker.terminalEvidence)
            XCTAssertEqual(saved.failure, ["fence", "lease"].contains(kind) ? "interference" : kind)
            if kind == "fence" {
                XCTAssertNotEqual(saved.sourceFence?.eventCount, saved.lastObservedSourceFence?.eventCount)
            }
            if kind == "lease" {
                XCTAssertNotEqual(saved.sourceFence?.continuity, saved.handoffAttempt?.continuity)
            }
            let bytes = try JSONEncoder().encode(saved)
            h.broker.cancel(); h.broker.monitor.stop(); try h.broker.recordTerminal(A.Failure.stopped(.cancelled))
            let after = try XCTUnwrap(h.broker.terminalEvidence)
            XCTAssertEqual(after.failure, saved.failure)
            XCTAssertEqual(after.input.firstFailure, saved.input.firstFailure)
            XCTAssertEqual(try JSONDecoder().decode(A.Terminal.self, from: bytes).failure, saved.failure)
        }
    }

}
