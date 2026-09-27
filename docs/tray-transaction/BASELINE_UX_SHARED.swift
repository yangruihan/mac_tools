import SwiftUI
import Carbon

struct ShortcutEditor: View {
    @Binding var shortcut: KeyChord
    @ObservedObject var hotkeys: HotKeyService
    let owner: String
    let bindingID: String
    var save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach([("⌘", "Command", UInt32(cmdKey)), ("⌥", "Option", UInt32(optionKey)),
                         ("⌃", "Control", UInt32(controlKey)), ("⇧", "Shift", UInt32(shiftKey))], id: \.2) { symbol, name, flag in
                    Toggle(symbol, isOn: Binding(get: { shortcut.modifiers & flag != 0 }, set: { on in
                        if on { shortcut.modifiers |= flag } else { shortcut.modifiers &= ~flag }
                        save()
                    }))
                    .toggleStyle(.button)
                    .accessibilityLabel(name)
                    .help(name)
                }
                Picker("按键", selection: $shortcut.key) {
                    Text("不设置").tag("")
                    ForEach(keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 94)
                .onChange(of: shortcut.key) { _ in save() }
            }.controlSize(.small)
            if let error = hotkeys.error(owner: owner, id: bindingID) { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct NativeToggleCard: View {
    let title: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool
    var body: some View {
        GroupBox {
            Toggle(isOn: $isOn) {
                HStack(spacing: 9) {
                    Image(systemName: icon).foregroundStyle(.secondary).font(.title3).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 12, weight: .semibold))
                        Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }.toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
                .padding(6).frame(maxWidth: .infinity)
        }
    }
}
