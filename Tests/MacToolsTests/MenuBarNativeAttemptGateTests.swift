import AppKit
import XCTest
@testable import MacTools

private enum CapturedAttempt {
    static func load() throws -> (MenuBarNativeRevealPlan.Observation, MenuBarNativeRevealDiagnostic) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/evidence/menu-bar-native-diagnostic-retry-2026-10-02/internal-diagnostic.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let trace = try decoder.decode(MenuBarNativeRevealDiagnostic.self, from: Data(contentsOf: url))
        let s = try XCTUnwrap(trace.entries.first { $0.event == "observation" }?.sample)
        func target(_ w: MenuBarNativeRevealDiagnostic.Window) -> MenuBarStatusTarget {
            .init(id: w.id, pid: w.pid, frame: w.frame, onScreen: w.onScreen, application: w.application)
        }
        let item = target(try XCTUnwrap(s.target)), spacer = try XCTUnwrap(s.ownedSpacer)
        let recoveryButton = try XCTUnwrap(s.recoveryButton)
        let peers = s.windows.map(target)
        let recovery = try XCTUnwrap(peers.first { $0.frame.contains(recoveryButton) && $0.onScreen })
        return (.init(generation: s.generation, displayID: 1, target: item,
            targetButton: try XCTUnwrap(s.targetButton), ownedSpacer: spacer, recoveryButton: recoveryButton,
            safeAreas: s.safeAreas, applicationMenu: try XCTUnwrap(s.applicationMenu),
            orderedWindowIDs: s.orderedWindowIDs, peers: peers, frontPID: s.frontPID,
            frontApplication: s.frontApplication, recoveryTarget: recovery), trace)
    }
}

/// Captured IDs/identities are labels in a private NSView model, never desktop
/// handles. The visibility outcome is a simulated response, not hardware proof.
@MainActor
private final class CapturedAttemptDriver: MenuBarNativeRevealWidthDriver {
    let before: MenuBarNativeRevealPlan.Observation
    let spacer: NSView
    let target: NSView
    let binding = MenuBarOwnedWidthBinding(itemKey: "captured-fixture-owned-item", instance: UUID(), pid: 10,
        application: .init(bundleID: "fixture", bundlePath: "/Fixture.app", launch: 1))
    var length: CGFloat = -1
    var visibleResponses: [Bool] = [false, false]
    var menuChanged = false
    var recoveryUnsafe = false
    var writes: [CGFloat] = []
    var afterSamples = 0
    var missingSecondGeometry = false
    init(_ observation: MenuBarNativeRevealPlan.Observation) {
        before = observation; spacer = NSView(frame: observation.ownedSpacer); target = NSView(frame: observation.target.frame)
    }
    var identity: MenuBarIconIdentity { .init(capturing: before.target, peersOnDisplay: before.peers) }
    func widthState() throws -> MenuBarOwnedWidthState {
        .init(binding: binding, length: length, effectiveLength: length >= 0 ? length : 22,
              backingFrame: spacer.frame, environment: before.generation)
    }
    func setLength(_ proposed: CGFloat, matching expected: MenuBarOwnedWidthBinding) throws {
        guard expected == binding else { throw MenuBarNativeRevealController.Failure.wrongOwner }
        writes.append(proposed); length = proposed
        // Deliberate fixture overhead: actual growth differs from requested
        // length. Production must measure it, not assume this 16-point value.
        let growth: CGFloat = proposed < 0 ? 0 : proposed - 22 + 16
        spacer.frame = CGRect(x: before.ownedSpacer.minX - growth, y: before.ownedSpacer.minY,
            width: before.ownedSpacer.width + growth, height: before.ownedSpacer.height)
        target.frame = before.target.frame.offsetBy(dx: -growth, dy: 0)
    }
    func observe(_ identity: MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation {
        if length < 0 { return before }
        let growth = spacer.frame.width - before.ownedSpacer.width
        let shown = visibleResponses[min(afterSamples, visibleResponses.count - 1)]; afterSamples += 1
        if missingSecondGeometry && afterSamples == 2 { throw MenuBarNativeObservationFailure.target }
        var item = before.target
        item = .init(id: item.id, pid: item.pid, frame: target.frame, onScreen: shown, application: item.application)
        let control = before.peers.first { $0.frame == before.ownedSpacer }!
        let peers = before.peers.map { old -> MenuBarStatusTarget in
            if old.id == item.id { return item }
            let frame = old.id == control.id ? spacer.frame : old.frame.minX < before.ownedSpacer.minX
                ? old.frame.offsetBy(dx: -growth, dy: 0) : old.frame
            return .init(id: old.id, pid: old.pid, frame: frame, onScreen: old.onScreen, application: old.application)
        }
        let owner = control.pid, recovery = before.recoveryTarget!
        let divider = peers.first { $0.pid == owner && $0.id != control.id && $0.id != recovery.id }!
        let height: CGFloat = 1117
        let display = MenuBarDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: height),
            quartzFrame: CGRect(x: 0, y: 0, width: 1728, height: height),
            safeAreas: before.safeAreas.map { CGRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height) })
        let context = MenuBarNativeObservation.Context(generation: before.generation, displays: [display], windows: peers,
            ownerPID: owner, controlID: control.id, dividerID: divider.id, frontPID: before.frontPID!,
            frontApplication: before.frontApplication!, overlays: [])
        let menu = menuChanged ? CGRect(x: 0, y: 0, width: 400, height: 32) : before.applicationMenu
        return try MenuBarNativeObservation.assemble(context, identity: identity,
            targetAX: [before.targetButton.offsetBy(dx: -growth, dy: 0)],
            recoveryAX: [before.recoveryButton], menuAX: [menu])
    }
    func verifyRestorationSafety() async throws {
        guard !recoveryUnsafe, before.recoveryTarget?.onScreen == true,
              before.safeAreas.contains(where: { $0.contains(before.recoveryButton) }) else {
            throw MenuBarNativeRevealController.Failure.restorationUnverified
        }
    }
}

