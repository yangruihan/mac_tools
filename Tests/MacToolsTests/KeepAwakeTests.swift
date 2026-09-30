import XCTest
import IOKit.pwr_mgt
@testable import MacTools

final class KeepAwakeTests: XCTestCase {
    private final class PowerProbe {
        var live = Set<IOPMAssertionID>()
        var next: IOPMAssertionID = 1
        var creates = 0
        var failCreation: Int?
        var failRelease = false
        var backend: KeepAwakeAssertions {
            KeepAwakeAssertions(create: { [self] _ in
                creates += 1
                if creates == failCreation { throw Failure.message("creation rejected") }
                let id = next; next += 1; live.insert(id); return id
            }, release: { [self] id in
                if failRelease { throw Failure.message("release rejected") }
                live.remove(id)
            }, isValid: { [self] in live.contains($0) })
        }
    }
    private func fixture() -> (UserDefaults, PluginContext, String) {
        let name = "KeepAwakeTests.\(UUID())"
        let prefs = UserDefaults(suiteName: name)!
        let context = PluginContext(settings: PluginSettings(id: KeepAwakePlugin.id, defaults: prefs), hotkeys: HotKeyService(), report: { _ in })
        return (prefs, context, name)
    }
    func testSavedIntentSurvivesStopRestartAndExplicitOff() throws {
        let (prefs, context, name) = fixture(); defer { prefs.removePersistentDomain(forName: name) }
        let power = PowerProbe()
        let first = KeepAwakePlugin(context: context, power: power.backend)
        first.start(); XCTAssertFalse(first.requestedKeepAwake); XCTAssertTrue(power.live.isEmpty)
        first.setKeepAwake(true); let ids = first.assertions
        first.setKeepAwake(true); first.start()
        XCTAssertEqual(first.assertions, ids); XCTAssertEqual(power.creates, 2)
        try first.stop(); XCTAssertTrue(power.live.isEmpty)
        XCTAssertTrue(first.requestedKeepAwake)
        XCTAssertEqual(try JSONDecoder().decode(Bool.self, from: context.settings.data(forKey: "enabled")!), true)
        first.setKeepAwake(false); XCTAssertTrue(first.requestedKeepAwake, "Stopped plugin must not change user preference")
        let second = KeepAwakePlugin(context: context, power: power.backend)
        second.start(); XCTAssertTrue(second.requestedKeepAwake); XCTAssertTrue(second.isKeepingAwake)
        second.setKeepAwake(false); XCTAssertFalse(second.isKeepingAwake); XCTAssertTrue(power.live.isEmpty)
        try second.stop()
        let third = KeepAwakePlugin(context: context, power: power.backend)
        third.start(); XCTAssertFalse(third.requestedKeepAwake); XCTAssertFalse(third.isKeepingAwake)
        try third.stop()
    }
    func testCreateFailureRollsBackAndKeepsIntentForRetry() throws {
        let (prefs, context, name) = fixture(); defer { prefs.removePersistentDomain(forName: name) }
        let power = PowerProbe(); power.failCreation = 2
        let plugin = KeepAwakePlugin(context: context, power: power.backend); plugin.start()
        plugin.setKeepAwake(true)
        XCTAssertTrue(plugin.requestedKeepAwake); XCTAssertFalse(plugin.isKeepingAwake)
        XCTAssertTrue(power.live.isEmpty); XCTAssertTrue(plugin.status.contains("未正常生效"))
        plugin.retry(); XCTAssertTrue(plugin.isKeepingAwake); XCTAssertEqual(power.live.count, 2)
        try plugin.stop(); XCTAssertTrue(power.live.isEmpty)
    }
    func testPartialRollbackFailureRetainsIDsAndOffCanRetry() throws {
        let (prefs, context, name) = fixture(); defer { prefs.removePersistentDomain(forName: name) }
        let power = PowerProbe(); power.failCreation = 2; power.failRelease = true
        let plugin = KeepAwakePlugin(context: context, power: power.backend); plugin.start()
        plugin.setKeepAwake(true)
        XCTAssertEqual(plugin.assertions.count, 1); XCTAssertFalse(plugin.isKeepingAwake)
        XCTAssertTrue(plugin.status.contains("清理失败"))
        plugin.setKeepAwake(false); XCTAssertFalse(plugin.requestedKeepAwake)
        XCTAssertEqual(plugin.assertions.count, 1); XCTAssertTrue(plugin.status.contains("关闭未完成"))
        power.failRelease = false; plugin.retry()
        XCTAssertTrue(power.live.isEmpty); XCTAssertTrue(plugin.assertions.isEmpty)
        try plugin.stop()
    }
    func testLostAssertionIsDetectedAndRecreatedWithoutDuplicates() throws {
        let (prefs, context, name) = fixture(); defer { prefs.removePersistentDomain(forName: name) }
        let power = PowerProbe()
        let subject = KeepAwakePlugin(context: context, power: power.backend); subject.start(); subject.setKeepAwake(true)
        power.live.remove(subject.assertions[0]); subject.refreshStatus()
        XCTAssertTrue(subject.requestedKeepAwake); XCTAssertFalse(subject.isKeepingAwake)
        XCTAssertTrue(subject.status.contains("失效"))
        subject.retry(); XCTAssertTrue(subject.isKeepingAwake); XCTAssertEqual(power.live.count, 2)
        try subject.stop(); XCTAssertTrue(power.live.isEmpty)
    }
}
