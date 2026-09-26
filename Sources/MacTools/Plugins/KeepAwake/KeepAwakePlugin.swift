import SwiftUI
import IOKit.pwr_mgt

final class KeepAwakePlugin: ObservableObject, ToolPlugin {
    static let id = "keep-awake"
    let info = PluginInfo(id: id, title: "保持唤醒", symbol: "cup.and.saucer", detail: "防闲置熄屏与休眠；不保证防锁屏", placement: .utility)
    private let context: PluginContext
    private var active = false
    @Published private(set) var isKeepingAwake = false
    private(set) var assertions: [IOPMAssertionID] = []
    init(context: PluginContext) { self.context = context }

    func start() { active = true }
    func setKeepAwake(_ enabled: Bool) {
        guard active else { return }
        do { try change(enabled) }
        catch { context.report("保持唤醒操作失败：\(error.localizedDescription)") }
    }
    private func change(_ enabled: Bool) throws {
        guard enabled != isKeepingAwake else { return }
        if enabled {
            var created: [IOPMAssertionID] = []
            for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
                var id = IOPMAssertionID(0)
                let status = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacTools Keep Awake" as CFString, &id)
                guard status == kIOReturnSuccess else {
                    created.forEach { IOPMAssertionRelease($0) }
                    throw Failure.message("无法创建电源断言（\(status)）")
                }
                created.append(id)
            }
            assertions = created; isKeepingAwake = true
        } else {
            assertions = assertions.filter { IOPMAssertionRelease($0) != kIOReturnSuccess }
            isKeepingAwake = !assertions.isEmpty
            if isKeepingAwake { throw Failure.message("部分请求释放失败，请重试或退出应用") }
        }
    }
    func stop() throws { try change(false); active = false }
    deinit { assertions.forEach { IOPMAssertionRelease($0) } }
    func makeView() -> AnyView { AnyView(KeepAwakeView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(KeepAwakeMenu(plugin: self)) }
}
private struct KeepAwakeView: View {
    @ObservedObject var plugin: KeepAwakePlugin
    var body: some View {
        NativeToggleCard(title: plugin.info.title, detail: "防闲置熄屏与休眠", icon: plugin.info.symbol,
                         isOn: Binding(get: { plugin.isKeepingAwake }, set: plugin.setKeepAwake))
            .help("退出或停用插件后释放；不阻止手动锁屏、屏保锁屏或合盖")
    }
}
private struct KeepAwakeMenu: View {
    @ObservedObject var plugin: KeepAwakePlugin
    var body: some View { Toggle("保持唤醒", isOn: Binding(get: { plugin.isKeepingAwake }, set: plugin.setKeepAwake)) }
}
