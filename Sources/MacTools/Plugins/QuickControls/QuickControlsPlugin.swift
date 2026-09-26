import SwiftUI
import Carbon

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name = "新配置"
    var audio = false
    var value = 15.0
    var locked: Bool? = nil // Missing in older saved presets means unlocked.
    var key = ""
    var modifiers = UInt32(cmdKey | optionKey)
    var shortcut: KeyChord {
        get { KeyChord(key: key, modifiers: modifiers) }
        set { key = newValue.key; modifiers = newValue.modifiers }
    }
}

func appliedValue(_ value: Double, audio: Bool, protection: Bool) throws -> Double {
    guard value.isFinite, (0...100).contains(value) else { throw Failure.message("数值必须在 0–100% 之间") }
    return audio && protection ? min(value, 18) : value
}

final class QuickControlsPlugin: ObservableObject, ToolPlugin {
    static let id = "quick-controls"
    let info = PluginInfo(id: id, title: "快捷控制", symbol: "slider.horizontal.3", detail: "亮度、音量、配置快捷键与锁定", placement: .content)
    let context: PluginContext
    @Published var presets: [Preset] = []
    @Published var unlockShortcut = KeyChord()
    @Published var protection = true
    @Published private(set) var locks: [Bool: Double] = [:]
    private(set) var active = false
    private var lockTimer: Timer?
    private let writeHardware: (Double, Bool) throws -> Void
    private let readHardware: (Bool) throws -> Double

    init(context: PluginContext,
         writeHardware: @escaping (Double, Bool) throws -> Void = { try Hardware.apply($0, audio: $1) },
         readHardware: @escaping (Bool) throws -> Double = { try Hardware.read(audio: $0) }) {
        self.context = context; self.writeHardware = writeHardware; self.readHardware = readHardware
        context.settings.migrateLegacyData(["presets", "unlockShortcut"])
        if let data = context.settings.data(forKey: "presets") {
            do {
                let loaded = try JSONDecoder().decode([Preset].self, from: data)
                guard Set(loaded.map(\.id)).count == loaded.count, loaded.allSatisfy({ $0.value.isFinite && (0...100).contains($0.value) }) else { throw Failure.message("配置数值或标识无效") }
                presets = loaded
            } catch { context.report("配置读取失败，原数据未覆盖：\(error.localizedDescription)") }
        }
        if let data = context.settings.data(forKey: "unlockShortcut"), let chord = try? JSONDecoder().decode(KeyChord.self, from: data) { unlockShortcut = chord }
    }

    func start() { guard !active else { return }; active = true; register() }
    func stop() {
        active = false
        locks.removeAll(); lockTimer?.invalidate(); lockTimer = nil
        context.hotkeys.remove(owner: info.id)
    }
    deinit { lockTimer?.invalidate(); context.hotkeys.remove(owner: info.id) }

    func save() {
        do { context.settings.set(try JSONEncoder().encode(presets), forKey: "presets"); register() }
        catch { context.report("配置保存失败：\(error.localizedDescription)") }
    }
    func saveUnlockShortcut() {
        do { context.settings.set(try JSONEncoder().encode(unlockShortcut), forKey: "unlockShortcut"); register() }
        catch { context.report("解锁快捷键保存失败：\(error.localizedDescription)") }
    }
    private func register() {
        guard active else { return }
        let actions = [HotKeyAction(id: "unlock", chord: unlockShortcut, perform: { [weak self] in self?.releaseAllLocks() })]
            + presets.map { preset in HotKeyAction(id: preset.id.uuidString, chord: preset.shortcut, perform: { [weak self] in self?.apply(preset) }) }
        context.hotkeys.replace(owner: info.id, actions: actions)
    }
    private func updateLockTimer() {
        guard !locks.isEmpty else { lockTimer?.invalidate(); lockTimer = nil; return }
        guard lockTimer == nil else { return }
        // ponytail: 200ms reconciliation can briefly expose system changes; notifications if latency matters.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.enforceLocks() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common); lockTimer = timer
    }
    func releaseAllLocks() {
        locks.removeAll(); updateLockTimer()
        context.report("已解除全部亮度和音量锁定；当前数值未改变")
    }
    func enforceLocks() {
        guard active else { return }
        for (audio, lockedValue) in locks {
            do {
                let value = try appliedValue(lockedValue, audio: audio, protection: protection)
                if abs(try readHardware(audio) - value) > 0.1 { try writeHardware(value, audio) }
            } catch { context.report("锁定恢复失败（仍保留锁定，请切换未锁定配置）：\(error.localizedDescription)") }
        }
    }
    func apply(_ preset: Preset) {
        guard active else { return }
        do {
            let value = try appliedValue(preset.value, audio: preset.audio, protection: protection)
            if preset.locked == true { _ = try readHardware(preset.audio) }
            try writeHardware(value, preset.audio)
            locks[preset.audio] = preset.locked == true ? value : nil
            updateLockTimer()
            context.report("已设置\(preset.audio ? "音量" : "亮度")：\(Int(value))%" + (value != preset.value ? "（耳机保护限制）" : ""))
        } catch { context.report(error.localizedDescription) }
    }
    func makeView() -> AnyView { AnyView(QuickControlsView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(QuickControlsMenu(plugin: self)) }
}

struct QuickControlsMenu: View {
    @ObservedObject var plugin: QuickControlsPlugin
    var body: some View {
        Button("解除所有锁定") { plugin.releaseAllLocks() }.disabled(plugin.locks.isEmpty)
        Text(plugin.protection ? "耳机保护：开启（最高 18%）" : "耳机保护：已关闭")
        ForEach(plugin.presets) { preset in
            Button("\(preset.audio ? "音量" : "亮度") · \(preset.name) · \(Int(preset.value))%") { plugin.apply(preset) }
        }
    }
}
