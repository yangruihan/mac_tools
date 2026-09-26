import XCTest
import SwiftUI
import IOKit.pwr_mgt
@testable import MacTools

final class Checks: XCTestCase {
    private var suites: [String] = []
    private func defaults() -> UserDefaults {
        let name = "MacToolsTests.\(UUID())"; suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites.removeAll(); super.tearDown()
    }
    private func context(_ id: String, defaults: UserDefaults, hotkeys: HotKeyService = HotKeyService()) -> PluginContext {
        PluginContext(settings: PluginSettings(id: id, defaults: defaults), hotkeys: hotkeys, report: { _ in })
    }

    func testAppearanceSwitchAndPersistence() {
        _ = NSApplication.shared
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let prefs = defaults(); prefs.set("invalid", forKey: "appearanceMode")
        let model = AppModel(defaults: prefs)
        XCTAssertEqual(model.appearanceMode, .system)
        for mode in [AppearanceMode.light, .dark, .system] {
            model.setAppearance(mode)
            XCTAssertEqual(prefs.string(forKey: "appearanceMode"), mode.rawValue)
            XCTAssertEqual(NSApp.appearance?.name, mode.nativeAppearance?.name)
            XCTAssertEqual(AppModel(defaults: prefs).appearanceMode, mode)
        }
    }

