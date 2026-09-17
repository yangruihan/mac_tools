import SwiftUI
import Carbon
import CoreAudio
import AudioToolbox
import CoreGraphics
import Darwin

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name = "新配置"
    var audio = false
    var value = 15.0
    var locked: Bool? = nil // Missing in older saved presets means unlocked.
    var key = ""
    var modifiers = UInt32(cmdKey | optionKey)
}

let keyCodes: [String: UInt32] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46]
func appliedValue(_ value: Double, audio: Bool, protection: Bool) throws -> Double {
    guard value.isFinite, (0...100).contains(value) else { throw Failure.message("数值必须在 0–100% 之间") }
    return audio && protection ? min(value, 18) : value
}
enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

enum Hardware {
    static func read(audio: Bool) throws -> Double {
        if audio {
            var device = AudioDeviceID(0)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { throw Failure.message("无法读取输出设备") }
            address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value: Float32 = 0
            size = UInt32(MemoryLayout.size(ofValue: value))
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { throw Failure.message("无法读取音量") }
            return Double(value) * 100
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success,
              let display = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { throw Failure.message("无法读取内置屏幕亮度") }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { throw Failure.message("亮度读取接口不可用") }
        typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        var value: Float = 0
        guard unsafeBitCast(symbol, to: Getter.self)(display, &value) == 0 else { throw Failure.message("亮度读取失败") }
        return Double(value) * 100
    }

    static func apply(_ value: Double, audio: Bool) throws {
        if audio {
            var device = AudioDeviceID(0)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { throw Failure.message("找不到默认音频输出设备") }
            address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { throw Failure.message("此输出设备不支持系统音量控制，请使用设备旋钮") }
            var scalar = Float32(value / 100)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: scalar)), &scalar)
            guard status == noErr else { throw Failure.message("音量设置失败：\(status)") }
        } else {
            var displays = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            guard CGGetActiveDisplayList(16, &displays, &count) == .success,
                  let display = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { throw Failure.message("没有内置显示器；暂不支持外接屏亮度") }
            guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { throw Failure.message("系统亮度接口不可用") }
            defer { dlclose(handle) }
            guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { throw Failure.message("系统亮度接口不可用") }
            typealias Setter = @convention(c) (UInt32, Float) -> Int32
            let status = unsafeBitCast(symbol, to: Setter.self)(display, Float(value / 100))
            guard status == 0 else { throw Failure.message("亮度设置失败：\(status)") }
        }
    }
}

