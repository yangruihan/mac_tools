import SwiftUI
import ScreenCaptureKit

final class WindowPreviewPlugin: ObservableObject, ToolPlugin {
    static let id = "window-preview"
    let info = PluginInfo(id: id, title: "窗口悬浮预览", symbol: "pin", detail: "macOS 14+ · 只读置顶预览，可调整大小；需屏幕录制权限", placement: .content)
    private let context: PluginContext
    let preview = FloatingPreview()
    @Published private(set) var windows: [SCWindow] = []
    @Published var selectedID: CGWindowID?
    @Published private(set) var isLoading = false
    @Published private(set) var message = "选择窗口后开始只读悬浮预览，不保存画面、不捕获声音。"
    private var active = false
    private var refreshTask: Task<Void, Never>?
    private var refreshID = UUID()
    private var chooser: NSWindow?

    init(context: PluginContext) { self.context = context }
    func start() {
        active = true
        if let data = context.settings.data(forKey: "frameRate"),
           let value = try? JSONDecoder().decode(Int.self, from: data) { preview.setFrameRate(value) }
    }
    func setFrameRate(_ value: Int) {
        guard FloatingPreview.frameRates.contains(value) else { return }
        preview.setFrameRate(value)
        if let data = try? JSONEncoder().encode(value) { context.settings.set(data, forKey: "frameRate") }
    }
    func stop() {
        active = false; refreshID = UUID()
        refreshTask?.cancel(); refreshTask = nil; isLoading = false
        preview.stop(); windows = []; selectedID = nil
        chooser?.contentView = nil; chooser?.close(); chooser = nil
    }
    deinit { refreshTask?.cancel(); preview.stop() }

    static var supported: Bool { if #available(macOS 14.0, *) { return true }; return false }
    static func label(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "应用"
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(app) — \(title.isEmpty ? "未命名窗口" : title)"
    }

    func requestPermission() {
        guard active else { return }
        guard Self.supported else { message = "此插件需要 macOS 14 或更新版本"; return }
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() { refreshWindows() }
        else { message = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权本应用，再刷新窗口列表；系统可能要求重启应用。" }
    }
    func refreshWindows() {
        guard active else { return }
        guard Self.supported else { message = "此插件需要 macOS 14 或更新版本"; return }
        guard CGPreflightScreenCaptureAccess() else { message = "请先点击「授权屏幕录制」，授权后再刷新。"; return }
        refreshTask?.cancel(); let token = UUID(); refreshID = token; isLoading = true
        refreshTask = Task { @MainActor [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard !Task.isCancelled, let self, self.active, self.refreshID == token else { return }
                self.windows = content.windows.filter {
                    $0.windowLayer == 0 && $0.frame.width > 1 && $0.frame.height > 1
                        && $0.owningApplication != nil && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
                }.sorted { Self.label($0).localizedStandardCompare(Self.label($1)) == .orderedAscending }
                if !self.windows.contains(where: { $0.windowID == self.selectedID }) { self.selectedID = nil }
                self.message = self.windows.isEmpty ? "没有可选窗口，请先打开目标窗口再刷新。" : "请选择要显示的窗口；仅捕获所选窗口，不会捕获整个屏幕。"
                self.isLoading = false; self.refreshTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.refreshID == token else { return }
                self.message = "读取窗口失败：\(error.localizedDescription)"; self.isLoading = false; self.refreshTask = nil
            }
        }
    }

    func beginPreview() {
        guard active, let window = windows.first(where: { $0.windowID == selectedID }) else { return }
        guard #available(macOS 14.0, *) else { return }
        guard CGPreflightScreenCaptureAccess() else { message = "屏幕录制权限不可用，请重新授权。"; return }
        let title = Self.label(window)
        preview.begin(title: title) { try await Self.capture(window) }
        message = "已打开悬浮预览；可拖动边缘缩放，关闭小窗即可停止。"
        context.report(message)
    }

    private enum Visibility { case visible([String: Any]), paused, closed }

    @available(macOS 14.0, *)
    private static func visibility(of window: SCWindow) async throws -> Visibility {
        guard let app = window.owningApplication else { return .closed }
        let records = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID) as? [[String: Any]] ?? []
        if let record = records.first(where: { ( $0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processID }),
           (record[kCGWindowIsOnscreen as String] as? Bool) == true { return .visible(record) }
        // A minimized window disappears from CGWindowList, but remains in ScreenCaptureKit's all-window list.
        let all = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        return all.windows.contains(where: { $0.windowID == window.windowID && $0.owningApplication?.processID == app.processID }) ? .paused : .closed
    }

    @available(macOS 14.0, *)
    static func capture(_ window: SCWindow) async throws -> CGImage {
        let record: [String: Any]
        switch try await visibility(of: window) {
        case .visible(let value): record = value
        case .paused: throw PreviewPaused()
        case .closed: throw Failure.message("源窗口已关闭，请重新选择")
        }
        var size = window.frame.size
        if let bounds = record[kCGWindowBounds as String] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: bounds) { size = rect.size }
        let pixels = FloatingPreview.pixelSize(for: size)
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width); config.height = Int(pixels.height)
        config.showsCursor = false; config.capturesAudio = false
        config.scalesToFit = true; config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        do { return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) }
        catch {
            if case .paused = try await visibility(of: window) { throw PreviewPaused() }
            throw error
        }
    }

    func showChooser() {
        guard active else { return }
        if chooser == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 280), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = info.title; window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 560, height: 250)
            window.contentView = NSHostingView(rootView: WindowPreviewControls(plugin: self, preview: preview).padding(20))
            window.center(); chooser = window
        }
        chooser?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func makeView() -> AnyView { AnyView(WindowPreviewControls(plugin: self, preview: preview)) }
    func makeMenuItems() -> AnyView { AnyView(WindowPreviewMenu(plugin: self, preview: preview)) }
}

