import XCTest
import AppKit
@testable import MacTools

final class MenuBarItemDirectoryTests: XCTestCase {
    private let display = MenuBarDisplay(id: 1,
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        quartzFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        safeAreas: [CGRect(x: 0, y: 1291, width: 918, height: 38),
                    CGRect(x: 1138, y: 1291, width: 918, height: 38)])
    private func item(_ id: UInt32, x: CGFloat, pid: Int32 = 10, y: CGFloat = 0) -> MenuBarStatusTarget {
        MenuBarStatusTarget(id: id, pid: pid, frame: CGRect(x: x, y: y, width: 42, height: 43),
            onScreen: x >= 0,
            application: MenuBarApplicationIdentity(bundleID: "test.\(pid)", bundlePath: "/Test\(pid).app", launch: 1))
    }
    private func build(_ windows: [MenuBarStatusTarget], displays: [MenuBarDisplay]? = nil) -> [MenuBarDirectoryItem] {
        MenuBarItemDirectory.build(windows: windows, displays: displays ?? [display],
            displayID: 1, excludingPID: 99, applicationName: { _ in " Test " })
    }
    func testNotchOffscreenAndPartialOverlapRemainAccessibleWithoutImages() {
        let rows = build([item(1, x: 963), item(2, x: -3000), item(3, x: 800), item(4, x: 900)])
        XCTAssertEqual(rows.map(\.id), [2, 3, 4, 1])
        XCTAssertEqual(rows.map(\.position), [.offscreen, .nativeBar, .notch, .notch])
        XCTAssertEqual(rows.map(\.title), (1...4).map { "Test · 图标 \($0)" })
        XCTAssertTrue(rows.allSatisfy { !$0.identity.singletonAtCapture })
        let target = item(2, x: -3000)
        XCTAssertEqual(MenuBarIconIdentity.identify(rows[0].identity, windows: [target]).target?.id, 2)
    }
    func testExcludesOwnUnknownDuplicateAndInvalidWindows() {
        var unknown = item(3, x: 800); unknown.application = nil
        let invalid = MenuBarStatusTarget(id: 4, pid: 10, frame: CGRect(x: 800, y: 0, width: 150, height: 43),
            onScreen: true, application: item(4, x: 800).application)
        let rows = build([item(1, x: 963), item(2, x: 700, pid: 99), unknown, invalid,
                          item(5, x: 700), item(5, x: 750), item(6, x: 750, y: 100)])
        XCTAssertEqual(rows.map(\.id), [1])
        // The invalid/duplicated peers cannot make restart rematching less conservative.
        XCTAssertFalse(rows[0].identity.singletonAtCapture)
    }
    func testSameRowDisplaysRefuseAmbiguousOffscreenButKeepPhysicalSelectedDisplay() {
        let second = MenuBarDisplay(id: 2, frame: CGRect(x: 2056, y: 0, width: 1200, height: 1329),
            quartzFrame: CGRect(x: 2056, y: 0, width: 1200, height: 1329), safeAreas: [])
        let rows = build([item(1, x: 963), item(2, x: -3000), item(3, x: 2100)], displays: [display, second])
        XCTAssertEqual(rows.map(\.id), [1])
        XCTAssertFalse(rows[0].identity.singletonAtCapture, "Other display items still prohibit singleton restart rematching")
        let restarted = MenuBarStatusTarget(id: 4, pid: 11, frame: item(4, x: 963).frame, onScreen: true,
            application: MenuBarApplicationIdentity(bundleID: "test.10", bundlePath: "/Test10.app", launch: 2))
        XCTAssertEqual(MenuBarIconIdentity.identify(rows[0].identity, windows: [restarted]).failure, .ambiguous)
    }
    func testDuplicateOrOverlappingDisplayMappingIsNotGuessed() {
        XCTAssertTrue(build([item(1, x: 963)], displays: [display, display]).isEmpty)
        let overlapping = MenuBarDisplay(id: 2, frame: display.frame, quartzFrame: display.quartzFrame, safeAreas: [])
        XCTAssertTrue(build([item(1, x: 963)], displays: [display, overlapping]).isEmpty)
        XCTAssertTrue(build([item(1, x: 963)], displays: []).isEmpty)
    }
    func testDisplayLocalTransformAndApplicationNameFallback() throws {
        let external = MenuBarDisplay(id: 1, frame: CGRect(x: -1500, y: 300, width: 1500, height: 900),
            quartzFrame: CGRect(x: -1500, y: -300, width: 1500, height: 900), safeAreas: [])
        let target = item(1, x: -1400, y: -300)
        let rows = MenuBarItemDirectory.build(windows: [target], displays: [external], displayID: 1,
            excludingPID: 99, applicationName: { _ in "\n " })
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.position, .nativeBar)
        XCTAssertEqual(row.title, "test.10")
        XCTAssertEqual(row.identity.application, target.application)
        XCTAssertTrue(row.identity.singletonAtCapture)
    }
    @MainActor
    func testDirectoryEntryDoesNotEnableOptedOutPluginOrMutateConfiguration() throws {
        let name = "MenuBarDirectory.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults)
        settings.set(try JSONEncoder().encode(false), forKey: "optedIn")
        let plugin = MenuBarOrganizerPlugin(context: PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in }))
        // Existing initialization migrates presentationMode; measure only the new entry.
        let before = (defaults.persistentDomain(forName: name) ?? [:]) as NSDictionary
        plugin.start(); plugin.refreshNotchDirectory(); plugin.activateDirectoryItem(1)
        plugin.environmentChanged(.willSleep); plugin.refreshNotchDirectory(); plugin.stop()
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertFalse(plugin.showsNotchDirectory)
        XCTAssertTrue(plugin.directoryItems.isEmpty)
        XCTAssertTrue(((defaults.persistentDomain(forName: name) ?? [:]) as NSDictionary).isEqual(before),
                      "Directory entry must preserve its own configuration domain")
    }
}
