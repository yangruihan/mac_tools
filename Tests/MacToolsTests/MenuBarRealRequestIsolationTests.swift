// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

/// Offline isolation tests: no native source, window, permission or send.
final class MenuBarRealRequestIsolationTests: XCTestCase {
    typealias A = MenuBarRealLocalAuthorization
    typealias H = MenuBarRequestWarmupTests.Harness
    typealias L = MenuBarLocalContinuityLedger
    final class Source: MenuBarHiddenInterferenceSource {
        var reads = 0, drains = 0
        func read() -> MenuBarMoveInterference.Availability { reads += 1; return .unavailable(.sourceLost) }
        func drainEvents() -> [MenuBarMoveInterference.Event] { drains += 1; return [] }
    }
    func testCompiledNativeAuthorityIsIndependentOfInjectedPolicy() throws {
        #if OWNED_LIVE_CONTROLLER
        XCTAssertEqual(A.nativeAuthority, .nativeRealWorker); XCTAssertEqual(A.nativeStartPolicy, .requestQuietReal)
        #elseif REAL_INPUT_DIAGNOSTIC
        XCTAssertEqual(A.nativeAuthority, .nativeDiagnostic)
        #if REQUEST_WARMUP_DIAGNOSTIC
        XCTAssertEqual(A.nativeStartPolicy, .requestQuietDiagnostic)
        #else
        XCTAssertEqual(A.nativeStartPolicy, .preUpContinuity)
        #endif
        #else
        XCTAssertEqual(A.nativeAuthority, .unavailableNative); XCTAssertEqual(A.nativeStartPolicy, .preUpContinuity)
        #endif
        for policy in [L.StartPolicy.requestQuietReal, .requestQuietDiagnostic] {
            let h = try H(startPolicy: policy)
            XCTAssertEqual(h.broker.authority, .isolated)
            XCTAssertFalse(h.broker.monitor.diagnostics().native)
            var noMove = L(session: UUID(), pid: 1, purpose: .noMove, startPolicy: policy)
            XCTAssertEqual(noMove.state, .stopped(.identity))
            noMove.configure(window: 1); XCTAssertEqual(noMove.state, .stopped(.identity))
        }
    }
    func testRealRequestNeedsEntireQuietWindowCountdownAndFreshReadsInBothOrders() throws {
        for first in [true, false] {
            let h = try H(startPolicy: .requestQuietReal); try h.request(appKitFirst: first)
            let request = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
            XCTAssertNil(h.broker.monitor.ledger.proof); XCTAssertThrowsError(try h.broker.permit())
            XCTAssertEqual(request.hidCounter, 101) // Original count is retained, never decremented.
            XCTAssertEqual(request.quietDeadline! - request.warmupStartedAt!, 250_000_000)
            try h.quietWindow()
            let proof = try XCTUnwrap(h.broker.monitor.ledger.proof)
            XCTAssertGreaterThanOrEqual(proof.matchedAt, request.quietDeadline!)
            XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
            XCTAssertThrowsError(try h.broker.permit()); try h.countdown()
            XCTAssertEqual(h.broker.monitor.ledger.validationCount, 1)
            let permit = try h.broker.permit()
            XCTAssertEqual(permit.authority, .isolated); XCTAssertFalse(permit.diagnosticOnly)
            // Selecting the real algorithm cannot turn this injected proof
            // into a native real worker, even after all timing checks pass.
            XCTAssertThrowsError(try permit.checkForRealAction(binding: h.broker.binding))
            let source = Source(); var gate = MenuBarMoveInterference.Gate()
            XCTAssertThrowsError(try A.armAndHandoff(h.fixture.plan(), permit: permit, input: source, gate: &gate, now: { h.time / 1_000_000 }))
            XCTAssertNil(gate.lease); XCTAssertEqual(source.reads, 0); XCTAssertEqual(source.drains, 0)
            XCTAssertFalse(permit.consumed); XCTAssertFalse(permit.handedOff)
        }
    }
    func testDiagnosticAndInjectedRealPermitsCannotWriteEitherActionMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("real-request-markers-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for policy in [L.StartPolicy.requestQuietDiagnostic, .requestQuietReal] {
            let h = try H(startPolicy: policy); try h.request(); try h.quietWindow(); try h.countdown()
            let permit = try h.broker.permit(), round = root.appendingPathComponent("round")
            XCTAssertThrowsError(try MenuBarRealActionConsumption.consumeAuthorized(round: round, session: root,
                binding: h.broker.binding, permit: permit)) { XCTAssertEqual(String(describing: $0), "nonNative") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: round.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("run-consumed").path))
            XCTAssertFalse(permit.consumed)
        }
    }
    func testRealPolicyLaterInputPermanentlyStopsEveryAuthorizationPhase() throws {
        for phase in ["warmup", "countdown", "validated"] {
            for kind in ["tap", "repeatUp", "counter", "age", "held", "modifier", "health", "fence", "fenceLoss", "gap", "cancel"] {
                let h = try H(startPolicy: .requestQuietReal); try h.request()
                if phase != "warmup" { try h.quietWindow() }
                if phase == "validated" { try h.countdown() }
                let before = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
                let deadline = h.broker.monitor.ledger.proof?.deadline
                h.time += kind == "gap" ? 600_000_000 : 10_000_000
                switch kind {
                case "tap": h.broker.monitor.receive(.mouseMoved, event: h.event())
                case "repeatUp": h.broker.monitor.receive(.leftMouseUp, event: h.event())
                case "counter": h.count += 1
                case "age": h.hid = h.time
                case "held": h.buttons = 1 << 8
                case "modifier": h.modifiers = 1
                case "health": h.healthy = false
                case "fence": h.eventCount += 1
                case "fenceLoss": h.fenceHealthy = false
                case "cancel": h.broker.cancel()
                default: break
                }
                XCTAssertThrowsError(try h.broker.poll(), phase + kind)
                XCTAssertEqual(h.broker.monitor.ledger.requestBoundary, before)
                XCTAssertEqual(h.broker.monitor.ledger.proof?.deadline, deadline)
                h.staysStopped()
            }
        }
    }
    func testRealPolicyCatchesInputDuringQuietRescanFinalRescanAndFenceRead() throws {
        for boundary in ["warmup", "countdown", "fence", "permit"] {
            let h = try H(startPolicy: .requestQuietReal); try h.request()
            if boundary != "warmup" { try h.quietWindow() }
            if boundary == "permit" {
                try h.countdown(); let permit = try h.broker.permit()
                h.fenceHook = { h.count += 1 }
                XCTAssertThrowsError(try permit.check(h.fixture.plan()))
            } else if boundary == "fence" {
                h.fenceHook = { h.count += 1 }; XCTAssertThrowsError(try h.broker.poll())
            } else {
                let phase: L.State = boundary == "warmup" ? .awaitingRequestQuiet : .awaitingFreshQuiet
                var injected = false
                h.pumpHook = { if h.broker.monitor.state == phase { injected = true; h.count += 1 } }
                for _ in 0..<32 { h.time += 100_000_000; do { try h.broker.poll() } catch { break } }
                XCTAssertTrue(injected)
            }
            XCTAssertTrue(h.broker.monitor.ledger.stopped); h.staysStopped()
        }
    }
    #if OWNED_LIVE_CONTROLLER
    func testRealBuildRejectsAbsentAndLegacyIsolatedPermitBeforeInputRead() throws {
        let source = Source(); var gate = MenuBarMoveInterference.Gate()
        let h = try MenuBarRealLocalAuthorizationTests.Harness(); try h.start(); try h.finish()
        let permit = try h.broker.permit()
        for candidate in [nil, permit] {
            XCTAssertThrowsError(try A.armAndHandoff(h.fixture.plan(), permit: candidate, input: source, gate: &gate, now: { 0 }))
            XCTAssertEqual(source.reads, 0); XCTAssertEqual(source.drains, 0); XCTAssertNil(gate.lease)
        }
        XCTAssertFalse(permit.consumed)
    }
    #endif
}
