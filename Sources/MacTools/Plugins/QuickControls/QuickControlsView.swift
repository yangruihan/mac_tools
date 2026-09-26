import SwiftUI

struct PresetRow: View {
    @Binding var preset: Preset
    @ObservedObject var plugin: QuickControlsPlugin

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    TextField("配置名称", text: $preset.name)
                        .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold))
                        .accessibilityLabel("配置名称")
                    Spacer(minLength: 8)
                    Toggle("锁定", isOn: Binding(get: { preset.locked == true }, set: { preset.locked = $0; plugin.save() }))
                        .toggleStyle(.checkbox).controlSize(.small)
                        .help("应用后锁定；修改勾选不影响当前锁定，可用「解除所有锁定」解锁")
                    Button("应用") { plugin.apply(preset) }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { plugin.presets.removeAll { $0.id == preset.id }; plugin.save() } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless).accessibilityLabel("删除配置 \(preset.name)").help("删除此配置")
                }
                HStack(spacing: 12) {
                    Image(systemName: preset.audio ? "speaker.wave.2" : "sun.max").foregroundStyle(.secondary).frame(width: 20)
                    Slider(value: $preset.value, in: 0...100, step: 1)
                        .accessibilityLabel("\(preset.name)\(preset.audio ? "音量" : "亮度")百分比")
                    Text("\(Int(preset.value))%")
                        .font(.system(size: 22, weight: .medium)).monospacedDigit().frame(width: 66, alignment: .trailing)
                }
                HStack(alignment: .top, spacing: 10) {
                    Label("快捷键", systemImage: "keyboard").font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                    ShortcutEditor(shortcut: $preset.shortcut, hotkeys: plugin.context.hotkeys, owner: plugin.info.id, bindingID: preset.id.uuidString, save: plugin.save)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
        }
        .onChange(of: preset.name) { _ in plugin.save() }
        .onChange(of: preset.value) { _ in plugin.save() }
    }
}

struct QuickControlsView: View {
    @ObservedObject var plugin: QuickControlsPlugin
    @State private var confirm = false
    @State private var showShortcut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Toggle("耳机保护 · 音量最高 18%", isOn: Binding(get: { plugin.protection }, set: { value in
                    if value { plugin.protection = true } else { confirm = true }
                })).toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button("解除所有锁定") { plugin.releaseAllLocks() }.disabled(plugin.locks.isEmpty)
                Button { showShortcut.toggle() } label: { Label("解锁快捷键", systemImage: "keyboard") }
                    .popover(isPresented: $showShortcut) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("解除所有锁定快捷键").font(.headline)
                            ShortcutEditor(shortcut: $plugin.unlockShortcut, hotkeys: plugin.context.hotkeys,
                                           owner: plugin.info.id, bindingID: "unlock", save: plugin.saveUnlockShortcut)
                        }.padding(20).frame(width: 360)
                    }
            }
            section("亮度", audio: false)
            section("音频", audio: true)
        }
        .alert("关闭耳机保护？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button("关闭保护", role: .destructive) { plugin.protection = false }
        } message: { Text("关闭后音量最高可设置为 100%。请先确认耳机佩戴和音量。") }
    }
    private func section(_ title: String, audio: Bool) -> some View {
        let count = plugin.presets.filter { $0.audio == audio }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: audio ? "speaker.wave.2.fill" : "sun.max.fill")
                    .foregroundStyle(.secondary).frame(width: 28, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(audio ? "默认输出设备 · \(count) 个配置" : "内置显示器 · \(count) 个配置")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(plugin.locks[audio].map { "已锁定 \(Int($0))%" } ?? "未锁定",
                      systemImage: plugin.locks[audio] == nil ? "lock.open" : "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    plugin.presets.append(Preset(name: audio ? "音量配置" : "亮度配置", audio: audio, value: audio ? 15 : 50))
                    plugin.save()
                } label: { Label("添加配置", systemImage: "plus") }
                .help("添加\(title)配置")
            }
            ForEach($plugin.presets) { $preset in
                if preset.audio == audio { PresetRow(preset: $preset, plugin: plugin) }
            }
            if count == 0 {
                GroupBox {
                    VStack(spacing: 6) {
                        Text("还没有\(title)配置").font(.subheadline.weight(.medium))
                        Text("点击「添加配置」，保存常用档位和快捷键。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
            }
        }
    }
}
