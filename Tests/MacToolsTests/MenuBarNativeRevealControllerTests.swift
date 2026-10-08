import XCTest
import AppKit
@testable import MacTools

@MainActor
final class MenuBarNativeRevealControllerTests: XCTestCase {
    private func controller(_ driver: MenuBarNativeRevealFixtureDriver, _ journal: MenuBarOwnedWidthJournal,
                            budget: Duration = .seconds(30)) -> MenuBarNativeRevealController {
        MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero, editingBudget: budget)
    }
    func testEnterMeasuresRealFixtureViewWidthThenFinishPreservesManualOrder() async throws {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity)
        XCTAssertTrue(entered); XCTAssertEqual(flow.state, .ready)
        XCTAssertEqual(driver.spacer.frame.width, 121)
        XCTAssertEqual(driver.target.frame.minX, 880)
        XCTAssertNotNil(journal.record, "Recovery remains while manual editing is active")
        driver.orderedIDs = [2, 1, 3] // An explicit user change is never undone by restoring own width.
        driver.target.frame = driver.target.frame.offsetBy(dx: -100, dy: 0)
        await flow.end(.completed)
        XCTAssertEqual(driver.length, -1); XCTAssertEqual(driver.spacer.frame.width, 38)
        XCTAssertEqual(driver.orderedIDs, [2, 1, 3]); XCTAssertNil(journal.record)
        XCTAssertEqual(driver.target.frame.minX, 863, "Restoring own width must preserve a manual placement offset")
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.writes, [105, -1])
    }
    func testCancelSleepDisplayChangeAndTimeoutRestoreOwnWidth() async {
        for reason in [MenuBarNativeRevealController.EndReason.cancelled, .environmentChanged, .timeout] {
            let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
            let flow = controller(driver, journal)
            let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
            if reason == .environmentChanged { driver.generation = UUID() }
            await flow.end(reason)
            XCTAssertEqual(driver.length, -1); XCTAssertEqual(driver.spacer.frame.width, 38)
            XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
        }
    }
    func testNoSpaceOrUnstableRecoveryDoesNotWriteWidth() async {
        for invalidSpace in [true, false] {
            let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
            if invalidSpace { driver.applicationMenuWidth = 900 } else { driver.recoveryShift = -620 }
            let flow = controller(driver, journal)
            let entered = await flow.begin(driver.identity)
            XCTAssertFalse(entered); XCTAssertTrue(driver.writes.isEmpty); XCTAssertEqual(journal.saves, 0)
        }
    }
    func testJournalFailureCannotApplyWidthAndThrowAfterApplyStillRestores() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        journal.failSave = true
        let flow = controller(driver, journal)
        var entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertTrue(driver.writes.isEmpty)
        journal.failSave = false; driver.throwsAfterWrite = true
        entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(driver.writes, [105, -1])
        XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
    }
    func testFailedExposureOrReadbackCannotReachReadyAndRestores() async {
        for badRead in [true, false] {
            let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
            if badRead { driver.throwsAtObservation = 3 } else { driver.reflowFactor = 0.5 }
            let flow = controller(driver, journal)
            let entered = await flow.begin(driver.identity)
            XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle)
            XCTAssertEqual(driver.length, -1); XCTAssertEqual(driver.spacer.frame.width, 38)
            XCTAssertNil(journal.record)
        }
    }
    func testCancelDuringPendingReadMakesLateObservationInert() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.pauseAtObservation = 2
        let flow = controller(driver, journal)
        let request = Task { await flow.begin(driver.identity) }
        while driver.continuation == nil { await Task.yield() }
        await flow.end(.cancelled)
        driver.continuation?.resume()
        let entered = await request.value
        XCTAssertFalse(entered); XCTAssertTrue(driver.writes.isEmpty); XCTAssertNil(journal.record)
    }
    func testTaskCancellationAfterWidthApplyStillAcknowledgesRestore() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.pauseAtObservation = 3
        let flow = controller(driver, journal)
        let request = Task { await flow.begin(driver.identity) }
        while driver.continuation == nil { await Task.yield() }
        request.cancel(); driver.continuation?.resume()
        let entered = await request.value
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle)
        XCTAssertEqual(driver.writes, [105, -1]); XCTAssertNil(journal.record)
    }
    func testRestorationGeometryFailureRetainsRecordAndBlocksNewEntry() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        driver.ignoresRestoreGeometry = true
        await flow.end(.cancelled)
        XCTAssertEqual(flow.state, .needsRecovery); XCTAssertNotNil(journal.record)
        let before = driver.writes
        let blocked = await flow.begin(driver.identity)
        XCTAssertFalse(blocked); XCTAssertEqual(driver.writes, before)
        driver.ignoresRestoreGeometry = false
        await flow.recoverOwnWidth()
        XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
    }
    func testNormalShutdownRequestsRestoreButRetainsRecordUntilNextLaunch() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        flow.shutdown()
        XCTAssertEqual(driver.length, -1); XCTAssertEqual(driver.spacer.frame.width, 38)
        XCTAssertNotNil(journal.record)
        let next = controller(driver, journal)
        await next.recoverOwnWidth()
        XCTAssertEqual(next.state, .idle); XCTAssertNil(journal.record)
    }
    func testCrashRecordOnlyRecoversSameApplicationAndOwnItemOnNewLaunch() async throws {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let old = controller(driver, journal)
        let entered = await old.begin(driver.identity); XCTAssertTrue(entered)
        // Simulate hard exit: no shutdown hook; a new instance sees durable record.
        let record = try XCTUnwrap(journal.record)
        driver.binding = MenuBarOwnedWidthBinding(itemKey: record.binding.itemKey, instance: UUID(), pid: 11,
            application: MenuBarApplicationIdentity(bundleID: "fixture", bundlePath: "/Fixture.app", launch: 2))
        driver.generation = UUID()
        let next = controller(driver, journal)
        await next.recoverOwnWidth()
        XCTAssertEqual(next.state, .idle); XCTAssertEqual(driver.length, -1); XCTAssertNil(journal.record)
        journal.record = record
        driver.binding = MenuBarOwnedWidthBinding(itemKey: "other-owned-item", instance: UUID(), pid: 11,
            application: record.binding.application)
        let wrong = controller(driver, journal), count = driver.writes.count
        await wrong.recoverOwnWidth()
        XCTAssertEqual(wrong.state, .needsRecovery); XCTAssertEqual(driver.writes.count, count)
        XCTAssertNotNil(journal.record)
        old.shutdown() // Old instance binding cannot affect the new object.
        XCTAssertEqual(driver.writes.count, count)
    }
    func testCorruptFileRecoveryIsNotClearedOrApplied() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OwnedWidth.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("owned-width.json")
        try Data("corrupt".utf8).write(to: url)
        let driver = MenuBarNativeRevealFixtureDriver()
        let flow = controller(driver, MenuBarOwnedWidthFileJournal(url: url))
        await flow.recoverOwnWidth()
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertTrue(driver.writes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), Data("corrupt".utf8))
    }
    func testEditingWatchdogRestoresAndDuplicateStartCannotResizeAgain() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal, budget: .milliseconds(20))
        let first = await flow.begin(driver.identity), second = await flow.begin(driver.identity)
        XCTAssertTrue(first); XCTAssertFalse(second)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.writes, [105, -1]); XCTAssertNil(journal.record)
    }
    func testDisplayChangeDuringPreflightMakesLateReadInertWithoutWidthWrite() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.pauseAtObservation = 2
        let flow = controller(driver, journal)
        let request = Task { await flow.begin(driver.identity) }
        while driver.continuation == nil { await Task.yield() }
        driver.generation = UUID()
        await flow.environmentChanged()
        driver.continuation?.resume()
        let entered = await request.value
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle); XCTAssertTrue(driver.writes.isEmpty)
    }
    func testPreparationWatchdogStopsHungObservationBeforeMutation() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.pauseAtObservation = 1
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero,
                                                 preparationBudget: .milliseconds(20))
        let request = Task { await flow.begin(driver.identity) }
        while driver.continuation == nil { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(flow.state, .idle)
        driver.continuation?.resume()
        let entered = await request.value
        XCTAssertFalse(entered); XCTAssertTrue(driver.writes.isEmpty)
    }
    func testDisplayChangeDoesNotWeakenPhysicalRestoreAcknowledgement() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        driver.generation = UUID(); driver.ignoresRestoreGeometry = true
        await flow.environmentChanged()
        XCTAssertEqual(flow.state, .needsRecovery); XCTAssertNotNil(journal.record)
        XCTAssertEqual(driver.spacer.frame.width, 121, "A returned length alone cannot prove reflow restoration")
        driver.ignoresRestoreGeometry = false
        await flow.recoverOwnWidth()
        XCTAssertEqual(flow.state, .idle)
    }
    func testDurableCrashRecordSurvivesAndIsAcknowledgedByFreshOwnViewInstance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OwnedWidthCrash.\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("owned-width.json")
        let store = MenuBarOwnedWidthFileJournal(url: url), oldDriver = MenuBarNativeRevealFixtureDriver()
        let old = controller(oldDriver, store)
        let entered = await old.begin(oldDriver.identity); XCTAssertTrue(entered)
        let record = try XCTUnwrap(try store.load())
        XCTAssertEqual(record.originalLength, -1)
        XCTAssertEqual((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize! < 16_384, true)
        let nextDriver = MenuBarNativeRevealFixtureDriver()
        nextDriver.binding = MenuBarOwnedWidthBinding(itemKey: record.binding.itemKey, instance: UUID(), pid: 11,
            application: MenuBarApplicationIdentity(bundleID: "fixture", bundlePath: "/Fixture.app", launch: 2))
        let next = controller(nextDriver, MenuBarOwnedWidthFileJournal(url: url))
        XCTAssertEqual(next.state, .needsRecovery)
        await next.recoverOwnWidth()
        XCTAssertEqual(nextDriver.writes, [-1]); XCTAssertEqual(next.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        old.shutdown()
    }
    func testCloseRequestRestoresSynchronouslyBeforeAcknowledgement() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        let completion = flow.requestEnd(.cancelled)
        XCTAssertEqual(driver.length, -1); XCTAssertEqual(driver.spacer.frame.width, 38)
        XCTAssertEqual(flow.state, .restoring)
        await completion?.value
        XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
    }
    func testUnknownRecoveryVisibilityRetainsJournalEvenIfWidthMatches() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        driver.restorationUnsafe = true
        await flow.end(.completed)
        XCTAssertEqual(driver.spacer.frame.width, 38); XCTAssertEqual(flow.state, .needsRecovery)
        XCTAssertNotNil(journal.record)
        driver.restorationUnsafe = false
        await flow.recoverOwnWidth()
        XCTAssertEqual(flow.state, .idle)
    }
    func testReadyMonitorRestoresOnLostRecoveryInsteadOfLeavingWidthActive() async {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = controller(driver, journal)
        let entered = await flow.begin(driver.identity); XCTAssertTrue(entered)
        driver.recoveryShift = -620
        try? await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(driver.length, -1); XCTAssertEqual(flow.state, .needsRecovery)
        XCTAssertNotNil(journal.record)
        driver.recoveryShift = 0
        await flow.recoverOwnWidth()
        XCTAssertEqual(flow.state, .idle)
    }
}
