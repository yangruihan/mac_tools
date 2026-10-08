// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarSharedStopTests: XCTestCase {
    typealias I = MenuBarMoveInterference
    final class Input: MenuBarOwnedEventInput {
        let privateEventSource = CGEventSource(stateID: .privateState)!
        var monitoringHealthy = true, continuity = UUID(), epoch = UUID()
        var value: MenuBarListenOnlyInterferenceSource.Receipt = .matched
        var onRegister: (() -> Void)?, onReceipt: (() -> Void)?
        var abandoned = 0
        func read() -> I.Availability {
            .available(.init(sequence: 1, uptimeMilliseconds: 1000, continuity: continuity,
                externalEpoch: epoch, coverage: I.requiredCoverage, buttons: [], keys: [], modifiers: 0))
        }
        func registerForReceipt(_ event: CGEvent, gesture: UUID, expectedEpoch: UUID?, expectedContinuity: UUID?) throws -> MenuBarListenOnlyInterferenceSource.Ticket {
            XCTAssertEqual(expectedEpoch, epoch); XCTAssertEqual(expectedContinuity, continuity)
            onRegister?(); return .init(marker: 7, epoch: epoch)
        }
        func receipt(_ ticket: MenuBarListenOnlyInterferenceSource.Ticket) -> MenuBarListenOnlyInterferenceSource.Receipt { onReceipt?(); return value }
        func abandonReceipt() { abandoned += 1 }
    }
    final class Harness {
        enum Fault: Error { case uncertain }
        let input = Input(), stop = MenuBarOperationStop(), gesture = UUID(), directory: URL
        var time = 1.0, pumps = 0, sessionTypes: [CGEventType] = [], pidTypes: [CGEventType] = []
        var cancel = false, denyPermission = false
        var pumpHook: (() -> Void)?, sessionHook: (() throws -> Void)?, pidHook: (() throws -> Void)?
        var witnessHook: ((String) -> Void)?
        lazy var witness: MenuBarDispatchWitness = try! .init(directory: directory,
            binding: .init(nonce: UUID(), targetPID: 234, controllerPID: 123, controllerLaunch: 1,
                controllerSHA256: String(repeating: "a", count: 64)), afterPersist: { [unowned self] in self.witnessHook?($0) })
        lazy var channel = MenuBarSessionOwnedEventChannel(input: input, witness: witness,
            delivery: .init(permission: { [unowned self] in !self.denyPermission },
                now: { [unowned self] in self.time }, pump: { [unowned self] in
                    self.pumps += 1; self.time += 0.01; self.pumpHook?()
                }, session: { [unowned self] event in
                    self.sessionTypes.append(event.type); try self.sessionHook?()
                }, pid: { [unowned self] event in self.pidTypes.append(event.type); try self.pidHook?() }))
        var lease: I.Lease { .init(gesture: gesture, continuity: input.continuity, externalEpoch: input.epoch, interferenceEpoch: UUID()) }
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("shared-stop-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
        func event(_ type: CGEventType, number: Int64 = 12) throws -> CGEvent {
            try IceOwnedMouseEvent.make(type: type, point: .init(x: 50, y: 20), pid: 234, window: 31,
                command: true, marker: type == .leftMouseDown ? 1 : 2, number: number, source: input.privateEventSource)
        }
        func bound(_ body: () throws -> Void) throws {
            channel.bindOperationStop(stop)
            try stop.withCancellation({ self.cancel }) { try channel.authorize(lease); try body() }
        }
    }

    func testStopAfterDurableSessionWitnessPreventsFirstNativeRoute() throws {
        let h = try Harness(); h.witnessHook = { if $0 == "session" { h.cancel = true } }
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertTrue(h.sessionTypes.isEmpty); XCTAssertTrue(h.pidTypes.isEmpty)
        XCTAssertTrue(h.channel.downResponsibilities.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.directory.appendingPathComponent("dispatch-started.json").path))
        XCTAssertEqual(h.stop.snapshot.reason, .cancelled) // conservative witness remains possible-effect
    }
    func testCancellationInsidePendingReceiptWaitStopsPidAndUp() throws {
        let h = try Harness(); h.input.value = .pending; h.pumpHook = { h.cancel = true }
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertEqual(h.sessionTypes, [.leftMouseDown]); XCTAssertTrue(h.pidTypes.isEmpty)
        XCTAssertTrue(h.channel.needsRelease); XCTAssertEqual(h.pumps, 1)
        XCTAssertGreaterThan(h.input.abandoned, 0)
    }
    func testLastPidPumpDetectsCancellationHealthAndReceiptLoss() throws {
        for cause in 0..<3 {
            let h = try Harness(); h.pumpHook = {
                if h.pumps == 2 {
                    if cause == 0 { h.cancel = true }
                    if cause == 1 { h.input.monitoringHealthy = false }
                    if cause == 2 { h.input.value = .interrupted }
                }
            }
            XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
            XCTAssertEqual(h.sessionTypes, [.leftMouseDown]); XCTAssertTrue(h.pidTypes.isEmpty)
        }
    }
    func testStopDuringPidWitnessWritePreventsSecondRoute() throws {
        let h = try Harness(); h.witnessHook = { if $0 == "pid" { h.stop.request(.externalInput) } }
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertEqual(h.sessionTypes.count, 1); XCTAssertTrue(h.pidTypes.isEmpty)
    }
    func testPermissionLostAfterSessionWritePreventsAllNativeRoutes() throws {
        let h = try Harness(); h.witnessHook = { _ in h.denyPermission = true }
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertTrue(h.sessionTypes.isEmpty); XCTAssertEqual(h.stop.snapshot.reason, .monitorLost)
    }
    func testUnknownReceiptKeepsFixed100msBudgetAndResponsibility() throws {
        let h = try Harness(); h.input.value = .pending
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertGreaterThanOrEqual(h.time, 1.1); XCTAssertLessThan(h.time, 1.12)
        XCTAssertTrue(h.channel.needsRelease); XCTAssertEqual(h.sessionTypes.count, 1); XCTAssertTrue(h.pidTypes.isEmpty)
    }
    func testUncertainDownNeverAutomaticallyPostsCleanupOrClearsResponsibility() throws {
        for route in ["session", "pid"] {
            let h = try Harness()
            if route == "session" { h.sessionHook = { throw Harness.Fault.uncertain } }
            else { h.pidHook = { throw Harness.Fault.uncertain } }
            XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
            let before = (h.sessionTypes.count, h.pidTypes.count)
            h.channel.release(try h.event(.leftMouseUp), gesture: h.gesture)
            h.channel.release(try h.event(.leftMouseUp), gesture: h.gesture)
            XCTAssertEqual(h.sessionTypes.count, before.0); XCTAssertEqual(h.pidTypes.count, before.1)
            XCTAssertEqual(h.channel.emergencyReleases, 0); XCTAssertTrue(h.channel.needsRelease)
            XCTAssertEqual(h.channel.downResponsibilities.last?.phase, .retainedForExplicitRecovery)
            let fresh = MenuBarOperationStop(); h.channel.bindOperationStop(fresh)
            XCTAssertThrowsError(try h.channel.authorize(h.lease))
            XCTAssertEqual(fresh.snapshot.reason, .possibleDown)
        }
    }
    func testUpRouteFailureIsUnconfirmedAndRetained() throws {
        let h = try Harness()
        XCTAssertThrowsError(try h.bound {
            try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture)
            h.pidHook = { throw Harness.Fault.uncertain }
            try h.channel.emit(h.event(.leftMouseUp), gesture: h.gesture)
        })
        XCTAssertEqual(h.channel.downResponsibilities.last?.phase, .upAttempted)
        XCTAssertTrue(h.channel.needsRelease)
    }
    func testDifferentMouseNumberCannotDischargeTheRecordedDown() throws {
        let h = try Harness()
        XCTAssertThrowsError(try h.bound {
            try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture)
            try h.channel.emit(h.event(.leftMouseUp, number: 13), gesture: h.gesture)
        })
        XCTAssertEqual(h.sessionTypes, [.leftMouseDown]); XCTAssertEqual(h.pidTypes, [.leftMouseDown])
        XCTAssertTrue(h.channel.needsRelease); XCTAssertEqual(h.channel.downResponsibilities.last?.phase, .possibleDown)
    }
    func testNormalPairRecordsDeliveryWithoutPhysicalReleaseProof() throws {
        let h = try Harness()
        try h.bound {
            try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture)
            try h.channel.emit(h.event(.leftMouseUp), gesture: h.gesture)
        }
        XCTAssertEqual(h.sessionTypes, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(h.pidTypes, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(h.channel.downResponsibilities.last?.phase, .pairDelivered)
        XCTAssertEqual(h.channel.downResponsibilities.last?.downRoutes, ["session", "pid"])
        XCTAssertEqual(h.channel.downResponsibilities.last?.upRoutes, ["session", "pid"])
        XCTAssertFalse(h.channel.needsRelease); XCTAssertNil(h.stop.snapshot.reason)
    }
    func testStopDuringAdmittedCallAllowsOnlyThatInFlightCall() throws {
        let h = try Harness(); h.sessionHook = { h.stop.request(.externalInput) }
        XCTAssertThrowsError(try h.bound { try h.channel.emit(h.event(.leftMouseDown), gesture: h.gesture) })
        XCTAssertEqual(h.sessionTypes.count, 1); XCTAssertTrue(h.pidTypes.isEmpty)
        XCTAssertEqual(h.stop.snapshot.effectsAdmitted, 1); XCTAssertNil(h.stop.snapshot.effectInFlight)
    }
    func testRealListenerCallbacksAndUnavailableReadFeedSharedLatchWithoutStartingTap() throws {
        for type in [CGEventType.mouseMoved, .tapDisabledByTimeout, .tapDisabledByUserInput] {
            let input = MenuBarListenOnlyInterferenceSource(), stop = MenuBarOperationStop()
            input.bindOperationStop(stop)
            let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!
            input.receive(type, e)
            XCTAssertEqual(stop.snapshot.reason, type == .mouseMoved ? .externalInput : .monitorLost)
            XCTAssertFalse(input.diagnostics().created)
            input.bindOperationStop(nil)
        }
        let input = MenuBarListenOnlyInterferenceSource(), stop = MenuBarOperationStop()
        input.bindOperationStop(stop); _ = input.read()
        XCTAssertEqual(stop.snapshot.reason, .monitorLost)
        XCTAssertFalse(input.diagnostics().created)
    }
    func testStickyStopCannotBeResetByReceiptOrNewCheckAndCancellationClosureExpires() throws {
        let stop = MenuBarOperationStop(); var checks = 0
        XCTAssertThrowsError(try stop.withCancellation({ checks += 1; return true }) { try stop.check() })
        let count = checks; stop.request(.failed)
        XCTAssertThrowsError(try stop.check()); XCTAssertEqual(checks, count)
        XCTAssertEqual(stop.snapshot.reason, .cancelled)
        XCTAssertThrowsError(try stop.perform("restore") {})
    }
    func testConcurrentStopIsAcceptedWhileAnAdmittedEffectIsWaiting() throws {
        let stop = MenuBarOperationStop(), entered = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0)
        let ended = expectation(description: "admitted call returns")
        DispatchQueue.global().async {
            defer { ended.fulfill() }
            try? stop.perform("already-admitted") { entered.signal(); _ = finish.wait(timeout: .now() + 1) }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        stop.request(.cancelled)
        XCTAssertEqual(stop.snapshot.reason, .cancelled)
        XCTAssertEqual(stop.snapshot.effectInFlight, "already-admitted")
        XCTAssertThrowsError(try stop.perform("second-effect") {})
        finish.signal(); wait(for: [ended], timeout: 2)
        XCTAssertNil(stop.snapshot.effectInFlight); XCTAssertEqual(stop.snapshot.effectsAdmitted, 1)
    }
    func testCancellationProviderCannotRunOnAnotherThread() throws {
        let stop = MenuBarOperationStop(); var checks = 0
        try stop.withCancellation({ checks += 1; return false }) {
            let checked = expectation(description: "foreign check refused")
            DispatchQueue.global().async {
                defer { checked.fulfill() }
                do { try stop.check(); XCTFail("foreign thread must not invoke cancellation provider") }
                catch { XCTAssertEqual(error as? MenuBarOperationStop.Failure, .wrongThread) }
                stop.request(.cancelled)
            }
            wait(for: [checked], timeout: 2); XCTAssertEqual(checks, 0)
        }
        XCTAssertEqual(stop.snapshot.reason, .cancelled)
    }
}
