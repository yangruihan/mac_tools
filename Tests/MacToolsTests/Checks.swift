import XCTest
@testable import MacTools

final class Checks: XCTestCase {
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
