import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarIconIdentityTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1400, height: 38)
    private func target(_ id: UInt32 = 1, pid: Int32 = 10, bundle: String = "com.example.tray", path: String = "/Applications/Tray.app", launch: Double = 1, x: Double = 100, onScreen: Bool = true) -> MenuBarStatusTarget {
        MenuBarStatusTarget(id: id, pid: pid, frame: CGRect(x: x, y: 0, width: 30, height: 24), onScreen: onScreen,
            application: MenuBarApplicationIdentity(bundleID: bundle, bundlePath: path, launch: launch))
    }
    private func resolve(_ identity: MenuBarIconIdentity, _ windows: [MenuBarStatusTarget]) -> MenuBarIconResolution {
        MenuBarIconIdentity.resolve(identity, windows: windows, safeAreas: [area])
    }
    func testRestartRematchesOnlyUniqueSameBundleAndPath() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        let restarted = target(22, pid: 40, launch: 2, x: 800)
        XCTAssertEqual(resolve(identity, [restarted]).target?.id, 22)
        XCTAssertEqual(resolve(identity, [target(22, pid: 40, path: "/tmp/Tray.app", launch: 2)]).failure, .missing)
        XCTAssertEqual(resolve(identity, []).failure, .missing)
    }
    func testReusedWindowAndPIDCannotClickDifferentApplicationOrLaunch() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        XCTAssertEqual(resolve(identity, [target(bundle: "com.example.other")]).failure, .missing)
        XCTAssertEqual(resolve(identity, [target(1, launch: 3)]).target?.application?.launch, 3)
        let anonymous = MenuBarStatusTarget(id: 1, pid: 10, frame: old.frame, onScreen: true)
        XCTAssertEqual(resolve(MenuBarIconIdentity(capturing: anonymous, peersOnDisplay: [anonymous]), [anonymous]).failure, .unverifiedIdentity)
    }
    func testReorderingUsesIdentityInsteadOfScreenshotCoordinates() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        let shifted = target(x: 500)
        XCTAssertEqual(resolve(identity, [shifted, target(9, pid: 99, bundle: "com.example.other", path: "/Applications/Other.app", x: 100)]).target?.frame.minX, 500)
    }
    func testMultiIconApplicationRefusesFallbackAfterRestartOrDisappearance() {
        let a = target(), b = target(2, x: 200)
        let identity = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a, b])
        XCTAssertEqual(resolve(identity, [b, a]).target?.id, 1)
        XCTAssertEqual(resolve(identity, [target(20, pid: 40, launch: 2)]).failure, .ambiguous)
        let singleton = MenuBarIconIdentity(capturing: a, peersOnDisplay: [a])
        XCTAssertEqual(resolve(singleton, [target(20, pid: 40, launch: 2), target(21, pid: 40, launch: 2, x: 300)]).failure, .ambiguous)
    }
    func testMirroredOffscreenCopyDoesNotOverrideActiveDisplayAndNotchIsReported() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        XCTAssertEqual(resolve(identity, [target(onScreen: false), target(2, x: 300)]).target?.id, 2)
        XCTAssertEqual(resolve(identity, [target(onScreen: false)]).failure, .offScreen)
        XCTAssertEqual(MenuBarIconIdentity.resolve(identity, windows: [target(x: 990)], safeAreas: [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)]).failure, .occluded)
        XCTAssertEqual(resolve(identity, [old, target(8, pid: 80, bundle: "com.other", x: 100)]).failure, .overlapped)
    }
    func testTwoVisibleDisplaysAreAmbiguousWithoutPreferredDisplay() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        XCTAssertEqual(resolve(identity, [target(8), target(9, x: 400)]).failure, .ambiguous)
    }
    func testFallbackUsesCurrentAnchorDisplayWithoutClickingOtherDisplayCopy() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        let mainCopy = target(2, x: 300), externalCopy = target(3, x: -300)
        XCTAssertEqual(MenuBarIconIdentity.resolve(identity, windows: [mainCopy, externalCopy], safeAreas: [area], preferredDisplay: area).target?.id, 2)
        XCTAssertNil(MenuBarIconIdentity.resolve(identity, windows: [externalCopy], safeAreas: [area], preferredDisplay: area).target)
    }
    func testUnknownOrInvalidLaunchAndGeometryNeverResolve() {
        let old = target(), identity = MenuBarIconIdentity(capturing: old, peersOnDisplay: [old])
        XCTAssertNil(resolve(identity, [target(launch: .nan)]).target)
        let invalid = MenuBarStatusTarget(id: 1, pid: 10, frame: CGRect(x: 100, y: 0, width: 400, height: 24), onScreen: true, application: old.application)
        XCTAssertEqual(resolve(identity, [invalid]).failure, .invalidGeometry)
    }
    func testCacheInvalidationPreservesSevenItemsButRejectsOldCaptureCompletion() {
        var gallery = MenuBarGallerySession()
        let generation = gallery.beginCapture()
        let icons = (0..<7).map { ShelfIcon(id: UInt32($0), frame: .zero, image: nil) }
        XCTAssertTrue(gallery.finishCapture(generation, icons: [], visible: icons))
        gallery.invalidateTargets()
        XCTAssertEqual(gallery.visibleIcons.count, 7)
        XCTAssertFalse(gallery.finishCapture(generation, icons: [], visible: []))
        let active = gallery.beginCapture()
        gallery.invalidateTargets()
        XCTAssertFalse(gallery.isCapturing)
        XCTAssertFalse(gallery.finishCapture(active, icons: icons, visible: []))
    }
}