final class Store: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var windowShortcut = Preset(name: "显示 / 收起界面", key: "M")
    var toggleWindow: (() -> Void)?
    @Published var protection = true
    @Published var message = "尚未应用配置；耳机保护默认开启"
    @Published var shortcutErrors: [UUID: String] = [:]
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var ids: [UInt32: UUID] = [:]
    @Published private(set) var locks: [Bool: Double] = [:]
    private var lockTimer: Timer?
    private let writeHardware: (Double, Bool) throws -> Void
    private let readHardware: (Bool) throws -> Double
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard,
         writeHardware: @escaping (Double, Bool) throws -> Void = { try Hardware.apply($0, audio: $1) },
         readHardware: @escaping (Bool) throws -> Double = { try Hardware.read(audio: $0) }) {
        self.writeHardware = writeHardware
        self.readHardware = readHardware
        self.defaults = defaults
        if let data = defaults.data(forKey: "presets") {
            do { let loaded = try JSONDecoder().decode([Preset].self, from: data)
                guard Set(loaded.map(\.id)).count == loaded.count, loaded.allSatisfy({ $0.value.isFinite && (0...100).contains($0.value) }) else { throw Failure.message("配置数值或标识无效") }
                presets = loaded }
            catch { message = "配置读取失败，原数据未覆盖：\(error.localizedDescription)" }
        }
        if let data = defaults.data(forKey: "windowShortcut"),
           let shortcut = try? JSONDecoder().decode(Preset.self, from: data) { windowShortcut = shortcut }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr else { return status }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            if let id = store.ids[key.id] {
                if id == store.windowShortcut.id { store.toggleWindow?() }
                else if let preset = store.presets.first(where: { $0.id == id }) { store.apply(preset) }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register()
    }
    deinit {
        lockTimer?.invalidate()
        references.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
    func save() {
        do { defaults.set(try JSONEncoder().encode(presets), forKey: "presets"); register() }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }
    func saveWindowShortcut() {
        do { defaults.set(try JSONEncoder().encode(windowShortcut), forKey: "windowShortcut"); register() }
        catch { message = "快捷键保存失败：\(error.localizedDescription)" }
    }
    func register() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll(); ids.removeAll(); shortcutErrors.removeAll()
        for (index, preset) in ([windowShortcut] + presets).enumerated() where !preset.key.isEmpty {
            guard let code = keyCodes[preset.key.uppercased()], preset.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
                shortcutErrors[preset.id] = "请选择字母/数字，至少包含 ⌘、⌥ 或 ⌃"; continue
            }
            var reference: EventHotKeyRef?
            let id = UInt32(index + 1)
            let status = RegisterEventHotKey(code, preset.modifiers, EventHotKeyID(signature: 0x4D54424F, id: id), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference); ids[id] = preset.id }
            else { shortcutErrors[preset.id] = "快捷键冲突或注册失败（\(status)）" }
        }
    }
    private func updateLockTimer() {
        guard !locks.isEmpty else { lockTimer?.invalidate(); lockTimer = nil; return }
        guard lockTimer == nil else { return }
        // ponytail: 200ms reconciliation can briefly expose system changes; device notifications if latency matters.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.enforceLocks() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        lockTimer = timer
    }
    func enforceLocks() {
        for (audio, lockedValue) in locks {
            do {
                let value = try appliedValue(lockedValue, audio: audio, protection: protection)
                if abs(try readHardware(audio) - value) > 0.1 { try writeHardware(value, audio) }
            } catch { message = "锁定恢复失败（仍保留锁定，请切换未锁定配置）：\(error.localizedDescription)" }
        }
    }
    func apply(_ preset: Preset) {
        do {
            let value = try appliedValue(preset.value, audio: preset.audio, protection: protection)
            if preset.locked == true { _ = try readHardware(preset.audio) }
            try writeHardware(value, preset.audio)
            locks[preset.audio] = preset.locked == true ? value : nil
            updateLockTimer()
            message = "已设置\(preset.audio ? "音量" : "亮度")：\(Int(value))%" + (value != preset.value ? "（耳机保护限制）" : "")
        } catch { message = error.localizedDescription }
    }
}

