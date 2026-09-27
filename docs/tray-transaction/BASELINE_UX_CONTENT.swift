import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var registry: PluginRegistry
    @State private var showShortcuts = false
    init(model: AppModel) { self.model = model; self.registry = model.plugins }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 25)).foregroundStyle(.secondary).frame(width: 38, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac 工具箱").font(.system(size: 22, weight: .semibold))
                    Text("\(registry.enabledPlugins.count) 个插件已启用").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PluginMenu(registry: registry).fixedSize()
                Picker("外观", selection: Binding(get: { model.appearanceMode }, set: model.setAppearance)) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).frame(width: 142)
                Button { showShortcuts.toggle() } label: { Label("窗口快捷键", systemImage: "keyboard") }
                    .popover(isPresented: $showShortcuts) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("显示界面 / 收起到托盘").font(.headline)
                            ShortcutEditor(shortcut: $model.windowShortcut, hotkeys: model.hotkeys, owner: "app.window", bindingID: "toggle", save: model.saveWindowShortcut)
                            Text("各工具的快捷键在对应插件内设置。").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).frame(width: 360)
                    }
                Button { model.toggleWindow?() } label: { Image(systemName: "rectangle.compress.vertical") }
                    .accessibilityLabel("收起到托盘")
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if registry.enabledPlugins.contains(where: { $0.info.placement == .utility }) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], spacing: 12) {
                            ForEach(registry.enabledPlugins.filter { $0.info.placement == .utility }, id: \.info.id) { $0.makeView() }
                        }
                    }
                    ForEach(registry.enabledPlugins.filter { $0.info.placement == .content }, id: \.info.id) { $0.makeView() }
                    if !registry.enabledPlugins.contains(where: { $0.info.placement == .content }) {
                        Text("暂无启用的工具面板，可在「插件」菜单中启用。").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(32)
                    }
                }.padding(24)
            }.frame(maxWidth: .infinity, minHeight: 350, maxHeight: .infinity)
                .accessibilityIdentifier("preset-list").layoutPriority(1)
            Divider()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(model.message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Text("配置自动保存").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(minWidth: 900, minHeight: 640).background(Color(nsColor: .windowBackgroundColor))
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