private struct WindowPreviewControls: View {
    @ObservedObject var plugin: WindowPreviewPlugin
    @ObservedObject var preview: FloatingPreview
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("窗口悬浮预览", systemImage: "pin").font(.headline)
                Text("只读 · 帧率可选 · 拖动悬浮窗边缘调整大小").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("授权屏幕录制") { plugin.requestPermission() }
                    Button(plugin.isLoading ? "刷新中…" : "刷新窗口列表") { plugin.refreshWindows() }.disabled(plugin.isLoading)
                    Spacer()
                    Button("停止预览") { preview.stop() }.disabled(preview.panel == nil)
                }
                Picker("窗口", selection: $plugin.selectedID) {
                    Text("请选择窗口").tag(Optional<CGWindowID>.none)
                    ForEach(plugin.windows, id: \.windowID) { window in
                        Text(WindowPreviewPlugin.label(window)).tag(Optional(window.windowID))
                    }
                }.frame(maxWidth: .infinity)
                Picker("帧率", selection: Binding(get: { preview.frameRate }, set: { plugin.setFrameRate($0) })) {
                    ForEach(FloatingPreview.frameRates, id: \.self) { rate in
                        Text("\(rate) 帧/秒").tag(rate)
                    }
                }.pickerStyle(.segmented)
                HStack {
                    Text(plugin.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("开始悬浮") { plugin.beginPreview() }.disabled(plugin.selectedID == nil || plugin.isLoading)
                }
                if preview.panel != nil { Text(preview.status).font(.caption).foregroundStyle(.secondary) }
                if !WindowPreviewPlugin.supported { Text("此插件需要 macOS 14+").foregroundStyle(.secondary) }
            }.padding(8)
        }
    }
}
private struct WindowPreviewMenu: View {
    @ObservedObject var plugin: WindowPreviewPlugin
    @ObservedObject var preview: FloatingPreview
    var body: some View {
        Button("选择窗口并悬浮…") { plugin.showChooser() }
        Button("停止窗口预览") { preview.stop() }.disabled(preview.panel == nil)
    }
}
