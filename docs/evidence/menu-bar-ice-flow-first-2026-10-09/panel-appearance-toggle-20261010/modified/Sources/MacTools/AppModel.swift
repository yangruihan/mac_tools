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
    @Published var message = "工具箱已就绪"
    var toggleWindow: (() -> Void)?
    var showToolbox: (() -> Void)?
    @Published var selectedPluginID: String? = QuickControlsPlugin.id
    let hotkeys = HotKeyService()
    private let defaults: UserDefaults
    private var running = false

    // Single explicit registration point; adding a plugin requires no host UI branch.
    lazy var plugins: PluginRegistry = {
        #if ICE_MENU_BAR_CANDIDATE
        let builtins: [any ToolPlugin] = [MenuBarOrganizerPlugin(context: context(for: MenuBarOrganizerPlugin.id))]
        #else
        let builtins: [any ToolPlugin] = [
            QuickControlsPlugin(context: context(for: QuickControlsPlugin.id)),
            KeepAwakePlugin(context: context(for: KeepAwakePlugin.id)),
            TrackpadPlugin(context: context(for: TrackpadPlugin.id)),
            WindowPreviewPlugin(context: context(for: WindowPreviewPlugin.id)),
            MenuBarOrganizerPlugin(context: context(for: MenuBarOrganizerPlugin.id))
        ]
        #endif
        // IDs are compile-time constants covered by registry tests; never accept downloaded code here.
        return try! PluginRegistry(plugins: builtins, defaults: defaults, report: { [weak self] in self?.message = $0 })
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
        selectedPluginID = MenuBarOrganizerPlugin.id
        #endif
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        if let data = defaults.data(forKey: "app.windowShortcut") ?? defaults.data(forKey: "windowShortcut"),
           let chord = try? JSONDecoder().decode(KeyChord.self, from: data) {
            windowShortcut = chord
            if defaults.data(forKey: "app.windowShortcut") == nil { defaults.set(data, forKey: "app.windowShortcut") }
        }
    }
    private func context(for id: String) -> PluginContext {
        PluginContext(settings: PluginSettings(id: id, defaults: defaults), hotkeys: hotkeys,
                      report: { [weak self] in self?.message = $0 },
                      openToolbox: { [weak self] in
                          self?.selectedPluginID = id
                          self?.showToolbox?()
                      }, setAppearance: { [weak self] in self?.setAppearance($0) })
    }
    func setAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode; defaults.set(mode.rawValue, forKey: "appearanceMode")
        NSApp.appearance = mode.nativeAppearance
    }
    func start() {
        guard !running else { return }; running = true
        NSApp.appearance = appearanceMode.nativeAppearance
        #if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
        if CommandLine.arguments.contains("--ice-candidate-ui-smoke") { return }
        #endif
        registerWindowShortcut(); plugins.startAll()
    }
    func stop() { plugins.stopAll(); hotkeys.remove(owner: "app.window"); running = false }
    func saveWindowShortcut() {
        do {
            defaults.set(try JSONEncoder().encode(windowShortcut), forKey: "app.windowShortcut")
            if running { registerWindowShortcut() }
        } catch { message = "窗口快捷键保存失败：\(error.localizedDescription)" }
    }
    private func registerWindowShortcut() {
        #if ICE_MENU_BAR_CANDIDATE
        return // Keep the installed app's global shortcuts untouched.
        #else
        hotkeys.replace(owner: "app.window", actions: [HotKeyAction(id: "toggle", chord: windowShortcut, perform: { [weak self] in self?.toggleWindow?() })])
        #endif
    }
}
