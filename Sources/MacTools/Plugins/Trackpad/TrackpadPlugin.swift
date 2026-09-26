import SwiftUI
import ApplicationServices

final class TrackpadPreference {
    private var previous = false
    private(set) var enabled = false

    private func systemToggle() throws -> AXUIElement {
        let trust = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(trust) else { throw Failure.message("需要辅助功能权限；授权 Mac 工具箱后重试") }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?PointerControl") else { throw Failure.message("无法打开指针控制设置") }
        NSWorkspace.shared.open(url)
        for _ in 0..<30 {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
               let toggle = findToggle(AXUIElementCreateApplication(app.processIdentifier)) { return toggle }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure.message("找不到系统的内置触控板开关；系统版本可能不兼容")
    }

    private func findToggle(_ element: AXUIElement) -> AXUIElement? {
        var id: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &id) == .success,
           String(describing: id).contains("AX_IGNORE_TRACKPAD") { return element }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let children = children as? [AXUIElement] {
            for child in children { if let found = findToggle(child) { return found } }
        }
        return nil
    }

    private func value(_ toggle: AXUIElement) throws -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(toggle, kAXValueAttribute as CFString, &raw) == .success,
              let number = raw as? NSNumber else { throw Failure.message("无法读取系统触控板开关") }
        return number.boolValue
    }

    func setEnabled(_ on: Bool) throws {
        guard on != enabled else { return }
        let toggle = try systemToggle()
        let current = try value(toggle)
        if on { previous = current }
        let desired = on ? true : previous
        if current != desired {
            guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success,
                  try value(toggle) == desired else { throw Failure.message("系统触控板开关未生效") }
        }
        enabled = on
    }
    deinit { if enabled { try? setEnabled(false) } }
}


final class TrackpadPlugin: ObservableObject, ToolPlugin {
    static let id = "trackpad"
    let info = PluginInfo(id: id, title: "屏蔽内置触控板", symbol: "hand.draw", detail: "需辅助功能权限；仅外接鼠标时生效", placement: .utility)
    private let context: PluginContext
    private var active = false
    private let applySystem: (Bool) throws -> Void
    @Published private(set) var isDisabled = false
    init(context: PluginContext, applySystem: ((Bool) throws -> Void)? = nil) {
        self.context = context
        self.applySystem = applySystem ?? TrackpadPreference().setEnabled
    }
    func start() { active = true }
    func setDisabled(_ enabled: Bool) {
        guard active else { return }
        do {
            try applySystem(enabled); isDisabled = enabled
            context.report(enabled ? "系统已开启：有外接鼠标时忽略内置触控板" : "已恢复原触控板系统设置")
        } catch { context.report(error.localizedDescription) }
    }
    func stop() throws { if isDisabled { try applySystem(false); isDisabled = false }; active = false }
    deinit { if isDisabled { try? applySystem(false) } }
    func makeView() -> AnyView { AnyView(TrackpadView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(TrackpadMenu(plugin: self)) }
}
private struct TrackpadView: View {
    @ObservedObject var plugin: TrackpadPlugin
    var body: some View {
        NativeToggleCard(title: plugin.info.title, detail: "仅外接鼠标时生效", icon: plugin.info.symbol,
                         isOn: Binding(get: { plugin.isDisabled }, set: plugin.setDisabled))
            .help("需要辅助功能权限；正常退出或停用插件时恢复原系统开关")
    }
}
private struct TrackpadMenu: View {
    @ObservedObject var plugin: TrackpadPlugin
    var body: some View { Toggle("有外接鼠标时屏蔽内置触控板", isOn: Binding(get: { plugin.isDisabled }, set: plugin.setDisabled)) }
}
