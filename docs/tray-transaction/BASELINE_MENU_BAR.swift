import SwiftUI
import Carbon
import ScreenCaptureKit

struct ShelfIcon: Identifiable {
    let id: CGWindowID
    let frame: CGRect
    let image: CGImage
}

final class MenuBarOrganizerPlugin: NSObject, ObservableObject, ToolPlugin {
    static let id = "menu-bar-organizer"
    let info = PluginInfo(id: id, title: "菜单栏收纳", symbol: "rectangle.3.group", detail: "按 ⌘ 拖动图标跨分隔符；点击收纳图标打开第二排", placement: .content)
    @Published private(set) var isOrganizing = false
    @Published private(set) var isCollapsed = false
    @Published private(set) var icons: [ShelfIcon] = []
    @Published private(set) var status = "默认关闭；启用后把要收起的原生图标 ⌘-拖到分隔符左侧。"
    private let context: PluginContext
    private var active = false
    private var control: NSStatusItem?
    private var divider: NSStatusItem?
    private var shelfPanel: NSPanel?
    private var work: Task<Void, Never>?
    private var displayObserver: NSObjectProtocol?
    private var token = UUID()

    init(context: PluginContext) { self.context = context; super.init() }
    func start() {
        active = true
        if let data = context.settings.data(forKey: "optedIn"), (try? JSONDecoder().decode(Bool.self, from: data)) == true { enable() }
    }
    func stop() { work?.cancel(); work = nil; token = UUID(); deactivate(); active = false }
    deinit {
        work?.cancel()
        // AppKit resources are also released from stop() on normal shutdown.
        if let control { NSStatusBar.system.removeStatusItem(control) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
    }
    private func saveOptIn(_ value: Bool) {
        if let data = try? JSONEncoder().encode(value) { context.settings.set(data, forKey: "optedIn") }
    }
    func enable() {
        guard active, !isOrganizing else { return }
        guard #available(macOS 14, *) else { status = "此插件需要 macOS 14 或更新版本"; return }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 else {
            status = "macOS 27 已改用系统菜单栏溢出菜单，此手动分隔符模式不适用"; return
        }
        // New items enter on the left: create the reachable control first, then its divider.
        let control = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        control.autosaveName = "mactools_shelf_control"
        control.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "显示隐藏的菜单栏图标")
        control.button?.target = self; control.button?.action = #selector(controlClicked)
        let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = "mactools_shelf_divider"
        divider.button?.title = "│"; divider.button?.toolTip = "按住 ⌘，将原生菜单栏图标拖到分隔符左右两侧"
        self.control = control; self.divider = divider; isOrganizing = true
        context.hotkeys.replace(owner: info.id, actions: [HotKeyAction(id: "emergency-reveal",
            chord: KeyChord(key: "R", modifiers: UInt32(controlKey | optionKey | cmdKey)),
            perform: { [weak self] in self?.expand() })])
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in self?.expand() }
        status = "已启用。请将收纳按钮留在分隔符右侧，再用 ⌘ 拖动需要收纳的图标。"
        saveOptIn(true)
    }
    func deactivate() {
        expand(); closePanel(); context.hotkeys.remove(owner: info.id)
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        if let control { NSStatusBar.system.removeStatusItem(control) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        control = nil; divider = nil; isOrganizing = false; icons = []
    }
    func turnOff() { saveOptIn(false); deactivate(); status = "菜单栏收纳已关闭；原生图标已展开。" }

    static func canCollapse(dividerX: CGFloat, controlX: CGFloat, screen: CGRect) -> Bool {
        dividerX >= screen.minX && controlX <= screen.maxX && dividerX + 8 < controlX
    }
    static func hiddenWindows(_ windows: [(id: CGWindowID, frame: CGRect)], leftOf dividerX: CGFloat,
                              in screen: CGRect, statusBarY: CGFloat) -> [(id: CGWindowID, frame: CGRect)] {
        windows.filter { $0.frame.width > 8 && $0.frame.width < 150 && $0.frame.minX >= screen.minX
            && $0.frame.maxX <= dividerX + 1 && screen.minX <= $0.frame.midX && $0.frame.midX <= screen.maxX
            && abs($0.frame.minY - statusBarY) < 48 }
            .sorted { $0.frame.minX < $1.frame.minX }
    }
    private func statusWindows() -> [(id: CGWindowID, frame: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { item in
            guard (item[kCGWindowLayer as String] as? Int) == level,
                  let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (id, frame)
        }
    }
    private func screen(for frame: CGRect) -> CGRect? {
        NSScreen.screens.map(\.frame).first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }
    private func placement() -> (divider: CGRect, control: CGRect, screen: CGRect)? {
        guard let dividerFrame = divider?.button?.window?.frame,
              let controlFrame = control?.button?.window?.frame,
              let screen = screen(for: controlFrame) else { return nil }
        return (dividerFrame, controlFrame, screen)
    }
    @objc private func controlClicked() {
        if isCollapsed { shelfPanel?.isVisible == true ? closePanel() : showCachedPanel() }
        else { hideIntoPanel() }
    }
    func expand() {
        work?.cancel(); work = nil; token = UUID(); closePanel()
        divider?.length = NSStatusItem.variableLength
        isCollapsed = false
    }
    private func closePanel() { shelfPanel?.contentView = nil; shelfPanel?.close(); shelfPanel = nil }
    func requestPermission() {
        guard active else { return }
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() { status = "已授权，点击收纳图标打开第二排。" }
        else { status = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权本应用，然后重启。" }
    }
    func hideIntoPanel() {
        guard isOrganizing, !isCollapsed else { return }
        guard CGPreflightScreenCaptureAccess() else { status = "先点击「授权屏幕录制」；未授权时不会隐藏任何图标。"; return }
        if let error = context.hotkeys.error(owner: info.id, id: "emergency-reveal") {
            status = "紧急展开快捷键不可用（\(error)），不会隐藏图标；请解除冲突后重试。"; return
        }
        guard let geometry = placement(), Self.canCollapse(dividerX: geometry.divider.minX, controlX: geometry.control.minX, screen: geometry.screen) else {
            status = "收纳按钮必须在分隔符右侧且可见；请按住 ⌘ 拖动两者后重试。"; return
        }
        let separatorX = geometry.divider.minX
        let menuY = (NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY) - geometry.screen.maxY
        let targets = Self.hiddenWindows(statusWindows(), leftOf: separatorX, in: geometry.screen, statusBarY: menuY)
        guard !targets.isEmpty else { status = "分隔符左侧尚无可收纳图标；先按住 ⌘ 拖动图标。"; return }
        work?.cancel(); let id = UUID(); token = id
        status = "正在读取 \(targets.count) 个图标…"
        work = Task { @MainActor [weak self] in
            guard #available(macOS 14, *) else { return }
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                var captured: [ShelfIcon] = []
                for target in targets {
                    try Task.checkCancellation()
                    guard let window = shareable.windows.first(where: { $0.windowID == target.id }) else { throw Failure.message("有图标无法读取，本次不隐藏") }
                    let config = SCStreamConfiguration()
                    config.width = max(16, Int(target.frame.width * 2)); config.height = max(16, Int(target.frame.height * 2))
                    config.showsCursor = false; config.capturesAudio = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                    captured.append(ShelfIcon(id: target.id, frame: target.frame, image: image))
                }
                guard !Task.isCancelled, let self, self.token == id, self.isOrganizing else { return }
                guard let latest = self.placement(), Self.canCollapse(dividerX: latest.divider.minX, controlX: latest.control.minX, screen: latest.screen),
                      Self.hiddenWindows(self.statusWindows(), leftOf: latest.divider.minX, in: latest.screen, statusBarY: menuY).map(\.id) == targets.map(\.id) else {
                    self.status = "采集期间图标顺序发生变化，保持展开；请重试。"; return
                }
                self.icons = captured
                self.divider?.length = 10_000
                // Check after reflow; never leave the recovery control hidden.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.token == id else { return }
                    guard let now = self.placement(), now.control.minX >= now.screen.minX,
                          now.control.maxX <= now.screen.maxX else {
                        self.expand(); self.status = "收纳按钮会被一起隐藏，已自动撤销。请 ⌘-拖动按钮到分隔符右侧。"; return
                    }
                    self.isCollapsed = true; self.status = "已收纳 \(captured.count) 个图标；展开后按住 ⌘ 可重新排列。"
                    self.showCachedPanel()
                }
            } catch {
                guard !Task.isCancelled, let self, self.token == id else { return }
                self.expand(); self.status = "读取图标失败，保持原样：\(error.localizedDescription)"
            }
        }
    }
    private func showCachedPanel() {
        guard isCollapsed, let geometry = placement(), !icons.isEmpty else { return }
        closePanel()
        let view = NSHostingView(rootView: ShelfPanelView(icons: icons, onExpand: { [weak self] in self?.expand() }))
        let width = min(geometry.screen.width - 24, CGFloat(icons.count) * 34 + 32)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: max(250, width), height: 100),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "收纳的菜单栏图标"
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.contentView = view
        let x = max(geometry.screen.minX, min(geometry.control.maxX - panel.frame.width, geometry.screen.maxX - panel.frame.width))
        panel.setFrameOrigin(CGPoint(x: x, y: geometry.control.minY - panel.frame.height - 5))
        panel.orderFrontRegardless(); shelfPanel = panel
    }
    func makeView() -> AnyView { AnyView(MenuBarOrganizerView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(MenuBarOrganizerMenu(plugin: self)) }
}