@MainActor
final class MenuBarNativeAttemptGateTests: XCTestCase {
    func testExactCapturedPreconditionFailureNowPlansOnlyOneButtonWidthAttempt() throws {
        let (before, trace) = try CapturedAttempt.load()
        XCTAssertEqual(trace.firstFailure?.stage, "plan.make")
        XCTAssertEqual(trace.firstFailure?.errorCode, "plan.targetNotOnScreen")
        XCTAssertFalse(before.target.onScreen)
        XCTAssertEqual(before.targetButton, CGRect(x: 657, y: 6.5, width: 29, height: 24))
        let plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertEqual(plan.purpose, .attemptUnorderedTarget); XCTAssertEqual(plan.requestedExtraLength, 29)
        XCTAssertThrowsError(try plan.verify(before)) { XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .targetNotOnScreen) }
    }
    func testCapturedHiddenTargetReachesReadyOnlyAfterTwoVisibleVerifiedPrivateSamples() async throws {
        let driver = CapturedAttemptDriver(try CapturedAttempt.load().0), journal = MenuBarMemoryOwnedWidthJournal()
        driver.visibleResponses = [true, true]
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertTrue(entered); XCTAssertEqual(flow.state, .ready); XCTAssertEqual(driver.afterSamples, 2)
        XCTAssertEqual(driver.spacer.frame.width, 83); XCTAssertEqual(driver.target.frame.minX, 612)
        XCTAssertEqual(driver.writes, [51]); XCTAssertNotNil(journal.record)
        XCTAssertEqual(flow.diagnostic.entries.filter { $0.event == "verified" }.count, 2)
        await flow.end(.completed)
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.writes, [51, -1])
        XCTAssertEqual(driver.spacer.frame.width, 38); XCTAssertEqual(driver.target.frame.minX, 657); XCTAssertNil(journal.record)
    }
    func testPersistentlyHiddenTargetDoesNotReachReadyAndRestoresExactlyOnce() async throws {
        let driver = CapturedAttemptDriver(try CapturedAttempt.load().0), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle)
        XCTAssertEqual(flow.diagnostic.firstFailure?.stage, "after.first.verify")
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.targetNotOnScreen")
        XCTAssertFalse(flow.diagnostic.entries.contains { $0.event == "confirmed" })
        XCTAssertEqual(driver.writes, [51, -1]); XCTAssertEqual(driver.target.frame.minX, 657); XCTAssertNil(journal.record)
    }
    func testOneVisibleSampleCannotGrantInteractionWhenSecondIsUnknown() async throws {
        for missingGeometry in [false, true] {
            let driver = CapturedAttemptDriver(try CapturedAttempt.load().0), journal = MenuBarMemoryOwnedWidthJournal()
            driver.visibleResponses = [true, false]; driver.missingSecondGeometry = missingGeometry
            let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
            let entered = await flow.begin(driver.identity)
            XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle)
            XCTAssertEqual(flow.diagnostic.firstFailure?.stage, missingGeometry ? "after.second.observe" : "after.second.verify")
            XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, missingGeometry ? "observation.target" : "plan.targetNotOnScreen")
            XCTAssertFalse(flow.diagnostic.entries.contains { $0.event == "confirmed" })
            XCTAssertEqual(driver.writes, [51, -1]); XCTAssertNil(journal.record)
        }
    }
    func testMenuChangeAfterAllowedAttemptStillRefusesInteractionAndRestores() async throws {
        let driver = CapturedAttemptDriver(try CapturedAttempt.load().0), journal = MenuBarMemoryOwnedWidthJournal()
        driver.visibleResponses = [true, true]; driver.menuChanged = true
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.changedEnvironment")
        XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.writes, [51, -1]); XCTAssertNil(journal.record)
    }
    func testUnknownRecoveryAfterFailedAttemptRetainsJournalAndBlocksInteraction() async throws {
        let driver = CapturedAttemptDriver(try CapturedAttempt.load().0), journal = MenuBarMemoryOwnedWidthJournal()
        driver.recoveryUnsafe = true
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .needsRecovery); XCTAssertNotNil(journal.record)
        XCTAssertEqual(driver.spacer.frame.width, 38); XCTAssertEqual(driver.writes, [51, -1])
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.targetNotOnScreen")
        let again = await flow.begin(driver.identity)
        XCTAssertFalse(again); XCTAssertEqual(driver.writes, [51, -1])
    }
}
