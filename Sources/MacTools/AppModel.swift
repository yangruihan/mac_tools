import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class AppModel: ObservableObject {
    @Published private(set) var appearanceMode: AppearanceMode = .system
    @Published var windowShortcut = KeyChord(key: "M")
    @Published var message = "尚未应用配置；耳机保护默认开启"
    var toggleWindow: (() -> Void)?
    let hotkeys = HotKeyService()
    private let defaults: UserDefaults
    private var running = false

    // Single explicit registration point; adding a plugin requires no host UI branch.
    lazy var plugins: PluginRegistry = {
        let builtins: [any ToolPlugin] = [
            QuickControlsPlugin(context: context(for: QuickControlsPlugin.id)),
            KeepAwakePlugin(context: context(for: KeepAwakePlugin.id)),
            TrackpadPlugin(context: context(for: TrackpadPlugin.id))
        ]
        // IDs are compile-time constants covered by registry tests; never accept downloaded code here.
        return try! PluginRegistry(plugins: builtins, defaults: defaults, report: { [weak self] in self?.message = $0 })
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        if let data = defaults.data(forKey: "windowShortcut"), let chord = try? JSONDecoder().decode(KeyChord.self, from: data) { windowShortcut = chord }
    }
    private func context(for id: String) -> PluginContext {
        PluginContext(settings: PluginSettings(id: id, defaults: defaults), hotkeys: hotkeys,
                      report: { [weak self] in self?.message = $0 })
    }
    func setAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode; defaults.set(mode.rawValue, forKey: "appearanceMode")
        NSApp.appearance = mode.nativeAppearance
    }
    func start() {
        guard !running else { return }; running = true
        NSApp.appearance = appearanceMode.nativeAppearance
        registerWindowShortcut(); plugins.startAll()
    }
    func stop() { plugins.stopAll(); hotkeys.remove(owner: "app.window"); running = false }
    func saveWindowShortcut() {
        do {
            defaults.set(try JSONEncoder().encode(windowShortcut), forKey: "windowShortcut")
            if running { registerWindowShortcut() }
        } catch { message = "窗口快捷键保存失败：\(error.localizedDescription)" }
    }
    private func registerWindowShortcut() {
        hotkeys.replace(owner: "app.window", actions: [HotKeyAction(id: "toggle", chord: windowShortcut, perform: { [weak self] in self?.toggleWindow?() })])
    }
}