private struct ShelfPanelView: View {
    let icons: [ShelfIcon]
    let onExpand: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(icons) { icon in
                        Image(decorative: icon.image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 24).accessibilityLabel("已收纳的菜单栏图标")
                    }
                }
            }
            Button("展开菜单栏 · 按住 ⌘ 拖动图标") { onExpand() }
                .font(.caption)
        }.padding(10)
    }
}
private struct MenuBarOrganizerView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(plugin.info.title, systemImage: plugin.info.symbol).font(.headline)
                Text("一个控制图标和一个分隔符；⌘-拖动原生图标到分隔符左侧即纳入，右侧即移出。收纳按钮必须留在右侧。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if plugin.isOrganizing {
                        Button("关闭收纳功能") { plugin.turnOff() }
                        Button("展开并排列") { plugin.expand() }
                        Button("收进弹框") { plugin.hideIntoPanel() }.disabled(plugin.isCollapsed)
                    } else { Button("启用收纳图标") { plugin.enable() } }
                    Button("授权屏幕录制") { plugin.requestPermission() }.disabled(!plugin.isOrganizing)
                }
                Text(plugin.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("紧急展开快捷键 ⌃⌥⌘R；必须先授权屏幕录制才能收起。").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
}
private struct MenuBarOrganizerMenu: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        Button(plugin.isOrganizing ? "关闭菜单栏收纳" : "启用菜单栏收纳") { plugin.isOrganizing ? plugin.turnOff() : plugin.enable() }
        if plugin.isOrganizing {
            Button("展开并排列") { plugin.expand() }
            Button("收进弹框") { plugin.hideIntoPanel() }.disabled(plugin.isCollapsed)
        }
    }
}
