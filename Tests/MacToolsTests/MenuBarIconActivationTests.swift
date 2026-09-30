import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarIconActivationTests: XCTestCase {
    func testTallerNotchBackingWindowUsesItsSafeVisibleCenter() {
        let window = MenuBarStatusTarget(id: 67, pid: 456, frame: CGRect(x: 1269, y: 0, width: 44, height: 43), onScreen: true)
        XCTAssertNotNil(MenuBarIconActivation.target(id: 67, pid: 456, windows: [window], safeAreas: [CGRect(x: 1138, y: 0, width: 918, height: 38)]))
    }
    func testForegroundHitAcceptsVisibleButtonHeightAndRejectsAdjacentMenu() {
        let window = CGRect(x: 1269, y: 0, width: 44, height: 43)
        XCTAssertTrue(MenuBarIconActivation.hitMatches(CGRect(x: 1268, y: 9.5, width: 46, height: 24), window: window))
        XCTAssertTrue(MenuBarIconActivation.hitMatches(CGRect(x: 1280, y: 10.5, width: 22, height: 22), window: window))
        XCTAssertFalse(MenuBarIconActivation.hitMatches(CGRect(x: 1222, y: 9.5, width: 46, height: 24), window: window))
        XCTAssertFalse(MenuBarIconActivation.hitMatches(CGRect(x: 1210, y: 0, width: 300, height: 24), window: window))
        XCTAssertFalse(MenuBarIconActivation.hitMatches(.zero, window: window))
    }
    func testOnlyCurrentVisibleSameOwnerUniqueSafeTargetCanActivate() {
        let areas = [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)]
        let good = MenuBarStatusTarget(id: 67, pid: 456, frame: CGRect(x: 1269, y: 0, width: 44, height: 43), onScreen: true)
        func target(_ windows: [MenuBarStatusTarget], owner: Int32 = 456) -> MenuBarStatusTarget? {
            MenuBarIconActivation.target(id: 67, pid: owner, windows: windows, safeAreas: areas)
        }
        XCTAssertEqual(target([good])?.id, 67)
        XCTAssertNil(target([good], owner: 999))
        XCTAssertNil(target([]))
        XCTAssertNil(target([good, good]))
        XCTAssertNil(target([MenuBarStatusTarget(id: 67, pid: 456, frame: good.frame, onScreen: false)]))
        XCTAssertNil(target([MenuBarStatusTarget(id: 67, pid: 456, frame: CGRect(x: 990, y: 0, width: 44, height: 43), onScreen: true)]))
        XCTAssertNil(target([good, MenuBarStatusTarget(id: 12, pid: 888, frame: good.frame, onScreen: true)]))
        let moved = MenuBarStatusTarget(id: 67, pid: 456, frame: good.frame.offsetBy(dx: 10, dy: 0), onScreen: true)
        XCTAssertFalse(MenuBarIconActivation.unchanged(good, moved))
        XCTAssertTrue(MenuBarIconActivation.unchanged(good, good))
    }
    func testSafeCoordinateMappingSupportsNegativeExternalDisplays() {
        let item = MenuBarStatusTarget(id: 3, pid: 123, frame: CGRect(x: -300, y: -1890, width: 30, height: 24), onScreen: true)
        XCTAssertNotNil(MenuBarIconActivation.target(id: 3, pid: 123, windows: [item], safeAreas: [CGRect(x: -533, y: -1890, width: 3360, height: 1890)]))
    }
}