    func testLegacyMigrationAndSettingsIsolation() throws {
        let prefs = defaults()
        let preset = Preset(name: "安静", audio: true, value: 12, locked: true, key: "9")
        let legacy = try JSONEncoder().encode([preset])
        let oldShortcut = try JSONEncoder().encode(Preset(name: "解锁", key: "U"))
        prefs.set(legacy, forKey: "presets"); prefs.set(oldShortcut, forKey: "unlockShortcut")
        prefs.set(try JSONEncoder().encode(Preset(key: "M")), forKey: "windowShortcut")
        let plugin = QuickControlsPlugin(context: context(QuickControlsPlugin.id, defaults: prefs))
        XCTAssertEqual(plugin.presets.first?.id, preset.id)
        XCTAssertEqual(plugin.presets.first?.locked, true)
        XCTAssertEqual(plugin.unlockShortcut.key, "U")
        let host = AppModel(defaults: prefs)
        XCTAssertEqual(host.windowShortcut.key, "M")
        let legacyWindow = prefs.data(forKey: "windowShortcut")
        host.windowShortcut.key = "N"; host.saveWindowShortcut()
        XCTAssertEqual(prefs.data(forKey: "windowShortcut"), legacyWindow)
        XCTAssertEqual(AppModel(defaults: prefs).windowShortcut.key, "N")
        plugin.presets[0].value = 8; plugin.save()
        let scoped = plugin.context.settings.data(forKey: "presets")!
        XCTAssertEqual(try JSONDecoder().decode([Preset].self, from: scoped)[0].value, 8)
        XCTAssertEqual(prefs.data(forKey: "presets"), legacy, "Legacy bytes must remain available for rollback")
        let reloaded = QuickControlsPlugin(context: context(QuickControlsPlugin.id, defaults: prefs))
        XCTAssertEqual(reloaded.presets.first?.value, 8, "Migration must not overwrite current settings")
        XCTAssertNil(PluginSettings(id: "another-tool", defaults: prefs).data(forKey: "presets"))
        XCTAssertNil(try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(Preset())).locked)
        print("MIGRATION: preset IDs/lock/key preserved; legacy bytes unchanged; namespaced settings isolated")
    }

    func testLocksProtectionAndDisableCleanup() throws {
        var values = [false: 50.0, true: 10.0]; var writes = 0; var fail = false
        let plugin = QuickControlsPlugin(context: context(QuickControlsPlugin.id, defaults: defaults()), writeHardware: { value, audio in
            if fail { throw Failure.message("simulated failure") }; values[audio] = value; writes += 1
        }, readHardware: { values[$0]! })
        plugin.start()
        plugin.apply(Preset(audio: true, value: 90, locked: true)); plugin.apply(Preset(value: 40, locked: true))
        XCTAssertEqual(values[true], 18)
        values[true] = 70; values[false] = 80; plugin.enforceLocks()
        XCTAssertEqual(values[true], 18); XCTAssertEqual(values[false], 40)
        fail = true; plugin.apply(Preset(audio: true, value: 10)); XCTAssertEqual(plugin.locks[true], 18)
        fail = false; plugin.apply(Preset(audio: true, value: 10)); values[true] = 12; values[false] = 80; plugin.enforceLocks()
        XCTAssertEqual(values[true], 12); XCTAssertEqual(values[false], 40)
        plugin.presets = []; plugin.save(); XCTAssertEqual(plugin.locks[false], 40)
        let before = writes; plugin.releaseAllLocks(); plugin.enforceLocks(); XCTAssertEqual(writes, before)
        plugin.apply(Preset(value: 30, locked: true)); plugin.stop()
        XCTAssertTrue(plugin.locks.isEmpty); XCTAssertFalse(plugin.active)
        let stoppedWrites = writes; plugin.enforceLocks(); plugin.apply(Preset(value: 90))
        XCTAssertEqual(writes, stoppedWrites)
        print("QUICK CONTROLS: cap/restore/unlock preserved; stop clears locks/timer; stopped actions do not write")
    }

    func testProtectionAndValidation() throws {
        for value in 0...100 {
            XCTAssertLessThanOrEqual(try appliedValue(Double(value), audio: true, protection: true), 18)
            XCTAssertEqual(try appliedValue(Double(value), audio: false, protection: true), Double(value))
            XCTAssertEqual(try appliedValue(Double(value), audio: true, protection: false), Double(value))
        }
        for invalid in [-1.0, 101, .nan, .infinity] { XCTAssertThrowsError(try appliedValue(invalid, audio: true, protection: true)) }
    }

    func testCrossPluginShortcutConflictsAndRelease() throws {
        let service = HotKeyService()
        let chord = KeyChord(key: "8", modifiers: UInt32(0x100 | 0x800 | 0x1000))
        service.replace(owner: "app.window", actions: [.init(id: "toggle", chord: chord, perform: {})])
        service.replace(owner: "aaa-example", actions: [.init(id: "action", chord: chord, perform: {})])
        XCTAssertNil(service.error(owner: "app.window", id: "toggle"))
        XCTAssertNotNil(service.error(owner: "aaa-example", id: "action"))
        service.remove(owner: "app.window")
        XCTAssertNil(service.error(owner: "aaa-example", id: "action"), "Previously conflicted key should become usable")
        service.replace(owner: "aaa-example", actions: [.init(id: "a", chord: chord, perform: {}), .init(id: "a", chord: chord, perform: {})])
        XCTAssertNotNil(service.error(owner: "aaa-example", id: "a"))
        service.replace(owner: "aaa-example", actions: [.init(id: "a", chord: KeyChord(key: "A", modifiers: 0), perform: {})])
        XCTAssertNotNil(service.error(owner: "aaa-example", id: "a"))
        service.remove(owner: "aaa-example")
        let prefs = defaults(); let plugin = QuickControlsPlugin(context: context(QuickControlsPlugin.id, defaults: prefs, hotkeys: service))
        plugin.start(); plugin.unlockShortcut = chord; plugin.saveUnlockShortcut()
        XCTAssertNil(service.error(owner: plugin.info.id, id: "unlock"))
        XCTAssertEqual(try JSONDecoder().decode(KeyChord.self, from: plugin.context.settings.data(forKey: "unlockShortcut")!), chord)
        plugin.stop()
        service.replace(owner: "aaa-example", actions: [.init(id: "a", chord: chord, perform: {})])
        XCTAssertNil(service.error(owner: "aaa-example", id: "a"))
        print("HOTKEYS: cross-owner conflict surfaced; removing owner/disabled plugin releases chord")
    }

    func testKeepAwakeNativeLifecycle() throws {
        var plugin: KeepAwakePlugin? = KeepAwakePlugin(context: context(KeepAwakePlugin.id, defaults: defaults()))
        plugin!.start(); plugin!.setKeepAwake(true)
        defer { try? plugin?.stop() }
        XCTAssertTrue(plugin!.isKeepingAwake)
        let ids = plugin!.assertions; XCTAssertEqual(ids.count, 2)
        for id in ids { XCTAssertNotNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        plugin!.setKeepAwake(true); XCTAssertEqual(plugin!.assertions, ids)
        try plugin!.stop()
        for id in ids { XCTAssertNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        plugin!.setKeepAwake(true); XCTAssertFalse(plugin!.isKeepingAwake, "Disabled plugin must not acquire resources")
        plugin!.start(); plugin!.setKeepAwake(true); let finalIDs = plugin!.assertions; plugin = nil
        for id in finalIDs { XCTAssertNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        print("AWAKE: native assertions ON -> released on stop/deinit; no audio writes")
    }

    func testTrackpadDisableRestoresAndFailureRetainsRegistryState() throws {
        var writes: [Bool] = []; var fail = false
        let prefs = defaults()
        let plugin = TrackpadPlugin(context: context(TrackpadPlugin.id, defaults: prefs), applySystem: { value in
            if fail { throw Failure.message("simulated permission loss") }; writes.append(value)
        })
        let registry = try PluginRegistry(plugins: [plugin], defaults: prefs, report: { _ in })
        registry.startAll(); plugin.setDisabled(true); XCTAssertTrue(plugin.isDisabled)
        fail = true
        XCTAssertFalse(registry.setEnabled(false, id: plugin.info.id))
        XCTAssertTrue(registry.enabledIDs.contains(plugin.info.id)); XCTAssertTrue(plugin.isDisabled)
        fail = false; XCTAssertTrue(registry.setEnabled(false, id: plugin.info.id))
        XCTAssertFalse(plugin.isDisabled); XCTAssertEqual(writes, [true, false])
        plugin.setDisabled(true); XCTAssertEqual(writes, [true, false])
    }

    func testPluginDiscoveryLifecyclePersistenceAndDuplicateGuard() throws {
        let prefs = defaults(); let first = ProbePlugin("example.one"); let second = ProbePlugin("example.two")
        let registry = try PluginRegistry(plugins: [first, second], defaults: prefs, report: { _ in })
        registry.startAll(); registry.startAll(); XCTAssertEqual(first.starts, 1); XCTAssertEqual(second.starts, 1)
        XCTAssertEqual(registry.enabledPlugins.map { $0.info.title }, ["example.one", "example.two"])
        _ = registry.enabledPlugins.map { $0.makeView() }; _ = registry.enabledPlugins.map { $0.makeMenuItems() }
        XCTAssertTrue(registry.setEnabled(false, id: first.info.id)); XCTAssertEqual(first.stops, 1)
        let reloaded = try PluginRegistry(plugins: [ProbePlugin("example.one"), ProbePlugin("example.two")], defaults: prefs, report: { _ in })
        XCTAssertEqual(reloaded.enabledIDs, ["example.two"])
        registry.stopAll(); registry.stopAll(); XCTAssertEqual(second.stops, 1)
        XCTAssertThrowsError(try PluginRegistry(plugins: [first, first], defaults: prefs, report: { _ in }))
        XCTAssertThrowsError(try PluginRegistry(plugins: [ProbePlugin("../invalid")], defaults: prefs, report: { _ in }))
        XCTAssertThrowsError(try PluginRegistry(plugins: [ProbePlugin("app.window")], defaults: prefs, report: { _ in }))
        let failing = ProbePlugin("failing"); failing.failStart = true
        let failedRegistry = try PluginRegistry(plugins: [failing], defaults: defaults(), report: { _ in })
        failedRegistry.startAll(); XCTAssertFalse(failedRegistry.enabledIDs.contains("failing"))
        failing.failStop = true
        XCTAssertFalse(failedRegistry.setEnabled(true, id: "failing"))
        XCTAssertTrue(failedRegistry.enabledIDs.contains("failing"), "Failed cleanup must stay visible for retry")
        failing.failStop = false
        XCTAssertTrue(failedRegistry.setEnabled(false, id: "failing"))
        print("PLUGIN HOST: new plugin views/menu/lifecycle need no host branch; disable persists; invalid IDs rejected")
    }

    func testBuiltinsAndWindowShortcutPersistence() {
        let prefs = defaults(); let model = AppModel(defaults: prefs)
        XCTAssertEqual(Set(model.plugins.plugins.map { $0.info.id }), ["quick-controls", "keep-awake", "trackpad"])
        model.windowShortcut = KeyChord(key: "7", modifiers: 0x100 | 0x800 | 0x1000); model.saveWindowShortcut()
        XCTAssertEqual(AppModel(defaults: prefs).windowShortcut, model.windowShortcut)
    }
}

private final class ProbePlugin: ToolPlugin {
    let info: PluginInfo
    var starts = 0; var stops = 0; var failStart = false; var failStop = false
    init(_ id: String) { info = PluginInfo(id: id, title: id, symbol: "puzzlepiece", detail: "Test plugin", placement: .content) }
    func start() throws { starts += 1; if failStart { throw Failure.message("test start failure") } }
    func stop() throws { stops += 1; if failStop { throw Failure.message("test cleanup failure") } }
    func makeView() -> AnyView { AnyView(Text(info.title)) }
    func makeMenuItems() -> AnyView { AnyView(Text(info.title)) }
}
