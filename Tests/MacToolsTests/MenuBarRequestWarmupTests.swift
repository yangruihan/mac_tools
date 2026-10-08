// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
import CryptoKit
@testable import MacTools

/// Native entry dependencies are injected. Nothing creates a window, tap,
/// permission prompt, native input read or event post.
final class MenuBarRequestWarmupTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    typealias A = MenuBarRealLocalAuthorization
    private struct Capture: Decodable {
        let localStartTerminal: MenuBarCapturedStartBoundaryTests.Snapshot
    }
    private func captured() throws -> MenuBarCapturedStartBoundaryTests.Snapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/evidence/menu-bar-real-local-user-round-2026-10-05/session/result.json"))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sha, "fbb4b112664f3f0460a08f4285cc7ce43480540479ef78d98df9c2996a413ea8")
        return try JSONDecoder().decode(Capture.self, from: data).localStartTerminal
    }
    private func feed(_ node: L.Node, into ledger: inout L) throws {
        switch node.kind {
        case .sample: ledger.sampled(try XCTUnwrap(node.sample))
        case .ownUp: ledger.event(ownPacket: try XCTUnwrap(node.packet), at: node.observedAt)
        case .activity: ledger.event(ownPacket: nil, at: node.observedAt)
        case .loss: ledger.lost(at: node.observedAt)
        }
    }
    private func record<T: Encodable>(_ name: String, value: T) throws {
        guard let directory = ProcessInfo.processInfo.environment["MAC_TOOLS_REQUEST_WARMUP_EVIDENCE_DIRECTORY"] else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"), options: .atomic)
    }
    func testUnmodifiedHumanTraceBecomesRequestOnlyNeverNativeAuthorization() throws {
        let c = try captured()
        for appKitFirst in [true, false] {
            var ledger = L(session: c.binding.nonce, pid: c.binding.controllerPID, purpose: .realStart, startPolicy: .requestQuietDiagnostic)
            ledger.configure(window: 325664)
            for node in c.input.nodes {
                if node.sequence == 312 && appKitFirst { ledger.begin(c.capturedStart, at: c.capturedStart.timestamp) }
                try feed(node, into: &ledger)
                if node.sequence == 313 && !appKitFirst { ledger.begin(c.capturedStart, at: node.observedAt) }
            }
            ledger.claim(at: c.atUptimeNanoseconds)
            XCTAssertEqual(ledger.state, .requestMatched)
            XCTAssertNil(ledger.proof); XCTAssertEqual(ledger.validationCount, 0)
            let request = try XCTUnwrap(ledger.requestBoundary)
            XCTAssertEqual(request.guardSequence, 313); XCTAssertEqual(request.hidCounter, 29361011)
            XCTAssertEqual(request.hidActivityUpperBound, 1539482624211791)
            XCTAssertEqual(request.packet, c.capturedStart)
            XCTAssertNil(request.warmupStartedAt); XCTAssertNil(request.quietDeadline)
            let retained = c.input.nodes.filter { $0.observedAt >= c.capturedStart.timestamp - 250_000_000 }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(ledger.nodes), try encoder.encode(retained)) // No prefix deletion, counter rewrite or attribution.
            XCTAssertTrue(ledger.requestReceiptHistoryValid)
            XCTAssertFalse(request.receiptHistory!.activityTimesComplete) // Historical trace omitted event type/time.
            try record("human-request-only-\(appKitFirst)", value: request)
            // The recording ends here: no invented quiet continuation or fence.
            var extended = ledger
            let started = c.atUptimeNanoseconds + 1
            extended.startRequestWarmup(at: started) // Explicit injected fence boundary, not a native observation.
            var injectedSamples = 0
            func sample(_ at: UInt64) -> L.Sample {
                injectedSamples += 1
                return .init(began: at, ended: at + 1_000, counterBefore: 29361011, counterAfter: 29361011,
                    age: Double(at - c.capturedStart.timestamp) / 1_000_000_000,
                    buttons: 0, modifiers: 0, healthyBefore: true, healthyAfter: true)
            }
            for step in 1...34 {
                let at = started + UInt64(step) * 100_000_000
                extended.sampled(sample(at))
                if extended.state == .awaitingRequestQuiet || extended.state == .awaitingFreshQuiet {
                    let first = extended.lastSequence + 1, isWarmup = extended.state == .awaitingRequestQuiet
                    extended.sampled(sample(at + 10_000)); extended.sampled(sample(at + 20_000))
                    if isWarmup { extended.completeRequestQuiet(firstNewSequence: first, at: at + 21_000) }
                    else { extended.complete(firstNewSequence: first, at: at + 21_000) }
                }
            }
            XCTAssertEqual(extended.state, .validatedRealInput); XCTAssertEqual(extended.validationCount, 1)
            XCTAssertEqual(extended.requestBoundary?.hidActivityUpperBound, request.hidActivityUpperBound)
            XCTAssertEqual(extended.requestBoundary?.hidCounter, request.hidCounter)
            struct ExtensionReport: Encodable {
                let scope = "offlineHumanPrefixWithInjectedFenceAndQuietSuffix"
                let realPhysicalStartValidated = false, nativePermitIssued = false
                let originalNodeCount, injectedSampleCount: Int
                let proof: L.Proof
            }
            try record("human-with-injected-quiet-\(appKitFirst)", value: ExtensionReport(
                originalNodeCount: c.input.nodes.count, injectedSampleCount: injectedSamples, proof: try XCTUnwrap(extended.proof)))
            XCTAssertNil(ledger.proof) // The original-only replay still has no authorization evidence.
        }
    }
    func testActivityBetweenFirstPostUpSampleAndRequestClaimCannotBeRebased() throws {
        let c = try captured()
        for kind in ["tap", "repeatUp", "counter", "age", "held", "loss", "unstableFirstRead"] {
            var ledger = L(session: c.binding.nonce, pid: c.binding.controllerPID, purpose: .realStart, startPolicy: .requestQuietDiagnostic)
            ledger.configure(window: 325664)
            for node in c.input.nodes {
                if node.sequence == 312 { ledger.begin(c.capturedStart, at: c.capturedStart.timestamp) }
                if node.sequence == 314 && (kind == "tap" || kind == "repeatUp") {
                    ledger.event(ownPacket: kind == "repeatUp" ? c.capturedStart : nil, at: node.sample!.began - 1)
                }
                if node.sequence == 314 || (node.sequence == 313 && kind == "unstableFirstRead"), let s = node.sample {
                    ledger.sampled(.init(began: s.began, ended: s.ended, counterBefore: s.counterBefore,
                        counterAfter: (kind == "counter" || kind == "unstableFirstRead") ? s.counterAfter! + 1 : s.counterAfter,
                        age: kind == "age" ? 0 : s.age, buttons: kind == "held" ? 1 << 8 : s.buttons,
                        modifiers: s.modifiers, healthyBefore: s.healthyBefore, healthyAfter: kind != "loss"))
                } else { try feed(node, into: &ledger) }
            }
            ledger.claim(at: c.atUptimeNanoseconds)
            XCTAssertTrue(ledger.stopped, kind); XCTAssertNil(ledger.proof); XCTAssertNil(ledger.requestBoundary)
            XCTAssertEqual(ledger.validationCount, 0)
            let failure = ledger.firstFailure
            ledger.startRequestWarmup(at: c.atUptimeNanoseconds + 1)
            XCTAssertEqual(ledger.firstFailure, failure)
            try record("human-injected-\(kind)", value: try XCTUnwrap(failure))
        }
    }
    final class Harness {
        let fixture = MenuBarHiddenMoveFixture()
        var time: UInt64 = 1_000_000_000, count: UInt32 = 100, hid: UInt64 = 900_000_000
        var buttons: UInt64 = 0, modifiers: UInt64 = 0, healthy = true, fenceHealthy = true
        var continuity = UUID(), epoch = UUID(), eventCount = 2, fenceReads = 0
        var fenceHook: (() -> Void)?, pumpHook: (() -> Void)?
        var broker: A!
        var layoutHook: (() throws -> MenuBarHiddenMoveModel.Plan)?
        init(startPolicy: L.StartPolicy = .requestQuietDiagnostic, capturesLayout: Bool = false) throws {
            let binding = MenuBarDispatchWitness.Binding(nonce: fixture.original.owner.nonce, targetPID: fixture.original.owner.target.pid,
                controllerPID: 123, controllerLaunch: 10, controllerSHA256: String(repeating: "a", count: 64))
            let reads = MenuBarLocalStartInput.Reads(now: { self.time }, counter: { self.count },
                age: { Double(self.time - self.hid) / 1_000_000_000 }, buttons: { self.buttons }, modifiers: { self.modifiers },
                healthy: { self.healthy }, pump: { self.pumpHook?() })
            broker = A(binding: binding, plan: try fixture.plan(), reads: reads, fence: {
                self.fenceReads += 1; self.fenceHook?()
                guard self.fenceHealthy else { throw A.Failure.interference }
                return .init(continuity: self.continuity, epoch: self.epoch, eventCount: self.eventCount)
            }, expires: 10_000_000_000, startPolicy: startPolicy, captureActionLayout: capturesLayout ? {
                guard let hook = self.layoutHook else { throw A.Failure.layout("missingTestProvider") }
                return try hook()
            } : nil)
            broker.monitor.configureLocalStart(window: 7)
        }
        func event(_ type: CGEventType = .leftMouseUp) -> CGEvent {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .init(x: 894, y: 354), mouseButton: .left)!
            e.timestamp = type == .leftMouseDown ? 1_010_000_000 : 1_050_000_000; e.flags = []
            e.setIntegerValueField(.mouseEventNumber, value: 0)
            e.setIntegerValueField(.eventSourceUnixProcessID, value: 996)
            e.setIntegerValueField(.eventSourceStateID, value: 1)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 7)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 7)
            return e
        }
        func request(appKitFirst: Bool = false) throws {
            time = 1_010_000_000; buttons = 1
            broker.monitor.receive(.leftMouseDown, event: event(.leftMouseDown))
            if appKitFirst { time = 1_050_100_000; broker.begin(event()) }
            time = 1_051_000_000; buttons = 0; count = 101; hid = 1_050_000_000
            broker.monitor.receive(.leftMouseUp, event: event())
            time = 1_060_000_000
            if !appKitFirst { broker.begin(event()) }
            try broker.poll()
            XCTAssertEqual(broker.monitor.state, .warmingRequest)
            XCTAssertGreaterThan(fenceReads, 0)
        }
        func quietWindow() throws {
            for _ in 0..<3 { time += 100_000_000; try broker.poll() }
            XCTAssertEqual(broker.monitor.state, .countdown)
        }
        func countdown() throws {
            for _ in 0..<30 { time += 100_000_000; try broker.poll() }
            XCTAssertEqual(broker.monitor.state, .validatedRealInput)
        }
        func staysStopped() {
            let failure = broker.monitor.ledger.firstFailure
            healthy = true; fenceHealthy = true; buttons = 0; modifiers = 0; fenceHook = nil; pumpHook = nil
            time += 4_000_000_000
            XCTAssertThrowsError(try broker.poll()); XCTAssertThrowsError(try broker.permit())
            XCTAssertEqual(broker.monitor.ledger.firstFailure, failure)
        }
    }
    func testSameBrokerRequiresFencedQuietWindowThenFullCountdownAndSinglePermit() throws {
        for appKitFirst in [true, false] {
            let h = try Harness(); try h.request(appKitFirst: appKitFirst)
            let request = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
            XCTAssertNil(h.broker.monitor.ledger.proof); XCTAssertEqual(h.broker.monitor.ledger.validationCount, 0)
            XCTAssertEqual(request.quietDeadline! - request.warmupStartedAt!, 250_000_000)
            XCTAssertThrowsError(try h.broker.permit())
            try h.quietWindow()
            let proof = try XCTUnwrap(h.broker.monitor.ledger.proof)
            XCTAssertGreaterThanOrEqual(proof.matchedAt, request.quietDeadline!)
            XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
            XCTAssertEqual(proof.hidCounter, 101); XCTAssertEqual(proof.hidActivityUpperBound, request.hidActivityUpperBound)
            XCTAssertThrowsError(try h.broker.permit()); try h.countdown()
            let permit = try h.broker.permit()
            XCTAssertTrue(permit.diagnosticOnly); XCTAssertThrowsError(try h.broker.permit())
            let lease = MenuBarMoveInterference.Lease(gesture: UUID(), continuity: h.continuity, externalEpoch: h.epoch, interferenceEpoch: UUID())
            try permit.handoff(h.fixture.plan(), lease: lease)
            XCTAssertTrue(permit.handedOff); XCTAssertTrue(permit.consumed)
            XCTAssertThrowsError(try permit.check(h.fixture.plan()))
            try record("injected-complete-\(appKitFirst)", value: h.broker.monitor.evidence())
        }
    }
    func testWarmupAndCountdownActivityPermanentlyStopWithoutRestartingTimer() throws {
        for inCountdown in [false, true] {
            for kind in ["tap", "repeatUp", "counter", "ageOnly", "button", "modifier", "health", "fence", "fenceLoss", "gap"] {
                let h = try Harness(); try h.request()
                if inCountdown { try h.quietWindow() }
                let request = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
                h.time += kind == "gap" ? 600_000_000 : 10_000_000
                switch kind {
                case "tap": h.broker.monitor.receive(.mouseMoved, event: h.event())
                case "repeatUp": h.broker.monitor.receive(.leftMouseUp, event: h.event())
                case "counter": h.count += 1
                case "ageOnly": h.hid = h.time
                case "button": h.buttons = 1 << 8
                case "modifier": h.modifiers = 1
                case "health": h.healthy = false
                case "fence": h.eventCount += 1
                case "fenceLoss": h.fenceHealthy = false
                default: break
                }
                XCTAssertThrowsError(try h.broker.poll(), kind)
                XCTAssertTrue(h.broker.monitor.ledger.stopped)
                XCTAssertEqual(h.broker.monitor.ledger.requestBoundary?.warmupStartedAt, request.warmupStartedAt)
                XCTAssertEqual(h.broker.monitor.ledger.requestBoundary?.hidCounter, request.hidCounter)
                XCTAssertEqual(h.broker.monitor.ledger.validationCount, 0)
                h.staysStopped()
                try record("stopped-\(inCountdown)-\(kind)", value: try XCTUnwrap(h.broker.monitor.ledger.firstFailure))
            }
        }
    }
    func testFirstFenceAndFinalHandoffGapsRemainGuarded() throws {
        for late in [false, true] {
            let h = try Harness()
            if late { try h.request(); try h.quietWindow(); try h.countdown() }
            h.fenceHook = { h.count += 1 }
            if late {
                XCTAssertThrowsError(try h.broker.permit())
            } else {
                XCTAssertThrowsError(try h.request())
                XCTAssertNil(h.broker.monitor.ledger.requestBoundary?.warmupStartedAt)
            }
            XCTAssertTrue(h.broker.monitor.ledger.stopped); h.staysStopped()
        }
    }
    func testActivityDuringEitherFreshRescanCannotCompleteQuietOrCountdown() throws {
        for inCountdown in [false, true] {
            let h = try Harness(); try h.request()
            if inCountdown { try h.quietWindow() }
            let phase: L.State = inCountdown ? .awaitingFreshQuiet : .awaitingRequestQuiet
            var injected = false
            h.pumpHook = {
                if h.broker.monitor.state == phase { injected = true; h.count += 1 }
            }
            for _ in 0..<32 {
                h.time += 100_000_000
                do { try h.broker.poll() } catch { break }
            }
            XCTAssertTrue(injected); XCTAssertEqual(h.broker.monitor.state, .stopped(.laterInput))
            XCTAssertEqual(h.broker.monitor.ledger.validationCount, 0)
            if !inCountdown { XCTAssertNil(h.broker.monitor.ledger.proof) }
            h.staysStopped()
        }
    }
    func testWarmupPermitIsConfinedToDiagnosticHandoff() throws {
        final class Source: MenuBarHiddenInterferenceSource {
            let harness: Harness
            var reads = 0, drains = 0
            init(_ harness: Harness) { self.harness = harness }
            func read() -> MenuBarMoveInterference.Availability {
                reads += 1
                return .available(.init(sequence: UInt64(reads), uptimeMilliseconds: harness.time / 1_000_000,
                    continuity: harness.continuity, externalEpoch: harness.epoch,
                    coverage: MenuBarMoveInterference.requiredCoverage, buttons: [], keys: [], modifiers: 0))
            }
            func drainEvents() -> [MenuBarMoveInterference.Event] { drains += 1; return [] }
        }
        let h = try Harness(); try h.request(); try h.quietWindow(); try h.countdown()
        let permit = try h.broker.permit()
        let source = Source(h)
        var gate = MenuBarMoveInterference.Gate()
        #if REAL_INPUT_DIAGNOSTIC
        try A.armAndHandoff(h.fixture.plan(), permit: permit, input: source, gate: &gate, now: { h.time / 1_000_000 })
        XCTAssertEqual(gate.state, .armed); XCTAssertTrue(permit.handedOff); XCTAssertTrue(permit.consumed)
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.drains, 1)
        XCTAssertThrowsError(try A.armAndHandoff(h.fixture.plan(), permit: permit, input: source, gate: &gate, now: { h.time / 1_000_000 }))
        XCTAssertEqual(source.reads, 1)
        #else
        XCTAssertThrowsError(try A.armAndHandoff(h.fixture.plan(), permit: permit, input: source, gate: &gate, now: { 0 })) {
            XCTAssertEqual(String(describing: $0), "nonNative")
        }
        XCTAssertFalse(permit.consumed); XCTAssertNil(gate.lease)
        XCTAssertEqual(source.reads, 0); XCTAssertEqual(source.drains, 0)
        #endif
    }
}
