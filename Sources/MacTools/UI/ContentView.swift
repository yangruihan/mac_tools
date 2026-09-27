import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var registry: PluginRegistry
    @State private var showShortcuts = false
    @State private var selectedPluginID: String? = QuickControlsPlugin.id
    init(model: AppModel) { self.model = model; self.registry = model.plugins }

    private var selectedPlugin: (any ToolPlugin)? {
        registry.enabledPlugins.first(where: { $0.info.id == selectedPluginID }) ?? registry.enabledPlugins.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label("Mac 工具箱", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
                Text("工具")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.bottom, 6)
                List(selection: $selectedPluginID) {
                    ForEach(registry.enabledPlugins, id: \.info.id) { plugin in
                        Label(plugin.info.title, systemImage: plugin.info.symbol)
                            .tag(plugin.info.id)
                    }
                }.listStyle(.sidebar)
                Text("\(registry.enabledPlugins.count) 个工具已启用")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(16)
            }
            .frame(width: 208)
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPlugin?.info.title ?? "工具箱")
                            .font(.system(size: 23, weight: .semibold))
                        Text(selectedPlugin?.info.detail ?? "在左侧选择工具")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    PluginMenu(registry: registry).fixedSize()
                    Picker("外观", selection: Binding(get: { model.appearanceMode }, set: model.setAppearance)) {
                        ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).frame(width: 126)
                    Button { showShortcuts.toggle() } label: { Image(systemName: "keyboard") }
                        .help("窗口快捷键").accessibilityLabel("窗口快捷键")
                        .popover(isPresented: $showShortcuts) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("显示界面 / 收起到托盘").font(.headline)
                                ShortcutEditor(shortcut: $model.windowShortcut, hotkeys: model.hotkeys, owner: "app.window", bindingID: "toggle", save: model.saveWindowShortcut)
                                Text("各工具的快捷键在对应页面设置。").font(.caption).foregroundStyle(.secondary)
                            }.padding(20).frame(width: 360)
                        }
                    Button { model.toggleWindow?() } label: { Image(systemName: "rectangle.compress.vertical") }
                        .help("收起到托盘").accessibilityLabel("收起到托盘")
                }.padding(.horizontal, 22).padding(.vertical, 16)
                Divider()
                ScrollView {
                    if let selectedPlugin {
                        selectedPlugin.makeView()
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(22)
                    } else {
                        Text("暂无启用的工具，可在「插件」中启用。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(32)
                    }
                }.frame(maxWidth: .infinity, minHeight: 350, maxHeight: .infinity)
                    .accessibilityIdentifier("preset-list").layoutPriority(1)
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(model.message).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text("自动保存").foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal, 22).padding(.vertical, 10)
            }
        }.frame(minWidth: 900, minHeight: 640).background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: registry.enabledIDs) { ids in
                if let selectedPluginID, !ids.contains(selectedPluginID) {
                    self.selectedPluginID = registry.enabledPlugins.first?.info.id
                }
            }
    }
}

struct PluginMenu: View {
    @ObservedObject var registry: PluginRegistry
    var body: some View {
        Menu {
            ForEach(registry.plugins, id: \.info.id) { plugin in
                Toggle(plugin.info.title, isOn: Binding(get: { registry.enabledIDs.contains(plugin.info.id) }, set: { registry.setEnabled($0, id: plugin.info.id) }))
                    .help(plugin.info.detail)
            }
        } label: { Label("插件", systemImage: "puzzlepiece.extension") }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var registry: PluginRegistry
    let showWindow: () -> Void
    init(model: AppModel, showWindow: @escaping () -> Void) { self.model = model; registry = model.plugins; self.showWindow = showWindow }
    var body: some View {
        Button("打开工具箱", action: showWindow)
        Picker("外观", selection: Binding(get: { model.appearanceMode }, set: model.setAppearance)) {
            ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu)
        PluginMenu(registry: registry)
        ForEach(registry.enabledPlugins, id: \.info.id) { plugin in
            Divider()
            plugin.makeMenuItems()
        }
        Divider()
        Text(model.message)
        Button("退出") { NSApp.terminate(nil) }
    }
}
