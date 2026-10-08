import XCTest
import AppKit
@testable import MacTools

/// These snapshots were outside the controller and are NOT an atomic before/after
/// pair. Replay only proves which independent predicates the recorded data fail.
final class MenuBarNativeCapturedReplayTests: XCTestCase {
    private let generation = UUID()
    private func captured(_ name: String) throws -> MenuBarNativeRevealPlan.Observation {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/evidence/menu-bar-native-live-acceptance-2026-10-02/\(name).json")
        let data = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func rect(_ d: [String: Any]) throws -> CGRect {
            CGRect(x: try XCTUnwrap(d["x"] as? Double), y: try XCTUnwrap(d["y"] as? Double),
                   width: try XCTUnwrap(d["width"] as? Double), height: try XCTUnwrap(d["height"] as? Double))
        }
        let rows = try XCTUnwrap(data["statusWindows"] as? [[String: Any]])
        let peers = try rows.map { d -> MenuBarStatusTarget in
            // launch=1 is a replay namespace, not a recovered kernel identity.
            .init(id: try XCTUnwrap(d["id"] as? UInt32), pid: try XCTUnwrap(d["pid"] as? Int32),
                frame: try rect(XCTUnwrap(d["frame"] as? [String: Any])), onScreen: try XCTUnwrap(d["onScreen"] as? Bool),
                application: .init(bundleID: try XCTUnwrap(d["bundle"] as? String),
                                   bundlePath: try XCTUnwrap(d["appPath"] as? String), launch: 1))
        }.filter { abs($0.frame.minY) < 1 }.sorted { ($0.frame.minX, $0.id) < ($1.frame.minX, $1.id) }
        let target = try XCTUnwrap(peers.first { $0.id == 307723 })
        let control = try XCTUnwrap(peers.first { $0.id == 307719 })
        let recovery = try XCTUnwrap(peers.first { $0.id == 307718 })
        let targetAX = try XCTUnwrap(data["selfTargetAXFrames"] as? [[String: Any]]).map { try rect($0) }
        let button = try MenuBarNativeObservation.button(targetAX, matching: target)
        let extras = try XCTUnwrap(data["ownExtras"] as? [[String: Any]])
        let recoveryAX = try extras.map { try rect(XCTUnwrap($0["frame"] as? [String: Any])) }
        let recoveryButton = try MenuBarNativeObservation.button(recoveryAX, matching: recovery)
        let menus = try XCTUnwrap(data["frontMenuFrames"] as? [[String: Any]]).map { try rect($0) }
        let menuMax = try XCTUnwrap(menus.map(\.maxX).max())
        return .init(generation: generation, displayID: 1, target: target, targetButton: button,
            ownedSpacer: control.frame, recoveryButton: recoveryButton,
            safeAreas: [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)],
            applicationMenu: CGRect(x: 0, y: 0, width: menuMax, height: 38), orderedWindowIDs: peers.map(\.id),
            peers: peers, frontPID: try XCTUnwrap(data["frontPID"] as? Int32), frontApplication: nil, recoveryTarget: recovery)
    }
    private func fixingContext(_ after: MenuBarNativeRevealPlan.Observation,
                               to before: MenuBarNativeRevealPlan.Observation,
                               fixOrder: Bool = false) -> MenuBarNativeRevealPlan.Observation {
        .init(generation: after.generation, displayID: after.displayID, target: after.target,
            targetButton: after.targetButton, ownedSpacer: after.ownedSpacer, recoveryButton: after.recoveryButton,
            safeAreas: after.safeAreas, applicationMenu: before.applicationMenu,
            orderedWindowIDs: fixOrder ? before.orderedWindowIDs : after.orderedWindowIDs,
            peers: after.peers, frontPID: before.frontPID, frontApplication: before.frontApplication,
            recoveryTarget: after.recoveryTarget)
    }
    func testRecordedMenuSwitchRejectsBeforeOrderAndVisibility() throws {
        let before = try captured("preflight-current"), after = try captured("reveal-actual")
        let plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertEqual(plan.requestedExtraLength, 29)
        XCTAssertEqual(before.applicationMenu.maxX, 594); XCTAssertEqual(after.applicationMenu.maxX, 383)
        XCTAssertThrowsError(try plan.verify(after)) { XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedEnvironment) }
    }
    func testStableMenuCounterfactualStillRejectsHiddenSystemWindowOrderChanges() throws {
        let before = try captured("preflight-current"), after = fixingContext(try captured("reveal-actual"), to: before)
        let changed = before.peers.filter { old in
            after.peers.contains { $0.id == old.id && $0.frame == old.frame && !$0.onScreen }
        }
        XCTAssertTrue(changed.contains { $0.id == 6863 })
        XCTAssertTrue(changed.contains { $0.id == 19 })
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(before).verify(after)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedOrder)
        }
    }
    func testStableContextAndOrderCounterfactualStillRequiresOrderedOnScreenTarget() throws {
        let before = try captured("preflight-current")
        let after = fixingContext(try captured("reveal-actual"), to: before, fixOrder: true)
        XCTAssertEqual(after.ownedSpacer.width - before.ownedSpacer.width, 45)
        XCTAssertEqual(before.targetButton.minX - after.targetButton.minX, 45)
        XCTAssertTrue(after.safeAreas[0].contains(after.targetButton)); XCTAssertFalse(after.target.onScreen)
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(before).verify(after)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .targetNotOnScreen)
        }
    }
}
