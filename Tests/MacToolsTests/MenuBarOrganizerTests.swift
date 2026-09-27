import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarOrganizerTests: XCTestCase {
    func testFailOpenGeometryAndHiddenWindowSelection() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        XCTAssertTrue(MenuBarOrganizerPlugin.canCollapse(dividerX: 700, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: 770, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: -100, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: 700, controlX: 1300, screen: screen))
        let windows: [(id: CGWindowID, frame: CGRect)] = [
            (1, CGRect(x: 640, y: 0, width: 28, height: 24)),
            (2, CGRect(x: 670, y: 0, width: 28, height: 24)),
            (3, CGRect(x: 760, y: 0, width: 28, height: 24)),
            (4, CGRect(x: 650, y: 300, width: 28, height: 24)),
            (5, CGRect(x: 400, y: 0, width: 3000, height: 24))
        ]
        let first = MenuBarOrganizerPlugin.hiddenWindows(windows, leftOf: 710, in: screen, statusBarY: 0).map(\.id)
        XCTAssertEqual(first, [1, 2])
        var moved = windows
        moved[0] = (1, CGRect(x: 680, y: 0, width: 28, height: 24))
        moved[1] = (2, CGRect(x: 640, y: 0, width: 28, height: 24))
        XCTAssertNotEqual(MenuBarOrganizerPlugin.hiddenWindows(moved, leftOf: 710, in: screen, statusBarY: 0).map(\.id), first)
        print("MENU BAR: only candidate status windows left of separator; recovery control geometry fail-closed")
    }
    func testActivationIsOptInAndDoesNotTouchSystemAtStartup() throws {
        let name = "MenuOrganizerTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = HotKeyService()
        let context = PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults), hotkeys: service, report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        let registry = try PluginRegistry(plugins: [plugin], defaults: defaults, report: { _ in })
        registry.startAll()
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertFalse(plugin.isCollapsed)
        registry.stopAll()
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertNil(defaults.data(forKey: "plugin.menu-bar-organizer.optedIn"))
        XCTAssertNil(service.error(owner: plugin.info.id, id: "emergency-reveal"))
        print("MENU BAR: load/stop inert until user opts in; no status icons created")
    }
}
