import XCTest
import AppKit
import IOKit.pwr_mgt
import CoreFoundation
@testable import MacTools

final class Checks: XCTestCase {
    func testAppearanceSwitchAndPersistence() {
        _ = NSApplication.shared
        let original = NSApp.appearance
        let suite = "AppearanceTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { NSApp.appearance = original; defaults.removePersistentDomain(forName: suite) }
        defaults.set("invalid", forKey: "appearanceMode")
        let store = Store(defaults: defaults)
        XCTAssertEqual(store.appearanceMode, .system)
        for mode in [AppearanceMode.light, .dark, .system] {
            store.setAppearance(mode)
            XCTAssertEqual(defaults.string(forKey: "appearanceMode"), mode.rawValue)
            XCTAssertEqual(NSApp.appearance?.name, mode.nativeAppearance?.name)
            let reloaded = Store(defaults: defaults)
            XCTAssertEqual(reloaded.appearanceMode, mode)
        }
        print("APPEARANCE: light -> dark -> system; native app appearance and persisted reload verified")
    }
    func testUnlockAllAndShortcut() throws {
        let defaults = UserDefaults(suiteName: "UnlockAllTests.\(UUID())")!
        var writes = 0
        let store = Store(defaults: defaults, writeHardware: { _, _ in writes += 1 }, readHardware: { _ in 12 })
        store.apply(Preset(audio: true, value: 10, locked: true))
        store.apply(Preset(value: 40, locked: true))
        XCTAssertEqual(store.locks.count, 2)
        let before = writes
        store.releaseAllLocks()
        XCTAssertTrue(store.locks.isEmpty)
        store.enforceLocks()
        XCTAssertEqual(writes, before)
        let shortcutDefaults = UserDefaults(suiteName: "UnlockHotkeyTests.\(UUID())")!
        let shortcutStore = Store(defaults: shortcutDefaults)
        shortcutStore.unlockShortcut.key = "U"
        shortcutStore.saveUnlockShortcut()
        XCTAssertNil(shortcutStore.shortcutErrors[shortcutStore.unlockShortcut.id])
        let saved = try JSONDecoder().decode(Preset.self, from: shortcutDefaults.data(forKey: "unlockShortcut")!)
        XCTAssertEqual(saved.key, "U")
        var conflict = shortcutStore.unlockShortcut; conflict.id = UUID()
        shortcutStore.presets = [conflict]; shortcutStore.save()
        XCTAssertNotNil(shortcutStore.shortcutErrors[conflict.id])
        print("UNLOCK ALL: both locks removed without hardware write; shortcut persisted and conflict detected")
    }
    func testKeepAwakeNativeLifecycle() throws {
        let suite = "AwakeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var store: Store? = Store(defaults: defaults)
        XCTAssertFalse(store!.keepAwake)
        store!.setKeepAwake(true)
        defer { store?.setKeepAwake(false) }
        XCTAssertTrue(store!.keepAwake, store!.message)
        let ids = store!.awakeAssertions
        XCTAssertEqual(ids.count, 2)
        for id in ids { XCTAssertNotNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        store!.setKeepAwake(true)
        XCTAssertEqual(ids, store!.awakeAssertions)
        print("AWAKE native ON: two IOPM assertions exist; repeated ON creates no duplicates")
        store!.setKeepAwake(false)
        XCTAssertFalse(store!.keepAwake)
        for id in ids { XCTAssertNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        print("AWAKE native OFF: both assertions released")
        store!.setKeepAwake(true)
        let finalIDs = store!.awakeAssertions
        store = nil
        for id in finalIDs { XCTAssertNil(IOPMAssertionCopyProperties(id)?.takeRetainedValue()) }
        print("AWAKE deinit: assertions released; no audio writes")
    }
    func testLocksAndLegacyPresets() throws {
        let suite = "LockTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var values = [false: 50.0, true: 10.0]
        var fail = false
        let store = Store(defaults: defaults, writeHardware: { value, audio in
            if fail { throw Failure.message("simulated failure") }
            values[audio] = value
        }, readHardware: { values[$0]! })
        let old = Preset(name: "legacy")
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.locked)
        let audio = Preset(audio: true, value: 90, locked: true)
        let brightness = Preset(value: 40, locked: true)
        store.apply(audio); store.apply(brightness)
        XCTAssertEqual(values[true], 18)
        values[true] = 70; values[false] = 80
        store.enforceLocks()
        XCTAssertEqual(values[true], 18); XCTAssertEqual(values[false], 40)
        fail = true
        store.apply(Preset(audio: true, value: 10))
        XCTAssertEqual(store.locks[true], 18)
        fail = false
        store.apply(Preset(audio: true, value: 10))
        values[true] = 12; values[false] = 80
        store.enforceLocks()
        XCTAssertEqual(values[true], 12); XCTAssertEqual(values[false], 40)
        store.presets = []; store.save()
        XCTAssertEqual(store.locks[false], 40)
        store.apply(Preset(value: 50))
        XCTAssertTrue(store.locks.isEmpty)
        print("LOCK CHECK: legacy=unlocked; external-change=restored; failed-switch=retained; unlocked-switch=released; channels=independent")
    }
    func testWindowShortcutPersistenceAndConflict() throws {
        let suite = "MacToolsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store(defaults: defaults)
        store.windowShortcut.key = "8"
        store.windowShortcut.modifiers = UInt32(0x100 | 0x800 | 0x1000)
        store.saveWindowShortcut()
        XCTAssertNil(store.shortcutErrors[store.windowShortcut.id])
        var duplicate = store.windowShortcut; duplicate.id = UUID()
        store.presets = [duplicate]; store.save()
        XCTAssertNotNil(store.shortcutErrors[duplicate.id])
        let saved = try JSONDecoder().decode(Preset.self, from: defaults.data(forKey: "windowShortcut")!)
        XCTAssertEqual(saved.key, "8")
        XCTAssertEqual(saved.modifiers, store.windowShortcut.modifiers)
        store.windowShortcut.key = ""; store.saveWindowShortcut()
        XCTAssertNil(store.shortcutErrors[duplicate.id])
    }
    func testProtectionAndValidation() throws {
        for value in 0...100 {
            XCTAssertLessThanOrEqual(try appliedValue(Double(value), audio: true, protection: true), 18)
            XCTAssertEqual(try appliedValue(Double(value), audio: false, protection: true), Double(value))
            XCTAssertEqual(try appliedValue(Double(value), audio: true, protection: false), Double(value))
        }
        for invalid in [-1.0, 101, .nan, .infinity] {
            XCTAssertThrowsError(try appliedValue(invalid, audio: true, protection: true))
        }
    }
    func testPersistenceAndShortcutConflict() throws {
        let suite = "MacToolsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store(defaults: defaults)
        let preset = Preset(name: "安静", audio: true, value: 12, key: "9", modifiers: UInt32(0x100 | 0x800 | 0x1000))
        store.presets = [preset]; store.save()
        XCTAssertNil(store.shortcutErrors[preset.id])
        let decoded = try JSONDecoder().decode([Preset].self, from: defaults.data(forKey: "presets")!)
        XCTAssertEqual(decoded[0].id, preset.id)
        XCTAssertEqual(decoded[0].value, 12)
        var duplicate = preset; duplicate.id = UUID()
        store.presets.append(duplicate); store.save()
        XCTAssertNotNil(store.shortcutErrors[duplicate.id])
        store.presets = []; store.save()
        let restored = Store(defaults: defaults)
        XCTAssertTrue(restored.presets.isEmpty)
        XCTAssertTrue(restored.protection)
    }
}
