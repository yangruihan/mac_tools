import SwiftUI
import IOKit.pwr_mgt

struct KeepAwakeAssertions {
    var create: (String) throws -> IOPMAssertionID
    var release: (IOPMAssertionID) throws -> Void
    var isValid: (IOPMAssertionID) -> Bool
    static let native = Self(create: { type in
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacTools Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { throw Failure.message("无法创建电源断言（\(result)）") }
        return id
    }, release: { id in
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw Failure.message("无法释放电源断言（\(result)）；请重试或退出应用") }
    }, isValid: { id in
        guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any] else { return false }
        return (properties[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == Int(kIOPMAssertionLevelOn)
    })
}

final class KeepAwakePlugin: ObservableObject, ToolPlugin {
    static let id = "keep-awake"
    let info = PluginInfo(id: id, title: "保持唤醒", symbol: "cup.and.saucer", detail: "防闲置熄屏与休眠；不保证防锁屏", placement: .utility)
    private let context: PluginContext
    private let power: KeepAwakeAssertions
    private var active = false
    @Published private(set) var requestedKeepAwake: Bool
    @Published private(set) var isKeepingAwake = false
    @Published private(set) var status = "已关闭；允许系统按原设置闲置熄屏与休眠。"
    private(set) var assertions: [IOPMAssertionID] = []
    init(context: PluginContext, power: KeepAwakeAssertions = .native) {
        self.context = context; self.power = power
        requestedKeepAwake = context.settings.data(forKey: "enabled").flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } ?? false
    }
    func start() {
        guard !active else { return }; active = true
        applyRequestedState()
    }
    func setKeepAwake(_ enabled: Bool) {
        guard active else { return }
        requestedKeepAwake = enabled
        if let data = try? JSONEncoder().encode(enabled) { context.settings.set(data, forKey: "enabled") }
        applyRequestedState()
    }
    func refreshStatus() {
        assertions = assertions.filter(power.isValid)
        isKeepingAwake = assertions.count == 2
        if requestedKeepAwake && !isKeepingAwake {
            status = "已保存开启选择，但电源断言已失效；点击重试。"
        } else if !requestedKeepAwake && !assertions.isEmpty {
            status = "关闭尚未完成，仍有电源断言；请重试或退出应用。"
        } else {
            status = isKeepingAwake ? "已生效：系统与屏幕的闲置休眠断言均有效。" : "已关闭；允许系统按原设置闲置熄屏与休眠。"
        }
    }
    func retry() { guard active else { return }; applyRequestedState() }
    private func applyRequestedState() {
        do {
            try change(requestedKeepAwake)
            refreshStatus()
        } catch {
            isKeepingAwake = assertions.count == 2 && assertions.allSatisfy(power.isValid)
            status = "\(requestedKeepAwake ? "已保存开启选择，但未正常生效" : "关闭未完成")：\(error.localizedDescription)"
            context.report("保持唤醒：\(status)")
        }
    }
    private func releaseAssertions() throws {
        var failed: [IOPMAssertionID] = []
        var firstError: Error?
        for id in assertions where power.isValid(id) {
            do { try power.release(id) }
            catch { failed.append(id); if firstError == nil { firstError = error } }
        }
        assertions = failed
        isKeepingAwake = assertions.count == 2 && assertions.allSatisfy(power.isValid)
        if let firstError { throw firstError }
    }
    private func change(_ enabled: Bool) throws {
        assertions = assertions.filter(power.isValid)
        if enabled && assertions.count == 2 { return }
        try releaseAssertions()
        guard enabled else { return }
        do {
            for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
                assertions.append(try power.create(type))
            }
        } catch {
            let creationError = error
            do { try releaseAssertions() }
            catch { throw Failure.message("\(creationError.localizedDescription)；清理失败：\(error.localizedDescription)") }
            throw creationError
        }
        guard assertions.count == 2 && assertions.allSatisfy(power.isValid) else {
            try releaseAssertions()
            throw Failure.message("系统未确认电源断言有效，请重试")
        }
        isKeepingAwake = true
    }
    func stop() throws {
        active = false
        try releaseAssertions()
        status = requestedKeepAwake ? "本次运行已停止；保留开启选择，下次启动恢复。" : "本次运行已停止；保持关闭选择。"
    }
    deinit { assertions.forEach { try? power.release($0) } }
    func makeView() -> AnyView { AnyView(KeepAwakeView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(KeepAwakeMenu(plugin: self)) }
}
private struct KeepAwakeView: View {
    @ObservedObject var plugin: KeepAwakePlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NativeToggleCard(title: plugin.info.title, detail: "防闲置熄屏与休眠 · 重启应用后恢复选择", icon: plugin.info.symbol,
                             isOn: Binding(get: { plugin.requestedKeepAwake }, set: plugin.setKeepAwake))
            Text(plugin.status).font(.callout).foregroundStyle(plugin.requestedKeepAwake && !plugin.isKeepingAwake ? .orange : .secondary)
                .accessibilityIdentifier("keep-awake-effective-status")
            HStack {
                Button("检查生效状态") { plugin.refreshStatus() }
                if plugin.requestedKeepAwake != plugin.isKeepingAwake { Button("重试") { plugin.retry() } }
            }
            Text("开启会增加电源消耗。退出或停用插件即释放断言；不会阻止手动睡眠、锁屏、合盖或低电量保护，也不会添加开机登录项。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct KeepAwakeMenu: View {
    @ObservedObject var plugin: KeepAwakePlugin
    var body: some View { Toggle("保持唤醒", isOn: Binding(get: { plugin.requestedKeepAwake }, set: plugin.setKeepAwake)) }
}