struct PresetRow: View {
    @Binding var preset: Preset
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("配置名称", text: $preset.name).frame(width: 130)
                Slider(value: $preset.value, in: 0...100, step: 1)
                Text("\(Int(preset.value))%").monospacedDigit().frame(width: 42)
                Toggle("锁定", isOn: Binding(get: { preset.locked == true }, set: { preset.locked = $0; store.save() }))
                    .help("应用后锁定；编辑或删除配置不会解除，需应用同类未锁定配置")
                Button("应用") { store.apply(preset) }
                Button(role: .destructive) { store.presets.removeAll { $0.id == preset.id }; store.save() } label: { Image(systemName: "trash") }.accessibilityLabel("删除配置")
            }
            HStack {
                Text("快捷键").foregroundStyle(.secondary)
                ForEach([("⌘", UInt32(cmdKey)), ("⌥", UInt32(optionKey)), ("⌃", UInt32(controlKey)), ("⇧", UInt32(shiftKey))], id: \.1) { label, flag in
                    Toggle(label, isOn: Binding(get: { preset.modifiers & flag != 0 }, set: { on in
                        if on { preset.modifiers |= flag } else { preset.modifiers &= ~flag }
                    })).toggleStyle(.button)
                }
                Picker("按键", selection: $preset.key) {
                    Text("不设置").tag("")
                    ForEach(keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 135)
                if let error = store.shortcutErrors[preset.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding(.vertical, 6)
        .onChange(of: preset.name) { _ in store.save() }
        .onChange(of: preset.value) { _ in store.save() }
        .onChange(of: preset.key) { _ in store.save() }
        .onChange(of: preset.modifiers) { _ in store.save() }
    }
}
struct ContentView: View {
    @ObservedObject var store: Store
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷控制").font(.largeTitle.bold())
            Text("配置自动保存 · 快捷键在应用运行时全局生效").foregroundStyle(.secondary)
            GroupBox("显示界面 / 收起到托盘") {
                HStack {
                    ForEach([("⌘", UInt32(cmdKey)), ("⌥", UInt32(optionKey)), ("⌃", UInt32(controlKey)), ("⇧", UInt32(shiftKey))], id: \.1) { label, flag in
                        Toggle(label, isOn: Binding(get: { store.windowShortcut.modifiers & flag != 0 }, set: { on in
                            if on { store.windowShortcut.modifiers |= flag } else { store.windowShortcut.modifiers &= ~flag }
                            store.saveWindowShortcut()
                        })).toggleStyle(.button)
                    }
                    Picker("按键", selection: $store.windowShortcut.key) {
                        Text("不设置").tag("")
                        ForEach(keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 135)
                    .onChange(of: store.windowShortcut.key) { _ in store.saveWindowShortcut() }
                    Button("收起到托盘") { store.toggleWindow?() }
                    if let error = store.shortcutErrors[store.windowShortcut.id] { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(6)
            }
            Toggle("耳机保护：音量最高 18%（重启自动开启）", isOn: Binding(get: { store.protection }, set: { value in
                if value { store.protection = true } else { confirm = true }
            }))
            ScrollView {
                VStack(spacing: 20) {
                    section("亮度", audio: false)
                    section("音频", audio: true)
                }
            }
            Text("亮度：\(store.locks[false].map { "已锁定 \(Int($0))%" } ?? "未锁定") · 音量：\(store.locks[true].map { "已锁定 \(Int($0))%" } ?? "未锁定")").font(.caption)
            Text(store.message).font(.callout).textSelection(.enabled)
            Text("亮度仅支持内置屏幕；关闭窗口后可通过菜单栏重新打开。退出后快捷键失效。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 740, minHeight: 500)
        .alert("关闭耳机保护？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button("关闭保护", role: .destructive) { store.protection = false }
        } message: { Text("关闭后音量配置最高可设置为 100%。请先确认耳机佩戴和音量。") }
    }
    func section(_ title: String, audio: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading) {
                HStack {
                    Label(title, systemImage: audio ? "speaker.wave.2" : "sun.max").font(.headline)
                    Spacer()
                    Button("添加配置", systemImage: "plus") {
                        store.presets.append(Preset(name: audio ? "音量配置" : "亮度配置", audio: audio, value: audio ? 15 : 50)); store.save()
                    }
                }
                ForEach($store.presets) { $preset in
                    if preset.audio == audio { PresetRow(preset: $preset, store: store) }
                }
                if !store.presets.contains(where: { $0.audio == audio }) { Text("添加一个配置，然后选择百分比和快捷键。").foregroundStyle(.secondary).padding(.vertical) }
            }.padding(8)
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.toggleWindow = { [weak self] in self?.toggleWindow() }
        showWindow(store: store)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func toggleWindow() {
        if let window, window.isVisible && !window.isMiniaturized && NSApp.isActive { window.orderOut(nil) }
        else { showWindow(store: store) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(store: store)
        return true
    }

    func showWindow(store: Store) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Mac 工具箱"
            panel.contentView = NSHostingView(rootView: ContentView(store: store))
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Mac 工具箱", systemImage: "slider.horizontal.3") { MenuContent(store: delegate.store, showWindow: { delegate.showWindow(store: delegate.store) }) }
    }
}
struct MenuContent: View {
    @ObservedObject var store: Store
    let showWindow: () -> Void
    var body: some View {
        Button("打开工具箱", action: showWindow)
        Text(store.protection ? "耳机保护：开启（最高 18%）" : "耳机保护：已关闭")
        ForEach(store.presets) { preset in Button("\(preset.audio ? "音量" : "亮度") · \(preset.name) · \(Int(preset.value))%") { store.apply(preset) } }
        Divider()
        Text(store.message)
        Button("退出") { NSApp.terminate(nil) }
    }
}
