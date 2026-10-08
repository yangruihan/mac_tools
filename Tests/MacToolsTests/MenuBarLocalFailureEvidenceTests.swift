// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarLocalFailureEvidenceTests: XCTestCase {
    typealias H = MenuBarLocalNativeContinuityTests.Harness
    typealias L = MenuBarLocalContinuityLedger

    func testEveryStopCausePersistsBeforeCleanupAndCannotBeOverwritten() throws {
        let cases: [(L.Cause, (H) -> Void)] = [
            (.identity, { $0.monitor.beginStart(.init($0.event())) }),
            (.noExactStartReceipt, { h in
                h.down(); h.time = 1_050_100_000; h.monitor.beginStart(.init(h.event()))
                h.time = 1_301_000_000; h.monitor.matchStart()
            }),
            (.missingPreUpAnchor, { h in
                // A newly configured listener has no sample before the up.
                h.time = 1_050_500_000; h.monitor.configureLocalStart(window: 7)
                h.time = 1_051_000_000; h.monitor.receive(.leftMouseUp, event: h.event())
                h.monitor.beginStart(.init(h.event())); h.monitor.matchStart()
            }),
            (.missingReceiptPredecessor, { h in
                h.time = 1_051_000_000; h.monitor.configureLocalStart(window: 7)
                h.monitor.receive(.leftMouseUp, event: h.event())
                h.monitor.beginStart(.init(h.event())); h.monitor.matchStart()
            }),
            (.unprovenReceiptActivity, { h in
                h.time = 1_050_100_000; h.monitor.beginStart(.init(h.event()))
                h.monitor.receive(.mouseMoved, event: h.event(.mouseMoved, timestamp: 0))
            }),
            (.boundaryGap, { h in h.start(); h.time += 600_000_000; h.monitor.poll() }),
            (.hidChangedAcrossStart, { h in
                h.down(); h.time = 1_051_000_000; h.count = 101
                h.monitor.receive(.leftMouseUp, event: h.event()); h.monitor.beginStart(.init(h.event())); h.monitor.matchStart()
            }),
            (.hidActivityUnproven, { h in
                h.down(); h.time = 1_051_000_000; h.lastHID = 1_050_500_000
                h.monitor.receive(.leftMouseUp, event: h.event()); h.monitor.beginStart(.init(h.event())); h.monitor.matchStart()
            }),
            (.laterInput, { h in h.start(); h.monitor.receive(.mouseMoved, event: h.event()) }),
            (.monitorLost, { h in h.healthy = false; h.monitor.poll() }),
            (.invalidSample, { h in h.count = nil; h.monitor.poll() }),
            (.clock, { h in h.time -= 1; h.monitor.poll() }),
            (.overflow, { h in
                h.down(); for _ in 0..<260 { h.monitor.poll() }
                h.time = 1_050_100_000; h.monitor.beginStart(.init(h.event())); h.monitor.poll()
            }),
            (.notQuiet, { h in
                h.down(); h.time = 1_051_000_000; h.buttons = 1
                h.monitor.receive(.leftMouseUp, event: h.event()); h.monitor.beginStart(.init(h.event())); h.monitor.matchStart()
            }),
            (.cancelled, { $0.monitor.cancel() }),
            (.virtualUnsupported, { h in h.time = 1_060_000_000; h.monitor.beginStart(.init(h.event()), virtual: true) })
        ]
        XCTAssertEqual(Set(cases.map(\.0)), Set(L.Cause.allCases))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("all-stop-evidence-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for (cause, inject) in cases {
            let requestCause = cause == .missingReceiptPredecessor || cause == .unprovenReceiptActivity
            let h = H(configure: cause != .missingPreUpAnchor && cause != .missingReceiptPredecessor,
                      startPolicy: requestCause ? .requestQuietReal : .preUpContinuity); inject(h)
            XCTAssertEqual(h.monitor.state, .stopped(cause), cause.rawValue)
            let frozen = h.monitor.evidence(), failure = try XCTUnwrap(frozen.firstFailure)
            XCTAssertEqual(failure.cause, cause)
            XCTAssertFalse(failure.previousState.hasPrefix("stopped")); XCTAssertGreaterThan(failure.line, 0)
            XCTAssertTrue(failure.sourceFile.contains("MenuBarLocal")); XCTAssertFalse(failure.operation.isEmpty)
            let context = MenuBarLocalDiagnosticReceipt.Context(nonce: h.monitor.ledger.session, controllerPID: 123,
                scope: frozen.scope, failure: cause.rawValue, state: frozen.state, startupStage: h.monitor.diagnostics().startupStage,
                nodeCount: frozen.nodes.count, firstFailure: failure)
            let data = try MenuBarLocalDiagnosticReceipt.encode(frozen, context: context)
            let file = root.appendingPathComponent(cause.rawValue + ".json")
            try MenuBarLocalReceiptWriter.writeNew(data, to: file)
            h.monitor.cancel(); h.monitor.stop(); h.healthy = true; h.monitor.poll()
            XCTAssertEqual(h.monitor.ledger.firstFailure, failure) // Cleanup and later healthy state cannot replace cause.
            XCTAssertEqual(try Data(contentsOf: file), data)
            let decoded = try JSONDecoder().decode(MenuBarLocalDiagnosticReceipt.Envelope.self, from: data)
            XCTAssertEqual(decoded.context.firstFailure, failure); XCTAssertNil(decoded.payloadEncodingFailure)
            XCTAssertNotNil(decoded.payload)
            XCTAssertThrowsError(try MenuBarLocalReceiptWriter.writeNew(Data("overwrite".utf8), to: file))
            if let destination = ProcessInfo.processInfo.environment["MAC_TOOLS_STOP_EVIDENCE_DIRECTORY"] {
                try MenuBarLocalReceiptWriter.writeNew(data, to: URL(fileURLWithPath: destination).appendingPathComponent(cause.rawValue + ".json"))
            }
        }
    }

    func testSameCauseDistinguishesSampleReentryFromElapsedCoverageGap() throws {
        let stalled = H(); stalled.start(); stalled.time += 600_000_000; stalled.monitor.poll()
        let reentered = H(); reentered.start(); reentered.time = 1_160_000_000
        reentered.ageHook = { reentered.monitor.receive(.mouseMoved, event: reentered.event()) }
        reentered.monitor.poll()
        let a = try XCTUnwrap(stalled.monitor.ledger.firstFailure), b = try XCTUnwrap(reentered.monitor.ledger.firstFailure)
        XCTAssertEqual(a.cause, .boundaryGap); XCTAssertEqual(b.cause, .boundaryGap)
        XCTAssertNotEqual(a.sourceFile, b.sourceFile); XCTAssertNotEqual(a.operation, b.operation)
        XCTAssertGreaterThan(try XCTUnwrap(a.attemptedObservationAt), try XCTUnwrap(a.lastObservedAt))
    }

    func testNonfinitePayloadStillProducesDurableScalarFailureReceipt() throws {
        let h = H(); h.count = nil; h.monitor.poll()
        let input = h.monitor.evidence()
        let context = MenuBarLocalDiagnosticReceipt.Context(nonce: h.monitor.ledger.session, controllerPID: 123,
            scope: input.scope, failure: "invalidSample", state: input.state, startupStage: "injected",
            nodeCount: input.nodes.count, firstFailure: input.firstFailure)
        struct Invalid: Encodable { let value = Double.nan }
        let bytes = try MenuBarLocalDiagnosticReceipt.encode(Invalid(), context: context)
        let decoded = try JSONDecoder().decode(MenuBarLocalDiagnosticReceipt.Envelope.self, from: bytes)
        XCTAssertNil(decoded.payload); XCTAssertNotNil(decoded.payloadEncodingFailure)
        XCTAssertEqual(decoded.context.firstFailure?.cause, .invalidSample)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("scalar-fallback-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try MenuBarLocalReceiptWriter.writeNew(bytes, to: file)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testStartupRejectionRetainsPreCleanupHealthWithoutStartingNativeTap() throws {
        let h = H()
        XCTAssertThrowsError(try h.monitor.start()) // Injection can never start a native tap.
        let first = try XCTUnwrap(h.monitor.evidence().startupFailure)
        XCTAssertEqual(first.rejectedStage, "policyCheck")
        XCTAssertFalse(first.diagnosticsBeforeCleanup.native)
        XCTAssertTrue(first.diagnosticsBeforeCleanup.monitoringHealthy)
        h.monitor.stop()
        XCTAssertFalse(h.monitor.diagnostics().monitoringHealthy)
        XCTAssertThrowsError(try h.monitor.start())
        let after = try XCTUnwrap(h.monitor.evidence().startupFailure)
        XCTAssertEqual(after.rejectedStage, first.rejectedStage)
        XCTAssertTrue(after.diagnosticsBeforeCleanup.monitoringHealthy)
        XCTAssertEqual(h.monitor.state, .ready) // Diagnostic capture does not create/reset a start claim.
    }
}
