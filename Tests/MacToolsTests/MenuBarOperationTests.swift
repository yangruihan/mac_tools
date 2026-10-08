import XCTest
import ApplicationServices
@testable import MacTools

private final class MemoryJournal: MenuBarRecoveryJournal {
    var record: MenuBarRecoveryRecord?
    var writes: [MenuBarRecoveryRecord.Phase] = []
    var failSave = false, failClear = false, corrupt = false
    func load() throws -> MenuBarRecoveryRecord? {
        if corrupt { throw MenuBarFileRecoveryJournal.Failure.invalidRecord }
        return record
    }
    func save(_ value: MenuBarRecoveryRecord) throws {
        if failSave { throw MenuBarFileRecoveryJournal.Failure.invalidRecord }
        writes.append(value.phase); record = value
    }
    func clear() throws {
        if failClear { throw MenuBarFileRecoveryJournal.Failure.invalidRecord }
        record = nil
    }
}
@MainActor
private final class FixtureDriver: MenuBarOperationDriver {
    var target = MenuBarStatusTarget(id: 1, pid: 10, frame: CGRect(x: 990, y: 0, width: 30, height: 24), onScreen: true,
        application: MenuBarApplicationIdentity(bundleID: "com.example.fixture", bundlePath: "/Applications/Fixture.app", launch: 1))
    var neighbor: MenuBarStatusTarget {
        MenuBarStatusTarget(id: 2, pid: target.pid, frame: target.frame.offsetBy(dx: 60, dy: 0), onScreen: true, application: target.application)
    }
    var identity: MenuBarIconIdentity { MenuBarIconIdentity(capturing: target, peersOnDisplay: [target]) }
    var ax: [MenuBarActionOutcome] = [.observed], clicks: [MenuBarActionOutcome] = [.refused]
    var menu: MenuBarInterfaceState = .open
    var recoveryMenu: MenuBarInterfaceState = .closed
    var trace: [String] = []
    var onAX: (() async throws -> Void)?
    var onReveal: (() throws -> Void)?
    var restoreFails = false, revealUnsupported = false
    func resolve(_ identity: MenuBarIconIdentity) throws -> MenuBarStatusTarget { trace.append("resolve"); return target }
    func activateAX(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome {
        trace.append("ax"); try await onAX?()
        return ax.isEmpty ? .refused : ax.removeFirst()
    }
    func activateVisible(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome {
        trace.append("click"); return clicks.isEmpty ? .refused : clicks.removeFirst()
    }
    func prepareReveal(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarRestoreAnchor {
        trace.append("prepare")
        if revealUnsupported { throw MenuBarOperationFailure.movementUnavailable }
        return MenuBarRestoreAnchor(displayID: 1, section: .hidden, left: nil, right: MenuBarRecordedTarget(neighbor))
    }
    func reveal(_ target: MenuBarStatusTarget, anchor: MenuBarRestoreAnchor, context: MenuBarOperationContext) async throws {
        trace.append("move"); try onReveal?()
    }
    func interfaceState(_ target: MenuBarStatusTarget) async -> MenuBarInterfaceState { menu }
    func recoveryInterfaceState(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws -> MenuBarInterfaceState { recoveryMenu }
    func restore(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws {
        trace.append("restore")
        if restoreFails { throw MenuBarOperationFailure.movementUnavailable }
    }
}
@MainActor
final class MenuBarOperationTests: XCTestCase {
    func testProductionAXRefusalStopsWithoutFallbackAndReleasesUnmovedLease() async {
        let d = FixtureDriver(), j = MemoryJournal()
        d.onAX = { throw MenuBarOperationFailure.axUnavailable("无可核实动作。") }
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .failed(MenuBarOperationFailure.axUnavailable("无可核实动作。").message))
        XCTAssertEqual(d.trace, ["resolve", "ax"])
        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.interaction)
        XCTAssertNil(j.record)
        d.onAX = nil
        let next = await c.activate(d.identity)
        XCTAssertEqual(next, .observed)
    }
    func testLiveDriverHasNoClickMoveOrRestoreProvider() async throws {
        let d = FixtureDriver()
        let live = MenuBarLiveOperationDriver(resolve: { _ in d.target })
        let generation = UUID()
        let ctx = MenuBarOperationContext(generation: generation, deadline: .now.advanced(by: .seconds(5)), currentGeneration: { generation })
        do { _ = try await live.activateVisible(d.target, context: ctx); XCTFail("Synthetic click must be unavailable") }
        catch { guard let failure = error as? MenuBarOperationFailure, case .axUnavailable = failure else { return XCTFail("Unexpected error: \(error)") } }
        do { _ = try await live.prepareReveal(d.target, context: ctx); XCTFail("Move must be unavailable") }
        catch { XCTAssertEqual(error as? MenuBarOperationFailure, .movementUnavailable) }
        let record = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(d.target),
            anchor: MenuBarRestoreAnchor(displayID: 1, section: .hidden, left: nil, right: MenuBarRecordedTarget(d.neighbor)), phase: .moved)
        do { try await live.restore(record, context: ctx); XCTFail("Restore must be unavailable") }
        catch { XCTAssertEqual(error as? MenuBarOperationFailure, .movementUnavailable) }
        let state = try await live.recoveryInterfaceState(record, context: ctx)
        if case .unknown = state {} else { XCTFail("Recovery must remain unknown") }
    }
    func testAXPreflightRejectsUnidentifiedTargetWithoutSendingAction() {
        let invalid = MenuBarStatusTarget(id: 0, pid: -1, frame: .zero, onScreen: false)
        let reply = MenuBarAXActivator.activate(invalid)
        XCTAssertEqual(reply.outcome, .refused)
        XCTAssertTrue(reply.supportedActions.isEmpty)
        XCTAssertNil(reply.rawError, "No AX action attempted")
        XCTAssertNotNil(reply.refusalReason)
    }
    func testAXObservedNeverSendsCoordinateClickOrMove() async {
        let d = FixtureDriver(), j = MemoryJournal()
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .observed)
        XCTAssertEqual(d.trace, ["resolve", "ax"])
        XCTAssertEqual(c.state, .foreignInteraction)
        XCTAssertNil(j.record)
    }
    func testAXTimeoutUnknownNeverEscalatesAndBlocksDuplicateRequest() async {
        let d = FixtureDriver(); d.ax = [.uncertain]
        let c = MenuBarOperationCoordinator(driver: d, journal: MemoryJournal())
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .uncertain)
        let duplicate = await c.activate(d.identity)
        XCTAssertEqual(duplicate, .failed(MenuBarOperationFailure.busy.message))
        XCTAssertEqual(d.trace, ["resolve", "ax"])
        d.menu = .unknown; await c.settle()
        XCTAssertEqual(c.state, .uncertain)
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(c.state, .idle)
    }
    func testCloseNeedsTwoConsecutiveSamplesAndUnknownResetsEvidence() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .observed]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity)
        d.menu = .closed; await c.settle()
        XCTAssertNotNil(j.record)
        d.menu = .unknown; await c.settle()
        d.menu = .closed; await c.settle()
        XCTAssertNotNil(j.record)
        await c.settle()
        XCTAssertNil(j.record)
    }
    func testAcceptedActionIsReportedAsDispatchedNotObserved() async {
        let d = FixtureDriver(); d.ax = [.accepted]
        let c = MenuBarOperationCoordinator(driver: d, journal: MemoryJournal())
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .dispatched)
    }
    func testExplicitAXRefusalCanUseVerifiedVisibleClick() async {
        let d = FixtureDriver(); d.ax = [.refused]; d.clicks = [.observed]
        let c = MenuBarOperationCoordinator(driver: d, journal: MemoryJournal())
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .observed)
        XCTAssertEqual(d.trace, ["resolve", "ax", "resolve", "click"])
    }
    func testPreparedRecordPrecedesMoveAndUnknownMenuPreventsRestore() async {
        let d = FixtureDriver(), j = MemoryJournal()
        d.ax = [.refused, .observed]
        d.onReveal = { XCTAssertEqual(j.record?.phase, .prepared) }
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .observed)
        XCTAssertEqual(j.writes, [.prepared, .moved])
        XCTAssertNotNil(c.pending)
        d.menu = .open; await c.settle()
        d.menu = .unknown; await c.settle()
        XCTAssertFalse(d.trace.contains("restore"))
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(d.trace.filter { $0 == "restore" }.count, 1)
        XCTAssertNil(j.record)
        XCTAssertEqual(c.state, .idle)
        await c.settle()
        XCTAssertEqual(d.trace.filter { $0 == "restore" }.count, 1)
    }
    func testUncertainAXAfterRevealNeverFallsBackAndRetainsRecovery() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .uncertain]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .uncertain)
        XCTAssertEqual(d.trace.filter { $0 == "click" }.count, 1)
        XCTAssertNotNil(j.record)
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertNil(j.record)
    }
    func testJournalFailurePreventsAllMovement() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused]; j.failSave = true
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .failed(MenuBarOperationFailure.journalUnavailable.message))
        XCTAssertFalse(d.trace.contains("move"))
        XCTAssertEqual(c.state, .idle)
    }
    func testPartialMoveFailureCompensatesWithoutActivationReplay() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused]
        d.onReveal = { throw MenuBarOperationFailure.deadline }
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity)
        XCTAssertEqual(d.trace.filter { $0 == "ax" }.count, 1)
        XCTAssertEqual(d.trace.filter { $0 == "restore" }.count, 1)
        XCTAssertNil(j.record)
    }
    func testRestoreFailureKeepsRecordAndBlocksNewActivation() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .observed]; d.restoreFails = true
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity); d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(c.state, .needsRecovery)
        XCTAssertNotNil(j.record)
        c.releaseUnmovedInteraction()
        XCTAssertTrue(c.blocksLayout, "An explicit release cannot discard recovery responsibility")
        XCTAssertNotNil(c.pending)
        let blocked = await c.activate(d.identity)
        XCTAssertEqual(blocked, .failed(MenuBarOperationFailure.recoveryRequired.message))
        d.restoreFails = false; try? await c.recover()
        XCTAssertNil(j.record)
        XCTAssertEqual(c.state, .idle)
    }
    func testCancellationAfterAXKeepsUnknownLeaseAndNeverClicks() async {
        let d = FixtureDriver(), j = MemoryJournal()
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        d.onAX = { c.invalidate() }
        _ = await c.activate(d.identity)
        XCTAssertEqual(c.state, .uncertain)
        XCTAssertFalse(d.trace.contains("click"))
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(c.state, .idle)
    }
    func testExpiredBudgetStopsBeforeResolvingOrPosting() async {
        let d = FixtureDriver()
        let c = MenuBarOperationCoordinator(driver: d, journal: MemoryJournal(), budget: .zero)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .failed(MenuBarOperationFailure.deadline.message))
        XCTAssertTrue(d.trace.isEmpty)
    }
    func testConcurrentRequestsCannotInterleave() async {
        let d = FixtureDriver()
        let c = MenuBarOperationCoordinator(driver: d, journal: MemoryJournal())
        var resume: CheckedContinuation<Void, Never>?
        d.onAX = { await withCheckedContinuation { resume = $0 } }
        let first = Task { await c.activate(d.identity) }
        while resume == nil { await Task.yield() }
        c.releaseUnmovedInteraction()
        XCTAssertTrue(c.blocksLayout, "Explicit release cannot interrupt an executing AX request")
        let second = await c.activate(d.identity)
        XCTAssertEqual(second, .failed(MenuBarOperationFailure.busy.message))
        resume?.resume()
        _ = await first.value
        XCTAssertEqual(d.trace.filter { $0 == "ax" }.count, 1)
    }
    func testRestartWithPreparedRecordOnlyRecoversNeverReplaysActivation() async {
        let d = FixtureDriver(), j = MemoryJournal()
        j.record = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(d.target),
            anchor: MenuBarRestoreAnchor(displayID: 1, section: .hidden, left: nil, right: MenuBarRecordedTarget(d.neighbor)), phase: .prepared)
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        XCTAssertEqual(c.state, .needsRecovery)
        try? await c.recover()
        XCTAssertEqual(d.trace, ["restore"])
        XCTAssertNil(j.record)
    }
    func testCorruptJournalIsNotSilentlyDiscarded() async {
        let d = FixtureDriver(), j = MemoryJournal(); j.corrupt = true
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        XCTAssertEqual(c.state, .needsRecovery)
        do { try await c.recover(); XCTFail("corrupt journal must block") } catch {}
        XCTAssertTrue(d.trace.isEmpty)
    }
    func testUnknownMenuCannotBeForcedToRestore() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .observed]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity); d.menu = .unknown
        do { try await c.recover(); XCTFail("must not restore unknown menu") } catch {}
        XCTAssertNotNil(j.record)
        XCTAssertFalse(d.trace.contains("restore"))
    }
    func testUnsupportedMoveIsHonestAndDoesNotCreateRecord() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused]; d.revealUnsupported = true
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let result = await c.activate(d.identity)
        XCTAssertEqual(result, .failed(MenuBarOperationFailure.movementUnavailable.message))
        XCTAssertNil(j.record)
        XCTAssertFalse(d.trace.contains("move"))
    }
    func testAXErrorClassificationDoesNotTreatTimeoutAsRefusal() {
        XCTAssertEqual(MenuBarAXActivator.classify(.cannotComplete), .uncertain)
        XCTAssertEqual(MenuBarAXActivator.classify(.failure), .uncertain)
        XCTAssertEqual(MenuBarAXActivator.classify(.actionUnsupported), .refused)
        XCTAssertEqual(MenuBarAXActivator.classify(.success), .accepted)
    }
    func testFileJournalRoundTripAndPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let j = MenuBarFileRecoveryJournal(url: directory.appendingPathComponent("move.json"))
        let d = FixtureDriver()
        let record = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(d.target),
            anchor: MenuBarRestoreAnchor(displayID: 1, section: .visible, left: MenuBarRecordedTarget(d.neighbor), right: nil), phase: .prepared)
        try j.save(record)
        XCTAssertEqual(try j.load(), record)
        let attributes = try FileManager.default.attributesOfItem(atPath: j.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let text = try String(contentsOf: j.url)
        XCTAssertFalse(text.contains("image")); XCTAssertFalse(text.contains("frame"))
        try j.clear(); XCTAssertNil(try j.load())
    }
    func testJournalRejectsSelfAnchorCorruptAndSymlinkWithoutDeletingThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let d = FixtureDriver(), path = directory.appendingPathComponent("move.json")
        let j = MenuBarFileRecoveryJournal(url: path)
        let bad = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(d.target),
            anchor: MenuBarRestoreAnchor(displayID: 1, section: .hidden, left: nil, right: MenuBarRecordedTarget(d.target)), phase: .prepared)
        XCTAssertThrowsError(try j.save(bad))
        try Data("invalid".utf8).write(to: path)
        XCTAssertThrowsError(try j.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        try FileManager.default.removeItem(at: path)
        let other = directory.appendingPathComponent("fixture-data")
        try Data("only fixture data".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: other)
        XCTAssertThrowsError(try j.load())
        XCTAssertEqual(try String(contentsOf: other), "only fixture data")
    }

    func testStartupRecoveryChecksMenuEvenWithoutAnInteractionLease() async {
        let d = FixtureDriver(), j = MemoryJournal()
        j.record = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(d.target),
            anchor: MenuBarRestoreAnchor(displayID: 1, section: .hidden, left: nil, right: MenuBarRecordedTarget(d.neighbor)), phase: .prepared)
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        d.recoveryMenu = .open
        do { try await c.recover(); XCTFail("startup must not move an item with an existing menu") } catch {}
        XCTAssertNotNil(j.record)
        XCTAssertFalse(d.trace.contains("restore"))
        d.recoveryMenu = .unknown
        do { try await c.recover(); XCTFail("unknown is not closed") } catch {}
        XCTAssertNotNil(j.record)
        d.recoveryMenu = .closed
        try? await c.recover()
        XCTAssertNil(j.record)
        XCTAssertEqual(d.trace.filter { $0 == "restore" }.count, 1)
        XCTAssertFalse(d.trace.contains("ax"))
    }

    func testTaskCancellationAfterPossibleMoveKeepsRecordForNextRecovery() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        var request: Task<MenuBarOperationCoordinator.Result, Never>?
        d.onReveal = { request?.cancel() }
        request = Task { await c.activate(d.identity) }
        _ = await request?.value
        XCTAssertNotNil(j.record)
        XCTAssertEqual(c.state, .needsRecovery)
        XCTAssertFalse(d.trace.contains("restore"))
        d.recoveryMenu = .unknown
        do { try await c.recover(); XCTFail("unknown recovery cannot move") } catch {}
        XCTAssertNotNil(j.record)
        d.recoveryMenu = .closed
        try? await c.recover()
        XCTAssertNil(j.record)
        XCTAssertEqual(d.trace.filter { $0 == "ax" }.count, 1)
        XCTAssertEqual(d.trace.filter { $0 == "restore" }.count, 1)
    }
    func testCancellationDuringAXDoesNotEscalateOrForgetInteraction() async {
        let d = FixtureDriver(), j = MemoryJournal()
        d.onAX = { try await Task.sleep(nanoseconds: 10_000_000_000) }
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        let request = Task { await c.activate(d.identity) }
        while !d.trace.contains("ax") { await Task.yield() }
        request.cancel(); _ = await request.value
        XCTAssertEqual(c.state, .uncertain)
        XCTAssertNotNil(c.interaction)
        XCTAssertFalse(d.trace.contains("click")); XCTAssertFalse(d.trace.contains("move"))
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(c.state, .idle)
    }
    func testClearFailurePreservesAlreadyRestoredRecordWithoutReactivation() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .observed]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity)
        j.failClear = true; d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertEqual(c.state, .needsRecovery); XCTAssertNotNil(j.record)
        let activations = d.trace.filter { $0 == "ax" }.count
        j.failClear = false; try? await c.recover()
        XCTAssertNil(j.record)
        XCTAssertEqual(d.trace.filter { $0 == "ax" }.count, activations)
    }
    func testInvalidationPreservesMenuAndRecoveryResponsibility() async {
        let d = FixtureDriver(), j = MemoryJournal(); d.ax = [.refused, .observed]
        let c = MenuBarOperationCoordinator(driver: d, journal: j)
        _ = await c.activate(d.identity)
        c.invalidate(); d.menu = .open; await c.settle()
        XCTAssertNotNil(j.record); XCTAssertFalse(d.trace.contains("restore"))
        d.menu = .unknown; await c.settle()
        XCTAssertNotNil(j.record)
        d.menu = .closed; await c.settle(); await c.settle()
        XCTAssertNil(j.record)
    }
    func testExitAndReloadRoundTripPreservesRecordUntilExistingMenuCloses() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let d = FixtureDriver(); d.ax = [.refused, .observed]
        let j = MenuBarFileRecoveryJournal(url: folder.appendingPathComponent("recovery.json"))
        do {
            let previous = MenuBarOperationCoordinator(driver: d, journal: j)
            _ = await previous.activate(d.identity)
            previous.invalidate()
            XCTAssertNotNil(try j.load())
        }
        let reloaded = MenuBarOperationCoordinator(driver: d, journal: MenuBarFileRecoveryJournal(url: j.url))
        XCTAssertEqual(reloaded.state, .needsRecovery)
        d.recoveryMenu = .open
        do { try await reloaded.recover(); XCTFail("existing menu survives manager exit") } catch {}
        XCTAssertNotNil(try j.load())
        d.recoveryMenu = .closed; try await reloaded.recover()
        XCTAssertNil(try j.load())
        XCTAssertEqual(d.trace.filter { $0 == "ax" }.count, 2)
    }

}
