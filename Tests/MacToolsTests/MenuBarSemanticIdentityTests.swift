import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarSemanticIdentityTests: XCTestCase {
    func testAXGeometryRevalidationPreservesOffscreenIdentityButRejectsLayoutChanges() {
        let application = MenuBarApplicationIdentity(bundleID: "test", bundlePath: "/test.app", launch: 1)
        let original = MenuBarStatusTarget(id: 1, pid: 2, frame: CGRect(x: -3000, y: 0, width: 26, height: 22), onScreen: false, application: application)
        XCTAssertTrue(MenuBarAXActivator.geometryMatches(original, current: original))
        var changed = MenuBarStatusTarget(id: 1, pid: 2, frame: original.frame.offsetBy(dx: 2, dy: 0), onScreen: false, application: application)
        XCTAssertFalse(MenuBarAXActivator.geometryMatches(original, current: changed))
        changed = original; changed.application = MenuBarApplicationIdentity(bundleID: "test", bundlePath: "/test.app", launch: 2)
        XCTAssertFalse(MenuBarAXActivator.geometryMatches(original, current: changed))
        changed = MenuBarStatusTarget(id: 1, pid: 2, frame: CGRect(x: CGFloat.nan, y: 0, width: 26, height: 22), onScreen: false, application: application)
        XCTAssertFalse(MenuBarAXActivator.geometryMatches(original, current: changed))
    }
    private func item(_ id: UInt32 = 1, pid: Int32 = 10, launch: Double = 1, x: Double = 990, visible: Bool = true) -> MenuBarStatusTarget {
        MenuBarStatusTarget(id: id, pid: pid, frame: CGRect(x: x, y: 0, width: 30, height: 24), onScreen: visible,
            application: MenuBarApplicationIdentity(bundleID: "com.example.test", bundlePath: "/Applications/Test.app", launch: launch))
    }
    func testSemanticIdentitySurvivesOcclusionWithoutMakingCoordinateClickSafe() {
        let a = item(), identity = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a])
        XCTAssertEqual(MenuBarIconIdentity.identify(identity, windows: [a]).target?.id, a.id)
        let safe = [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)]
        XCTAssertEqual(MenuBarIconIdentity.resolve(identity, windows: [a], safeAreas: safe).failure, .occluded)
    }
    func testExactCurrentLaunchCanIdentifyOffscreenItemWithoutGuessingAnotherCopy() {
        let a = item(visible: false), other = item(2, x: 300)
        let identity = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a, other])
        XCTAssertEqual(MenuBarIconIdentity.identify(identity, windows: [a, other]).target?.id, a.id)
        let parked = item(x: -3200, visible: false)
        let captured = MenuBarIconIdentity(capturing: parked, peersOnDisplay: [parked, other])
        XCTAssertEqual(MenuBarIconIdentity.identify(captured, windows: [parked, other], preferredDisplay: CGRect(x: 0, y: 0, width: 1400, height: 900)).target?.id, parked.id)
    }
    func testRestartOnlyRematchesSingletonAndRejectsDuplicateOrRecycledOwner() {
        let a = item(), identity = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a])
        let restart = item(22, pid: 40, launch: 2)
        XCTAssertEqual(MenuBarIconIdentity.identify(identity, windows: [restart]).target?.id, 22)
        XCTAssertEqual(MenuBarIconIdentity.identify(identity, windows: [restart, item(23, pid: 40, launch: 2)]).failure, .ambiguous)
        let multi = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a, item(2)])
        XCTAssertEqual(MenuBarIconIdentity.identify(multi, windows: [restart]).failure, .ambiguous)
        let wrong = MenuBarStatusTarget(id: a.id, pid: a.pid, frame: a.frame, onScreen: true,
            application: MenuBarApplicationIdentity(bundleID: "other", bundlePath: "/Applications/Other.app", launch: 1))
        XCTAssertEqual(MenuBarIconIdentity.identify(identity, windows: [wrong]).failure, .missing)
    }
}
