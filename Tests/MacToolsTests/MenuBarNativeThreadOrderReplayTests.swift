import AppKit
import XCTest
@testable import MacTools

/// Reads the same transaction's saved samples. No desktop/AX calls or replayed
/// effects. Counterfactuals below are test-only; no recorded field is overwritten.
final class MenuBarNativeThreadOrderReplayTests: XCTestCase {
    private func captured() throws -> (MenuBarNativeRevealPlan.Observation, MenuBarNativeRevealPlan.Observation, MenuBarNativeRevealDiagnostic) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let trace = try decoder.decode(MenuBarNativeRevealDiagnostic.self,
            from: Data(contentsOf: root.appendingPathComponent("docs/evidence/menu-bar-native-auto-thread-2026-10-03/internal-diagnostic.json")))
        func observation(_ stage: String) throws -> MenuBarNativeRevealPlan.Observation {
            let sample = try XCTUnwrap(trace.entries.first { $0.stage == stage && $0.event == "observation" }?.sample)
            func target(_ w: MenuBarNativeRevealDiagnostic.Window) -> MenuBarStatusTarget {
                .init(id: w.id, pid: w.pid, frame: w.frame, onScreen: w.onScreen, application: w.application)
            }
            let peers = sample.windows.map(target), recoveryButton = try XCTUnwrap(sample.recoveryButton)
            let frontPID = try XCTUnwrap(sample.frontPID)
            let recovery = try XCTUnwrap(peers.first { $0.pid == frontPID && $0.frame.contains(recoveryButton) })
            // The diagnostic did not serialize displayID. 1 is an equal replay
            // namespace, not a reconstructed physical display identity.
            return .init(generation: sample.generation, displayID: 1, target: target(try XCTUnwrap(sample.target)),
                targetButton: try XCTUnwrap(sample.targetButton), ownedSpacer: try XCTUnwrap(sample.ownedSpacer),
                recoveryButton: recoveryButton, safeAreas: sample.safeAreas, applicationMenu: try XCTUnwrap(sample.applicationMenu),
                orderedWindowIDs: sample.orderedWindowIDs, peers: peers, frontPID: frontPID,
                frontApplication: sample.frontApplication, recoveryTarget: recovery)
        }
        return (try observation("before.first.observe"), try observation("after.first.observe"), trace)
    }
    private func counterfactual(_ after: MenuBarNativeRevealPlan.Observation,
                                order: [UInt32]? = nil, target: MenuBarStatusTarget? = nil,
                                peers: [MenuBarStatusTarget]? = nil) -> MenuBarNativeRevealPlan.Observation {
        .init(generation: after.generation, displayID: after.displayID, target: target ?? after.target,
            targetButton: after.targetButton, ownedSpacer: after.ownedSpacer, recoveryButton: after.recoveryButton,
            safeAreas: after.safeAreas, applicationMenu: after.applicationMenu, orderedWindowIDs: order ?? after.orderedWindowIDs,
            peers: peers ?? after.peers, frontPID: after.frontPID, frontApplication: after.frontApplication,
            recoveryTarget: after.recoveryTarget)
    }
    func testActualStableIdentitiesAndExpectedTargetShiftStillRejectRawOrderChange() throws {
        let (before, after, _) = try captured()
        let detail = MenuBarNativeRevealDiagnostic.PostcheckDetail(before: before, after: after)
        XCTAssertEqual(before.peers.count, 30); XCTAssertEqual(after.peers.count, 30)
        XCTAssertEqual(detail.peerIdentitySetStable, true)
        XCTAssertEqual(detail.measuredSpacerGrowth, 45); XCTAssertTrue(detail.targetShiftMatchesMeasuredGrowth)
        XCTAssertEqual(detail.peers.filter { $0.beforeRank != $0.afterRank }.map(\.id), [6863, 125881])
        let hidden = try XCTUnwrap(detail.peers.first { $0.id == 6863 })
        XCTAssertEqual(hidden.before?.frame, hidden.after?.frame)
        XCTAssertEqual(hidden.before?.onScreen, false); XCTAssertEqual(hidden.after?.onScreen, false)
        let moving = try XCTUnwrap(detail.peers.first { $0.id == 125881 })
        XCTAssertEqual(moving.before?.frame.minX, 1029); XCTAssertEqual(moving.after?.frame.minX, 984)
        XCTAssertEqual(moving.before?.onScreen, true); XCTAssertEqual(moving.after?.onScreen, true)
        XCTAssertEqual(detail.peers.filter { $0.before?.onScreen != $0.after?.onScreen }.map(\.id), [167701])
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(before).verify(after)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedOrder)
        }
    }
    func testVisibilityAndOrderRemainIndependentMandatoryRefusals() throws {
        let (before, after, _) = try captured(), plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertThrowsError(try plan.verify(counterfactual(after, order: before.orderedWindowIDs))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .targetNotOnScreen)
        }
        let visible = MenuBarStatusTarget(id: after.target.id, pid: after.target.pid,
            frame: after.target.frame, onScreen: true, application: after.target.application)
        XCTAssertThrowsError(try plan.verify(counterfactual(after, target: visible))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedOrder)
        }
    }
    func testActualFalseOnScreenDoesNotMeanButtonStillInNotchOrMenuRegion() throws {
        let (before, after, _) = try captured()
        let areas = after.safeAreas.sorted { $0.minX < $1.minX }
        let notch = CGRect(x: areas[0].maxX, y: areas[0].minY,
            width: areas[1].minX - areas[0].maxX, height: areas[0].height)
        XCTAssertEqual(notch.minX, 771); XCTAssertEqual(notch.maxX, 956)
        XCTAssertTrue(areas[0].contains(before.targetButton)); XCTAssertTrue(areas[0].contains(after.targetButton))
        XCTAssertFalse(notch.intersects(after.targetButton)); XCTAssertFalse(after.applicationMenu.intersects(after.targetButton))
        XCTAssertEqual(after.targetButton.minX - after.applicationMenu.maxX, 71)
        XCTAssertFalse(after.target.onScreen)
        let detail = MenuBarNativeRevealDiagnostic.PostcheckDetail(before: before, after: after)
        XCTAssertTrue(detail.targetButtonInsideSafeArea); XCTAssertTrue(detail.targetButtonClearOfApplicationMenu)
        XCTAssertFalse(detail.targetOnScreen)
    }
    func testPeerIdentityChangeCannotBeExplainedAwayAsNativeMovement() throws {
        let (before, after, _) = try captured()
        var peers = after.peers
        let index = try XCTUnwrap(peers.firstIndex { $0.id == 125881 }), application = try XCTUnwrap(peers[index].application)
        peers[index].application = .init(bundleID: application.bundleID, bundlePath: application.bundlePath, launch: application.launch + 1)
        let different = counterfactual(after, order: before.orderedWindowIDs, peers: peers)
        XCTAssertEqual(MenuBarNativeRevealDiagnostic.PostcheckDetail(before: before, after: different).peerIdentitySetStable, false)
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(before).verify(different)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedIdentity)
        }
    }
    func testLegacyTraceHasNoInventedPostcheckAndNewEvidenceRoundTripsWithoutChangingFailure() throws {
        let (before, after, legacy) = try captured()
        XCTAssertNil(legacy.firstFailure?.postcheck)
        var trace = MenuBarNativeRevealDiagnostic(transaction: UUID())
        trace.append(stage: "after.first.verify", event: "failure", state: "revealing", elapsed: 580,
            error: MenuBarNativeRevealPlan.Failure.changedOrder,
            postcheck: .init(before: before, after: after))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(MenuBarNativeRevealDiagnostic.self, from: encoder.encode(trace))
        XCTAssertEqual(saved.firstFailure?.errorCode, "plan.changedOrder")
        XCTAssertEqual(saved.firstFailure?.postcheck?.peers.count, 30)
        XCTAssertEqual(saved.firstFailure?.postcheck?.peerIdentitySetStable, true)
        XCTAssertEqual(saved.firstFailure?.postcheck?.targetOnScreen, false)
    }
}

@MainActor
final class MenuBarNativePostcheckRestoreTests: XCTestCase {
    func testPostcheckEvidenceSurvivesAcknowledgedFailureRestoration() async throws {
        let driver = MenuBarNativeRevealFixtureDriver(), journal = MenuBarMemoryOwnedWidthJournal()
        driver.didSetLength = {
            if driver.length >= 0 { driver.orderedIDs = [1, 3, 2]; driver.targetOnScreen = false }
        }
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle); XCTAssertNil(journal.record)
        XCTAssertEqual(driver.writes, [105, -1]); XCTAssertEqual(driver.spacer.frame.width, 38)
        XCTAssertEqual(flow.diagnostic.firstFailure?.errorCode, "plan.changedOrder")
        let detail = try XCTUnwrap(flow.diagnostic.firstFailure?.postcheck)
        XCTAssertEqual(detail.beforeOrder, [1, 2, 3]); XCTAssertEqual(detail.afterOrder, [1, 3, 2])
        XCTAssertFalse(detail.targetOnScreen); XCTAssertTrue(detail.targetShiftMatchesMeasuredGrowth)
        XCTAssertEqual(flow.diagnostic.entries.last?.event, "restored")
    }
}
