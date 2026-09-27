import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarOrganizerTests: XCTestCase {
    func testStatusItemSlotsStayVisibleAndOrdered() {
        XCTAssertTrue(MenuBarOrganizerPlugin.sanePositions(control: 250, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: nil, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: 290, divider: 250))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: -4000, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: .nan, divider: 290))
    }
    func testMainTrayPositionRestoresOnDisable() throws {
        let name = "MenuOrganizerPosition.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let main = "NSStatusItem Preferred Position Item-0"
        defaults.set(648.0, forKey: main)
        defaults.set(try JSONEncoder().encode(true), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
        XCTAssertEqual(defaults.double(forKey: "plugin.menu-bar-organizer.priorMainPosition"), 648)
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
        defaults.set(try JSONEncoder().encode(false), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 648)
        XCTAssertNil(defaults.object(forKey: "plugin.menu-bar-organizer.priorMainPosition"))
        defaults.set(450.0, forKey: main)
        defaults.set(648.0, forKey: "plugin.menu-bar-organizer.priorMainPosition")
        defaults.set(try JSONEncoder().encode(true), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
    }
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
        let visible = MenuBarOrganizerPlugin.visibleWindows(windows, rightOf: 750, in: screen, statusBarY: 0).map(\.id)
        XCTAssertEqual(visible, [3])
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
    func testVisibleLimitIsClampedAndPersistedWithoutTouchingSystem() {
        let name = "MenuOrganizerTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let context = PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults),
                                    hotkeys: HotKeyService(), report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        plugin.setVisibleLimit(0)
        XCTAssertEqual(plugin.visibleLimit, 1)
        plugin.setVisibleLimit(500)
        XCTAssertEqual(plugin.visibleLimit, 30)
        let reopened = MenuBarOrganizerPlugin(context: context)
        reopened.start()
        XCTAssertEqual(reopened.visibleLimit, 30)
        XCTAssertFalse(reopened.isOrganizing)
        reopened.stop()
    }
    func testReorderStaysInsideItsLane() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let a = CGRect(x: 400, y: 0, width: 28, height: 24)
        let b = CGRect(x: 460, y: 0, width: 28, height: 24)
        let hidden = MenuBarOrganizerPlugin.reorderTarget(source: a, target: b, dividerX: 600, controlX: 650, screen: screen)
        XCTAssertEqual(hidden?.x, 496)
        XCTAssertEqual(hidden?.after, true)
        XCTAssertNil(MenuBarOrganizerPlugin.reorderTarget(source: a, target: CGRect(x: 700, y: 0, width: 28, height: 24),
                                                          dividerX: 600, controlX: 650, screen: screen))
    }
}
