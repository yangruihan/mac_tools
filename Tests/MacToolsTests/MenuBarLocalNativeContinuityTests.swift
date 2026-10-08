// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

/// Exercises the actual no-move adapter and ledger together. Native reads and
/// callback delivery are injected; CGEvents stay in memory, never posted.
final class MenuBarLocalNativeContinuityTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    final class Harness {
        var time: UInt64 = 1_000_000_000, count: UInt32? = 100, lastHID: UInt64 = 900_000_000
        var buttons: UInt64 = 0, modifiers: UInt64 = 0, healthy = true
        var ageHook: (() -> Void)?, pumpHook: (() -> Void)?
        var monitor: MenuBarLocalNoMoveInput!
        init(configure: Bool = true, startPolicy: L.StartPolicy = .preUpContinuity) {
            let reads = MenuBarLocalNoMoveInput.Reads(now: { [unowned self] in self.time },
                counter: { [unowned self] in self.count }, age: { [unowned self] in
                    self.ageHook?(); return Double(self.time - self.lastHID) / 1_000_000_000
                }, buttons: { [unowned self] in self.buttons }, modifiers: { [unowned self] in self.modifiers },
                healthy: { [unowned self] in self.healthy }, pump: { [unowned self] in self.pumpHook?() })
            monitor = .init(session: UUID(), pid: 123, isolatedReads: reads,
                purpose: startPolicy.usesRequestQuiet ? .realStart : .noMove, startPolicy: startPolicy)
            if configure { monitor.configureLocalStart(window: 7) }
        }
        func event(_ type: CGEventType = .leftMouseUp, timestamp: UInt64 = 1_050_000_000,
                   pointerWindow: Int64 = 7, handlingWindow: Int64 = 7, number: Int64 = -20895) -> CGEvent {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .init(x: 864, y: 355), mouseButton: .left)!
            e.timestamp = timestamp; e.setIntegerValueField(.mouseEventNumber, value: number)
            e.setIntegerValueField(.eventSourceUnixProcessID, value: 456)
            e.setIntegerValueField(.eventSourceStateID, value: 1690226100)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: pointerWindow)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: handlingWindow)
            return e
        }
        func down() {
            time = 1_010_000_000; monitor.receive(.leftMouseDown, event: event(.leftMouseDown, timestamp: time))
        }
        @discardableResult func start(appKitFirst: Bool = true) -> CGEvent {
            down(); let up = event()
            if appKitFirst {
                time = 1_050_100_000; monitor.beginStart(.init(up)); monitor.matchStart()
                XCTAssertEqual(monitor.state, .awaitingReceipt)
            }
            time = 1_051_000_000; monitor.receive(.leftMouseUp, event: up)
            time = 1_060_000_000
            if !appKitFirst { monitor.beginStart(.init(up)) }
            monitor.matchStart()
            XCTAssertEqual(monitor.state, .countdown)
            return up
        }
        func finish() {
            for t in stride(from: UInt64(1_160_000_000), through: 4_060_000_000, by: 100_000_000) {
                time = t; monitor.poll()
            }
        }
        func remainsStopped(file: StaticString = #filePath, line: UInt = #line) {
            let first = monitor.state; healthy = true; buttons = 0; modifiers = 0; ageHook = nil; pumpHook = nil
            finish()
            XCTAssertEqual(monitor.state, first, file: file, line: line)
            XCTAssertEqual(monitor.ledger.validationCount, 0, file: file, line: line)
            guard case .stopped = first else { return XCTFail("must remain stopped", file: file, line: line) }
        }
    }

    func testBothCallbackOrdersUseRealAdapterAndNewPostDeadlineScan() throws {
        for appKitFirst in [true, false] {
            let h = Harness(); let up = h.start(appKitFirst: appKitFirst); h.finish()
            XCTAssertEqual(h.monitor.state, .validatedNoMove)
            XCTAssertEqual(h.monitor.ledger.validationCount, 1)
            let evidence = h.monitor.evidence(), proof = try XCTUnwrap(evidence.proof)
            XCTAssertEqual(evidence.scope, "isolatedInjectedNativeAdapter")
            XCTAssertEqual(proof.packet, .init(up)); XCTAssertEqual(proof.packet.number, -20895)
            XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
            XCTAssertLessThan(proof.anchorSequence, proof.upSequence)
            XCTAssertLessThan(proof.upSequence, proof.matchSequence)
            XCTAssertLessThan(proof.hidActivityUpperBound, proof.packet.timestamp)
            let final = try XCTUnwrap(evidence.nodes.first { $0.sequence == evidence.finalSampleSequence })
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(final.sample).began, proof.deadline)
            XCTAssertTrue(evidence.nodes.allSatisfy { $0.sample?.valid ?? true })
            for (a,b) in zip(evidence.nodes, evidence.nodes.dropFirst()) { XCTAssertEqual(b.sequence, a.sequence + 1) }
            XCTAssertFalse(h.monitor.diagnostics().native)
            if let directory = ProcessInfo.processInfo.environment["MAC_TOOLS_LOCAL_ADAPTER_EVIDENCE_DIRECTORY"] {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let file = URL(fileURLWithPath: directory).appendingPathComponent(appKitFirst ? "injected-appkit-first.json" : "injected-tap-first.json")
                try encoder.encode(evidence).write(to: file, options: .atomic)
            }
        }
    }
    func testHIDActivityBeforeFirstUpSampleCannotBeAbsorbedIntoBaseline() {
        let h = Harness(); h.down(); let up = h.event()
        h.time = 1_050_100_000; h.monitor.beginStart(.init(up))
        h.count = 101; h.lastHID = 1_050_500_000; h.time = 1_051_000_000
        h.monitor.receive(.leftMouseUp, event: up)
        h.time = 1_060_000_000; h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.hidChangedAcrossStart)); h.remainsStopped()
    }
    func testHIDCounterChangeThenReturnBeforeClaimStillRefuses() {
        let h = Harness(); h.down(); let up = h.event(); h.time = 1_051_000_000
        h.monitor.receive(.leftMouseUp, event: up)
        h.count = 101; h.time = 1_052_000_000; h.monitor.poll()
        h.count = 100; h.time = 1_053_000_000; h.monitor.poll()
        h.monitor.beginStart(.init(up)); h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.hidChangedAcrossStart)); h.remainsStopped()
    }
    func testStableCounterDoesNotHideMoreRecentHIDAgeInStartupGap() {
        let h = Harness(); h.down(); let up = h.event(); h.lastHID = 1_050_500_000; h.time = 1_051_000_000
        h.monitor.receive(.leftMouseUp, event: up); h.monitor.beginStart(.init(up)); h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.hidActivityUnproven)); h.remainsStopped()
    }
    func testHardwareLikeOwnUpCounterIncreaseIsNotSubtractedOrExempted() {
        let h = Harness(); h.down(); let up = h.event()
        up.setIntegerValueField(.eventSourceStateID, value: 1)
        h.time = 1_051_000_000; h.count = 101; h.lastHID = up.timestamp
        h.monitor.receive(.leftMouseUp, event: up); h.monitor.beginStart(.init(up)); h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.hidChangedAcrossStart))
        XCTAssertNil(h.monitor.ledger.proof) // Exact Packet is not HID-counter attribution.
    }
    func testMissingOrLatePreUpHistoryNeverBecomesContinuousByWaiting() {
        let h = Harness(configure: false); let up = h.event(); h.time = 1_050_500_000
        h.monitor.configureLocalStart(window: 7); h.time = 1_051_000_000
        h.monitor.receive(.leftMouseUp, event: up); h.monitor.beginStart(.init(up)); h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.missingPreUpAnchor)); h.remainsStopped()
    }
    func testWindowFilterDoesNotRetainForeignCoordinatesOrClaimMissingWindow() throws {
        for window in [Int64(0), 99] {
            let h = Harness(); h.down(); let own = h.event()
            h.time = 1_050_100_000; h.monitor.beginStart(.init(own))
            let foreign = h.event(pointerWindow: window, handlingWindow: window)
            foreign.location = .init(x: 9876543, y: 7654321)
            h.time = 1_051_000_000; h.monitor.receive(.leftMouseUp, event: foreign); h.monitor.matchStart()
            XCTAssertEqual(h.monitor.state, .stopped(.laterInput))
            let text = String(decoding: try JSONEncoder().encode(h.monitor.evidence()), as: UTF8.self)
            XCTAssertFalse(text.contains("9876543")); XCTAssertFalse(text.contains("7654321"))
        }
    }
    func testExactOwnPacketFieldsRemainRequiredInNativeCallbackPath() {
        for field in [CGEventField.mouseEventNumber, .eventSourceUnixProcessID, .eventSourceStateID] {
            let h = Harness(); h.down(); let up = h.event(), changed = up.copy()!
            changed.setIntegerValueField(field, value: changed.getIntegerValueField(field) + 1)
            h.time = 1_050_100_000; h.monitor.beginStart(.init(up))
            h.time = 1_051_000_000; h.monitor.receive(.leftMouseUp, event: changed); h.monitor.matchStart()
            XCTAssertEqual(h.monitor.state, .stopped(.laterInput)); h.remainsStopped()
        }
    }
    func testInputWhileAwaitingUpAndRepeatedOwnUpArePermanentlyTerminal() {
        for duplicate in [false, true] {
            let h = Harness(); h.down(); let up = h.event(); h.time = 1_050_100_000
            h.monitor.beginStart(.init(up)); h.time = 1_051_000_000
            if duplicate { h.monitor.receive(.leftMouseUp, event: up) }
            h.monitor.receive(duplicate ? .leftMouseUp : .mouseMoved, event: up)
            h.monitor.matchStart(); XCTAssertEqual(h.monitor.state, .stopped(.laterInput)); h.remainsStopped()
        }
    }
    func testLossAtTheClickBoundaryAndReconnectCannotEraseHistory() {
        let h = Harness(); h.down(); let up = h.event(); h.time = 1_051_000_000
        h.monitor.receive(.leftMouseUp, event: up)
        h.monitor.receive(.tapDisabledByTimeout, event: up)
        h.monitor.beginStart(.init(up)); h.monitor.matchStart()
        XCTAssertEqual(h.monitor.state, .stopped(.monitorLost))
        XCTAssertEqual(h.monitor.ledger.nodes.last?.kind, .loss); h.remainsStopped()
    }
    func testHIDOnlyInputAndUncountedActivityDuringCountdownAreBothLatched() {
        for incrementsCount in [true, false] {
            let h = Harness(); h.start(); h.time = 1_061_000_000; h.lastHID = 1_060_500_000
            let beforeEpoch = h.monitor.ledger.epoch
            if incrementsCount { h.count = 101 }
            h.monitor.poll()
            XCTAssertEqual(h.monitor.state, .stopped(incrementsCount ? .laterInput : .hidActivityUnproven))
            XCTAssertGreaterThan(h.monitor.ledger.epoch, beforeEpoch)
            h.remainsStopped()
        }
    }
    func testTapOnlyAndPublicStateActivityCannotDisappearWhenQuietReturns() {
        for kind in 0...2 {
            let h = Harness(); h.start(); h.time = 1_160_000_000
            if kind == 0 { h.monitor.receive(.keyDown, event: h.event()) }
            if kind == 1 { h.buttons = 1; h.monitor.poll() }
            if kind == 2 { h.modifiers = 1; h.monitor.poll() }
            XCTAssertEqual(h.monitor.state, .stopped(.laterInput)); h.remainsStopped()
        }
    }
    func testHealthLossWithinReadAndMissingCounterAreNeverIdle() {
        for missing in [true, false] {
            let h = Harness(); h.start(); h.time = 1_160_000_000
            if missing { h.count = nil } else { h.ageHook = { h.healthy = false } }
            h.monitor.poll()
            XCTAssertEqual(h.monitor.state, .stopped(missing ? .invalidSample : .monitorLost)); h.remainsStopped()
        }
    }
    func testActivityDuringPostDeadlineResamplingStopsInsteadOfPassing() {
        let h = Harness(); h.start()
        h.ageHook = {
            if h.monitor.state == .awaitingFreshQuiet { h.count = 101; h.lastHID = h.time }
        }
        h.finish(); XCTAssertEqual(h.monitor.state, .stopped(.laterInput)); h.remainsStopped()
    }
    func testStallBackwardClockCancelAndVirtualStartCannotResume() {
        for reason in 0...3 {
            let h = Harness(); h.start()
            switch reason {
            case 0: h.time += 600_000_000; h.monitor.poll()
            case 1: h.time -= 1; h.monitor.poll()
            case 2: h.monitor.cancel()
            default: h.monitor.receive(.tapDisabledByUserInput, event: h.event())
            }
            h.remainsStopped()
        }
        let h = Harness(); h.time = 1_060_000_000; h.monitor.beginStart(.init(h.event()), virtual: true)
        XCTAssertEqual(h.monitor.state, .stopped(.virtualUnsupported))
        XCTAssertThrowsError(try h.monitor.start()) // Injected backend cannot create a native tap.
    }
    func testReentrantCallbackDuringSamplingCannotManufactureAnAtomicRead() {
        let h = Harness(); h.start(); h.time = 1_160_000_000
        h.ageHook = { h.monitor.receive(.mouseMoved, event: h.event()) }
        h.monitor.poll(); XCTAssertEqual(h.monitor.state, .stopped(.boundaryGap)); h.remainsStopped()
    }
    func testHIDAgeUsesTheConservativeEndOfTheQueryInterval() {
        let uncertain = L.Sample(began: 1100, ended: 1300, counterBefore: 100, counterAfter: 100,
            age: 0.0000001, buttons: 0, modifiers: 0, healthyBefore: true, healthyAfter: true)
        XCTAssertTrue(uncertain.valid)
        // Optimistically using began would give 1000, falsely within bound 1100.
        // The actual latest HID time can be 1200, so unchanged count is insufficient.
        XCTAssertFalse(uncertain.activityNoLaterThan(1100))
        XCTAssertTrue(uncertain.activityNoLaterThan(1300))
        for invalidAge in [Double.nan, .infinity, 2.0] {
            let invalid = L.Sample(began: 1100, ended: 1300, counterBefore: 100, counterAfter: 100,
                age: invalidAge, buttons: 0, modifiers: 0, healthyBefore: true, healthyAfter: true)
            XCTAssertFalse(invalid.activityNoLaterThan(1300)) // Includes an impossible pre-boot time.
        }
    }
}
