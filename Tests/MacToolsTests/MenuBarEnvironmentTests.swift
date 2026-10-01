import XCTest
import AppKit
@testable import MacTools

final class MenuBarEnvironmentTests: XCTestCase {
    func testDisplayLocalConversionHandlesAboveLeftAndChangedMainDisplay() {
        let screen = MenuBarDisplay(id: 2, frame: CGRect(x: -533, y: 1329, width: 3360, height: 1890),
            quartzFrame: CGRect(x: -533, y: -1890, width: 3360, height: 1890), safeAreas: [])
        XCTAssertEqual(screen.quartz(CGRect(x: -300, y: 3195, width: 30, height: 24)), CGRect(x: -300, y: -1890, width: 30, height: 24))
        let moved = MenuBarDisplay(id: 2, frame: CGRect(x: 0, y: 0, width: 2512, height: 1413),
            quartzFrame: CGRect(x: 0, y: 0, width: 2512, height: 1413), safeAreas: [])
        XCTAssertEqual(moved.quartz(CGRect(x: 100, y: 1389, width: 30, height: 24)), CGRect(x: 100, y: 0, width: 30, height: 24))
    }
    func testNotchCoverageIsDistinctFromOutsideDisplay() {
        let screen = MenuBarDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), quartzFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
            safeAreas: [CGRect(x: 0, y: 1291, width: 918, height: 38), CGRect(x: 1138, y: 1291, width: 918, height: 38)])
        XCTAssertEqual(screen.availability(of: CGRect(x: 990, y: 0, width: 44, height: 43)), .occluded)
        XCTAssertEqual(screen.availability(of: CGRect(x: -1000, y: 0, width: 44, height: 43)), .outsideDisplay)
        XCTAssertEqual(screen.availability(of: CGRect(x: 1269, y: 0, width: 44, height: 43)), .visible)
        XCTAssertFalse(screen.anchorSafe(CGRect(x: 905, y: 1300, width: 30, height: 24)))
        XCTAssertTrue(screen.anchorSafe(CGRect(x: 1268, y: 1300, width: 46, height: 24)))
    }
    func testCollapsedDividerMayExtendOutsideItsDisplayButCannotCrossDisplayRows() {
        let screen = MenuBarDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), quartzFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329), safeAreas: [])
        let control = CGRect(x: 1700, y: 1286, width: 30, height: 43)
        XCTAssertTrue(screen.containsStatusPair(divider: CGRect(x: -3700, y: 1286, width: 5016, height: 43), control: control))
        XCTAssertFalse(screen.containsStatusPair(divider: CGRect(x: 1000, y: 3000, width: 24, height: 43), control: control))
        XCTAssertFalse(screen.containsStatusPair(divider: CGRect(x: -5000, y: 1286, width: 100, height: 43), control: control))
    }
    func testExternal24PointStatusWindowClipsIts27PointButtonLayout() {
        let external = MenuBarDisplay(id: 2, frame: CGRect(x: -533, y: 1329, width: 3360, height: 1890), quartzFrame: CGRect(x: -533, y: -1890, width: 3360, height: 1890), safeAreas: [])
        let window = CGRect(x: 2388, y: 3195, width: 38, height: 24)
        let button = CGRect(x: 2388, y: 3193.5, width: 38, height: 27)
        XCTAssertFalse(external.anchorSafe(button))
        XCTAssertTrue(external.anchorSafe(button, clippedTo: window))
        XCTAssertFalse(external.anchorSafe(button.offsetBy(dx: 1000, dy: 0), clippedTo: window.offsetBy(dx: 1000, dy: 0)))
        XCTAssertFalse(external.anchorSafe(button, clippedTo: .zero))
    }
    func testRapidDisplaySleepWakeAndAppChangesInvalidateOldWork() {
        var state = MenuBarEnvironment()
        let original = state.generation
        state.receive(.displaysChanged)
        XCTAssertFalse(state.accepts(original))
        let resized = state.generation
        state.receive(.willSleep)
        XCTAssertTrue(state.sleeping)
        XCTAssertFalse(state.accepts(state.generation))
        state.receive(.didWake)
        XCTAssertFalse(state.sleeping)
        XCTAssertFalse(state.accepts(resized))
        let awake = state.generation
        state.receive(.applicationsChanged)
        XCTAssertFalse(state.accepts(awake))
        XCTAssertTrue(state.accepts(state.generation))
    }
    func testAllScreenLifecycleEventsExpandAndRejectPendingCollapseAndCapture() throws {
        for event in [MenuBarEnvironment.Change.displaysChanged, .willSleep, .didWake] {
            var environment = MenuBarEnvironment(), visibility = MenuBarVisibility(), gallery = MenuBarGallerySession()
            visibility.enable()
            let collapse = try XCTUnwrap(visibility.beginCollapse())
            let capture = gallery.beginCapture()
            environment.receive(event)
            visibility.expand(); gallery.clear()
            XCTAssertEqual(visibility.state, .expanded)
            XCTAssertFalse(visibility.finishCollapse(collapse, recoveryVisible: true))
            XCTAssertFalse(gallery.finishCapture(capture, icons: [], visible: []))
        }
    }
    func testEnvironmentChangesAreInertWhenPluginHasNotOptedIn() {
        let name = "MenuBarEnvironmentTests.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let context = PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: preferences), hotkeys: HotKeyService(), report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        let before = plugin.status
        for event in [MenuBarEnvironment.Change.displaysChanged, .willSleep, .didWake, .applicationsChanged] { plugin.environmentChanged(event) }
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertEqual(plugin.status, before)
        XCTAssertNil(preferences.data(forKey: "plugin.menu-bar-organizer.optedIn"))
    }
    @MainActor func testMonitorUsesCorrectCentersAndStopsWithoutDuplicateObservers() {
        let screen = NotificationCenter(), workspace = NotificationCenter()
        var events: [MenuBarEnvironment.Change] = []
        let monitor = MenuBarEnvironmentMonitor(screenCenter: screen, workspaceCenter: workspace) { events.append($0) }
        monitor.start(); monitor.start()
        screen.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        XCTAssertEqual(events, [.displaysChanged, .willSleep, .didWake, .applicationsChanged, .applicationsChanged])
        screen.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(events.count, 5)
        monitor.stop()
        screen.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(events.count, 5)
    }
}
