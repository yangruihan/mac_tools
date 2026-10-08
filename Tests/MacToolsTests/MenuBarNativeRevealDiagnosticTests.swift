import XCTest
import AppKit
@testable import MacTools

@MainActor
final class MenuBarNativeRevealDiagnosticTests: XCTestCase {
    func testFirstVerificationFailureSurvivesPhysicalRestoreFailure() async throws {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.didSetLength = { if driver.length >= 0 { driver.targetOnScreen = false } }
        driver.ignoresRestoreGeometry = true
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .needsRecovery)
        XCTAssertEqual(flow.diagnostic.firstFailure?.stage, "after.first.verify")
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.targetNotOnScreen")
        XCTAssertTrue(flow.diagnostic.entries.contains { $0.errorCode == "controller.restorationUnverified" })
        let sample = try XCTUnwrap(flow.diagnostic.entries.last { $0.stage == "after.first.observe" }?.sample)
        XCTAssertFalse(try XCTUnwrap(sample.target).onScreen)
        XCTAssertGreaterThan(try XCTUnwrap(sample.ownedSpacer).width, 38)
        XCTAssertNotNil(journal.record)
        XCTAssertEqual(flow.diagnostic.entries.last?.state, "needsRecovery")
        XCTAssertEqual(flow.diagnostic.entries.last?.event, "recovery-required")
        driver.ignoresRestoreGeometry = false
        await flow.recoverOwnWidth()
        XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.targetNotOnScreen")
    }
    func testReadFailureRecordsItsStageBeforeAutomaticAcknowledgedRestoration() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.throwsAtObservation = 3
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle)
        XCTAssertEqual(flow.diagnostic.firstFailure?.stage, "after.first.observe")
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "controller.staleObservation")
        XCTAssertEqual(flow.diagnostic.entries.last?.event, "restored")
        XCTAssertEqual(driver.writes, [105, -1]); XCTAssertNil(journal.record)
        let entries = flow.diagnostic.entries
        XCTAssertEqual(entries.map(\.sequence), Array(1...entries.count))
        XCTAssertEqual(entries.map(\.elapsedMilliseconds), entries.map(\.elapsedMilliseconds).sorted())
    }
    func testDiagnosticFilePersistsFailureAndRestoredStatePrivately() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-diagnostic-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.didSetLength = { if driver.length >= 0 { driver.orderedIDs = [1, 3, 2] } }
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero, diagnosticURL: url)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let trace = try decoder.decode(MenuBarNativeRevealDiagnostic.self, from: Data(contentsOf: url))
        XCTAssertEqual(trace.firstFailure?.errorCode, "plan.changedOrder")
        XCTAssertEqual(trace.firstFailure?.stage, "after.first.verify")
        XCTAssertEqual(trace.entries.last?.event, "restored")
        XCTAssertFalse(flow.diagnosticWriteFailed)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
    func testDiagnosticWriteFailureCannotBlockWidthRestoration() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())/trace.json")
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.didSetLength = { if driver.length >= 0 { driver.applicationMenuWidth = 350 } }
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero, diagnosticURL: url)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertTrue(flow.diagnosticWriteFailed)
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.changedEnvironment")
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.spacer.frame.width, 38); XCTAssertNil(journal.record)
    }
    func testOptionalImmediateDiagnosticReadCannotAddAnActivationGuard() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.didSetLength = { if driver.length >= 0 { driver.failsNextWidthRead = true } }
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertTrue(entered); XCTAssertEqual(flow.state, .ready)
        XCTAssertNil(flow.diagnostic.firstFailure)
        XCTAssertNil(flow.diagnostic.entries.first { $0.event == "applied" }?.backingFrame)
        XCTAssertEqual(flow.diagnostic.entries.first { $0.stage == "after.first.observe" }?.sample?.ownedSpacer?.width, 121)
        await flow.end(.completed)
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.spacer.frame.width, 38); XCTAssertNil(journal.record)
    }
    func testLateLiveSampleCannotEnterAnotherTransactionTrace() async throws {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let oldTransaction = flow.diagnostic.transaction
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        let observation = try await driver.observe(driver.identity)
        let count = flow.diagnostic.entries.count
        flow.recordLiveObservation(transaction: oldTransaction, phase: "cg-after-ax", sample: .init(observation))
        XCTAssertEqual(flow.diagnostic.entries.count, count)
        flow.recordLiveObservation(transaction: flow.diagnostic.transaction, phase: "cg-after-ax", sample: .init(observation))
        XCTAssertEqual(flow.diagnostic.entries.count, count + 1)
        await flow.end(.cancelled)
    }
    func testBoundedTraceRetainsFirstFailureEvenBeyondEntryLimit() {
        var trace = MenuBarNativeRevealDiagnostic(transaction: UUID())
        for i in 0..<130 { trace.append(stage: "editing", event: "sample", state: "ready", elapsed: Double(i)) }
        trace.append(stage: "editing.verify", event: "failure", state: "ready", elapsed: 130,
                     error: MenuBarNativeRevealPlan.Failure.changedIdentity)
        trace.append(stage: "restore", event: "failure", state: "needsRecovery", elapsed: 131,
                     error: MenuBarNativeRevealController.Failure.restorationUnverified)
        XCTAssertEqual(trace.entries.count, 128); XCTAssertEqual(trace.droppedEntries, 4)
        XCTAssertEqual(trace.firstFailure?.errorCode, "plan.changedIdentity")
        XCTAssertEqual(trace.firstFailure?.sequence, 131)
        XCTAssertEqual(trace.entries.last?.sequence, 132)
        XCTAssertEqual(trace.entries.last?.state, "needsRecovery")
    }
}
