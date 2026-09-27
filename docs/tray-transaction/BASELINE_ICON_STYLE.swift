import SwiftUI
import Carbon
import ScreenCaptureKit
import ApplicationServices
import UniformTypeIdentifiers

struct ShelfIcon: Identifiable {
    let id: CGWindowID
    let frame: CGRect
    let image: CGImage
}

final class MenuBarOrganizerPlugin: NSObject, ObservableObject, ToolPlugin {
    static let id = "menu-bar-organizer"
    private static let controlName = "mactools_shelf_control"
    private static let dividerName = "mactools_shelf_divider"
    private static let mainPositionKey = "NSStatusItem Preferred Position Item-0"
    private static let priorMainPositionKey = "plugin.menu-bar-organizer.priorMainPosition"
    private static let pinnedMainPosition = 200.0
    let info = PluginInfo(id: id, title: "菜单栏收纳", symbol: "rectangle.3.group", detail: "按 ⌘ 拖动图标跨分隔符；点击收纳图标打开第二排", placement: .content)
    @Published private(set) var isOrganizing = false
    @Published private(set) var isCollapsed = false
    @Published private(set) var icons: [ShelfIcon] = []
    @Published private(set) var visibleIcons: [ShelfIcon] = []
    @Published var visibleLimit = 6
    @Published private(set) var status = "默认关闭；启用后把要收起的原生图标 ⌘-拖到分隔符左侧。"
    private let context: PluginContext
    private var active = false
    private var control: NSStatusItem?
    private var divider: NSStatusItem?
    private var shelfPanel: NSPanel?
    private var work: Task<Void, Never>?
    private var displayObserver: NSObjectProtocol?
    private var token = UUID()
    private var moving = false

    static func prepareMainStatusPosition(defaults: UserDefaults = .standard) {
        let optedIn = defaults.data(forKey: "plugin.menu-bar-organizer.optedIn")
            .flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } == true
        let position = defaults.object(forKey: mainPositionKey) as? Double
        if optedIn {
            if defaults.object(forKey: priorMainPositionKey) != nil {
                if position == 450 { defaults.set(pinnedMainPosition, forKey: mainPositionKey) }
            } else if position.map({ $0 > 250 }) ?? true {
                defaults.set(position ?? -1, forKey: priorMainPositionKey)
                defaults.set(pinnedMainPosition, forKey: mainPositionKey)
            }
        } else if let prior = defaults.object(forKey: priorMainPositionKey) as? Double {
            if position == pinnedMainPosition || position == 450 {
                if prior >= 0 { defaults.set(prior, forKey: mainPositionKey) }
                else { defaults.removeObject(forKey: mainPositionKey) }
            }
            defaults.removeObject(forKey: priorMainPositionKey)
        }
    }

    init(context: PluginContext) { self.context = context; super.init() }
    func start() {
        active = true
        if let data = context.settings.data(forKey: "visibleLimit"), let value = try? JSONDecoder().decode(Int.self, from: data) {
            visibleLimit = min(30, max(1, value))
        }
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
        // A full bar parks new items under app menus; seed visible, ordered slots before creation.
        let defaults = UserDefaults.standard
        let controlPositionKey = "NSStatusItem Preferred Position \(Self.controlName)"
        let dividerPositionKey = "NSStatusItem Preferred Position \(Self.dividerName)"
        if !Self.sanePositions(control: defaults.object(forKey: controlPositionKey) as? Double,
                               divider: defaults.object(forKey: dividerPositionKey) as? Double) {
            defaults.set(250.0, forKey: controlPositionKey)
            defaults.set(290.0, forKey: dividerPositionKey)
        }
        let control = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        control.autosaveName = Self.controlName
        control.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "显示隐藏的菜单栏图标")
        control.button?.target = self; control.button?.action = #selector(controlClicked)
        let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = Self.dividerName
        divider.button?.title = "│"; divider.button?.toolTip = "按住 ⌘，将原生菜单栏图标拖到分隔符左右两侧"
        self.control = control; self.divider = divider; isOrganizing = true
        context.hotkeys.replace(owner: info.id, actions: [HotKeyAction(id: "emergency-reveal",
            chord: KeyChord(key: "R", modifiers: UInt32(controlKey | optionKey | cmdKey)),
            perform: { [weak self] in self?.expand() })])
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in self?.expand() }
        status = "已启用。请将收纳按钮留在分隔符右侧，再用 ⌘ 拖动需要收纳的图标。"
        saveOptIn(true)
        Self.prepareMainStatusPosition()
    }
    func deactivate() {
        expand(); closePanel(); context.hotkeys.remove(owner: info.id)
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        if let control { NSStatusBar.system.removeStatusItem(control) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        control = nil; divider = nil; isOrganizing = false; icons = []; visibleIcons = []
    }
    func turnOff() {
        saveOptIn(false); deactivate(); Self.prepareMainStatusPosition()
        status = "菜单栏收纳已关闭；原生图标已展开。原托盘位置下次启动时恢复。"
    }

    static func canCollapse(dividerX: CGFloat, controlX: CGFloat, screen: CGRect) -> Bool {
        dividerX >= screen.minX && controlX <= screen.maxX && dividerX + 8 < controlX
    }
    static func sanePositions(control: Double?, divider: Double?) -> Bool {
        guard let control, let divider else { return false }
        return control.isFinite && divider.isFinite && (0...10_000).contains(control)
            && (0...10_000).contains(divider) && divider >= control + 16
    }
    static func hiddenWindows(_ windows: [(id: CGWindowID, frame: CGRect)], leftOf dividerX: CGFloat,
                              in screen: CGRect, statusBarY: CGFloat) -> [(id: CGWindowID, frame: CGRect)] {
        windows.filter { $0.frame.width > 8 && $0.frame.width < 150 && $0.frame.minX >= screen.minX
            && $0.frame.maxX <= dividerX + 1 && screen.minX <= $0.frame.midX && $0.frame.midX <= screen.maxX
            && abs($0.frame.minY - statusBarY) < 48 }
            .sorted { $0.frame.minX < $1.frame.minX }
    }
    static func visibleWindows(_ windows: [(id: CGWindowID, frame: CGRect)], rightOf controlX: CGFloat,
                               in screen: CGRect, statusBarY: CGFloat) -> [(id: CGWindowID, frame: CGRect)] {
        windows.filter { $0.frame.width > 8 && $0.frame.width < 150 && $0.frame.minX >= controlX - 1
            && $0.frame.maxX <= screen.maxX && abs($0.frame.minY - statusBarY) < 48 }
            .sorted { $0.frame.minX > $1.frame.minX }
    }
    static func reorderTarget(source: CGRect, target: CGRect, dividerX: CGFloat,
                              controlX: CGFloat, screen: CGRect) -> (x: CGFloat, after: Bool)? {
        let hidden = source.maxX <= dividerX + 1 && target.maxX <= dividerX + 1
        let visible = source.minX >= controlX - 1 && target.minX >= controlX - 1
        guard hidden || visible else { return nil }
        let after = source.midX < target.midX
        let x = after ? target.maxX + 8 : target.minX - 8
        guard x > screen.minX + 8, x < screen.maxX - 8,
              hidden ? x < dividerX : x > controlX else { return nil }
        return (x, after)
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
        if shelfPanel?.isVisible == true { closePanel(); return }
        if isCollapsed { showCachedPanel() }
        else if let layout = placement() {
            let menuY = (NSScreen.screens.first?.frame.maxY ?? layout.screen.maxY) - layout.screen.maxY
            let count = Self.visibleWindows(statusWindows(), rightOf: layout.control.maxX, in: layout.screen, statusBarY: menuY).count
            if !CGPreflightScreenCaptureAccess() {
                status = "需要屏幕录制权限才能显示图标预览；尚未隐藏或移动图标。"
                showHelpPanel()
            } else if count > visibleLimit && !AXIsProcessTrusted() {
                status = "需要辅助功能权限才能自动整理超出数量的图标；尚未移动图标。"
                showHelpPanel()
            } else if count > visibleLimit { applyVisibleLimit(showShelf: true) }
            else { hideIntoPanel() }
        } else {
            status = "收纳图标位置不可读，保持菜单栏展开。"
            showHelpPanel()
        }
    }
    func openShelf() { controlClicked() }
    func retryOpenShelf() { closePanel(); controlClicked() }
    func expand() {
        work?.cancel(); work = nil; token = UUID(); closePanel()
        divider?.length = NSStatusItem.variableLength
        isCollapsed = false
        if isOrganizing { status = "已展开；按住 ⌘ 在原生菜单栏拖动可见图标跨过分隔符。" }
    }
    func setVisibleLimit(_ value: Int) {
        visibleLimit = min(30, max(1, value))
        if let data = try? JSONEncoder().encode(visibleLimit) { context.settings.set(data, forKey: "visibleLimit") }
    }
    private func accessibilityReady(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = prompt ? AXIsProcessTrustedWithOptions(options) : AXIsProcessTrusted()
        guard trusted else {
            status = "辅助功能未授权；未移动图标。可在原生菜单栏按住 ⌘ 手动拖动。"
            return false
        }
        return true
    }
    private func statusFrame(_ id: CGWindowID) -> CGRect? { statusWindows().first { $0.id == id }?.frame }
    private func postDrag(from source: CGPoint, to destination: CGPoint, token moveToken: UUID) async -> Bool {
        let original = CGEvent(source: nil)?.location
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown, source)
        var completed = true
        for step in 1...12 {
            if token != moveToken || !isOrganizing { completed = false; break }
            let fraction = CGFloat(step) / 12
            post(.leftMouseDragged, CGPoint(x: source.x + (destination.x - source.x) * fraction,
                                            y: source.y + (destination.y - source.y) * fraction))
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        post(.leftMouseUp, completed ? destination : source)
        if let original { CGWarpMouseCursorPosition(original) }
        return completed
    }
    func moveIcon(_ id: CGWindowID, intoShelf: Bool) {
        guard isOrganizing, !moving, icons.contains(where: { $0.id == id }) || visibleIcons.contains(where: { $0.id == id }),
              accessibilityReady() else { return }
        moving = true
        expand()
        status = "正在移动图标…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let moved = await self.moveExpandedIcon(id, intoShelf: intoShelf)
            self.moving = false
            if moved { self.hideIntoPanel() }
        }
    }
    private func moveExpandedIcon(_ id: CGWindowID, intoShelf: Bool) async -> Bool {
            let moveToken = token
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard token == moveToken, isOrganizing else { return false }
            guard let layout = placement(), let frame = statusFrame(id),
                  Self.canCollapse(dividerX: layout.divider.minX, controlX: layout.control.minX, screen: layout.screen) else {
                status = "图标或分隔符已不可见，保持展开；请手动 ⌘ 拖动。"; return false
            }
            guard frame.minX >= layout.screen.minX, frame.maxX <= layout.screen.maxX,
                  (frame.maxX <= layout.divider.minX + 1 || frame.minX >= layout.control.maxX - 1) else {
                status = "图标不在可安全拖动的区域，保持展开。"; return false
            }
            let wasHidden = frame.maxX <= layout.divider.minX + 1
            guard wasHidden != intoShelf else { status = "图标已在目标区域。"; return true }
            let destinationX = intoShelf ? layout.divider.minX - max(20, frame.width) : layout.control.maxX + max(20, frame.width)
            guard destinationX > layout.screen.minX + 8, destinationX < layout.screen.maxX - 8 else {
                status = "目标位置不在可见菜单栏内，保持展开。"; return false
            }
            guard await postDrag(from: CGPoint(x: frame.midX, y: frame.midY),
                                 to: CGPoint(x: destinationX, y: frame.midY), token: moveToken) else { return false }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard token == moveToken, isOrganizing else { return false }
            guard let after = statusFrame(id) else { status = "无法确认图标移动，保持展开。"; return false }
            let crossed = intoShelf ? after.maxX <= layout.divider.minX + 1 : after.minX >= layout.control.maxX - 1
            status = crossed ? "图标已移到\(intoShelf ? "收纳区" : "可见区")；菜单栏保持展开，可继续调整。" : "系统没有接受这次移动，保持展开；可手动 ⌘ 拖动。"
            return crossed
    }
    func applyVisibleLimit(showShelf: Bool = false) {
        guard isOrganizing, !moving, accessibilityReady() else { return }
        if showShelf && !CGPreflightScreenCaptureAccess() {
            status = "请先授权屏幕录制；未移动或隐藏图标。"; return
        }
        moving = true
        expand()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.moving = false }
            var moved = 0
            while moved < 30 {
                guard let layout = self.placement(), Self.canCollapse(dividerX: layout.divider.minX,
                    controlX: layout.control.minX, screen: layout.screen) else {
                    self.status = "分隔符或控制图标不可见，已停止自动收纳。"; return
                }
                let menuY = (NSScreen.screens.first?.frame.maxY ?? layout.screen.maxY) - layout.screen.maxY
                let visible = Self.visibleWindows(self.statusWindows(), rightOf: layout.control.maxX,
                                                  in: layout.screen, statusBarY: menuY)
                guard visible.count > self.visibleLimit else {
                    self.status = "可见区有 \(visible.count) 个图标，已符合上限 \(self.visibleLimit)。"
                    if showShelf { self.moving = false; self.hideIntoPanel() }
                    return
                }
                guard let candidate = visible.last, await self.moveExpandedIcon(candidate.id, intoShelf: true) else {
                    self.status = "自动收纳在第 \(moved + 1) 个图标处停止：\(self.status)"; return
                }
                moved += 1
            }
            self.status = "已移动 30 个图标；为避免持续重排已停止，请检查菜单栏。"
        }
    }
    func reorderIcon(_ id: CGWindowID, nextTo targetID: CGWindowID) {
        guard id != targetID, isOrganizing, !moving, accessibilityReady(),
              (icons.contains(where: { $0.id == id }) && icons.contains(where: { $0.id == targetID })) ||
              (visibleIcons.contains(where: { $0.id == id }) && visibleIcons.contains(where: { $0.id == targetID })) else { return }
        moving = true; expand()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.moving = false }
            let moveToken = self.token
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.token == moveToken, self.isOrganizing, let layout = self.placement(),
                  let source = self.statusFrame(id), let target = self.statusFrame(targetID),
                  let destination = Self.reorderTarget(source: source, target: target,
                        dividerX: layout.divider.minX, controlX: layout.control.maxX, screen: layout.screen) else {
                self.status = "两个图标不在同一安全区域，保持展开。"; return
            }
            guard await self.postDrag(from: CGPoint(x: source.midX, y: source.midY),
                                      to: CGPoint(x: destination.x, y: target.midY), token: moveToken) else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.token == moveToken, let after = self.statusFrame(id), let targetAfter = self.statusFrame(targetID) else { return }
            let ordered = destination.after ? after.midX > targetAfter.midX : after.midX < targetAfter.midX
            self.status = ordered ? "已调整原生图标顺序；菜单栏保持展开。" : "系统未接受顺序调整；可手动 ⌘ 拖动。"
            if ordered { self.moving = false; self.hideIntoPanel() }
        }
    }
    private func closePanel() { shelfPanel?.contentView = nil; shelfPanel?.close(); shelfPanel = nil }
    private func showHelpPanel() {
        guard let frame = control?.button?.window?.frame,
              let screen = screen(for: frame) else { return }
        closePanel()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 390, height: 112),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "菜单栏收纳"
        panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: OrganizerHelpView(plugin: self).frame(width: 390, height: 112))
        view.sizingOptions = []
        panel.contentView = view
        panel.setFrameOrigin(CGPoint(x: max(screen.minX, min(frame.maxX - panel.frame.width, screen.maxX - panel.frame.width)),
                                     y: frame.minY - panel.frame.height - 5))
        panel.orderFrontRegardless(); shelfPanel = panel
    }
    func requestAccessibilityPermission() { _ = accessibilityReady(prompt: true) }
    func requestPermission() {
        guard active else { return }
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() { status = "已授权，点击收纳图标打开第二排。" }
        else { status = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权本应用，然后重启。" }
    }
    @available(macOS 14, *)
    private static func snapshot(_ window: SCWindow, frame: CGRect) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = max(16, Int(frame.width * 2)); config.height = max(16, Int(frame.height * 2))
        config.showsCursor = false; config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }
    func hideIntoPanel() {
        guard isOrganizing, !isCollapsed, !moving else { return }
        guard CGPreflightScreenCaptureAccess() else {
            status = "先点击「授权屏幕录制」；未授权时不会隐藏任何图标。"
            showHelpPanel(); return
        }
        if let error = context.hotkeys.error(owner: info.id, id: "emergency-reveal") {
            status = "紧急展开快捷键不可用（\(error)），不会隐藏图标；请解除冲突后重试。"
            showHelpPanel(); return
        }
        guard let geometry = placement(), Self.canCollapse(dividerX: geometry.divider.minX, controlX: geometry.control.minX, screen: geometry.screen) else {
            status = "收纳按钮必须在分隔符右侧且可见；请按住 ⌘ 拖动两者后重试。"
            showHelpPanel(); return
        }
        let separatorX = geometry.divider.minX
        let menuY = (NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY) - geometry.screen.maxY
        let targets = Self.hiddenWindows(statusWindows(), leftOf: separatorX, in: geometry.screen, statusBarY: menuY)
        guard !targets.isEmpty else {
            status = "分隔符左侧尚无可收纳图标；先按住 ⌘ 拖动图标。"
            showHelpPanel(); return
        }
        let outside = Self.visibleWindows(statusWindows(), rightOf: geometry.control.maxX, in: geometry.screen, statusBarY: menuY)
        work?.cancel(); let id = UUID(); token = id
        status = "正在读取 \(targets.count) 个图标…"
        work = Task { @MainActor [weak self] in
            guard #available(macOS 14, *) else { return }
            do {
                let started = ContinuousClock.now
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let windows = Dictionary(shareable.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                let matches = try targets.map { target -> SCWindow in
                    guard let window = windows[target.id] else { throw Failure.message("有图标无法读取，本次不隐藏") }
                    return window
                }
                var images = [CGImage?](repeating: nil, count: targets.count)
                try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
                    func add(_ index: Int) {
                        group.addTask {
                            try Task.checkCancellation()
                            return (index, try await Self.snapshot(matches[index], frame: targets[index].frame))
                        }
                    }
                    for index in 0..<min(4, matches.count) { add(index) }
                    for index in 4..<matches.count {
                        guard let (done, image) = try await group.next() else { throw Failure.message("图标采集提前结束") }
                        images[done] = image
                        add(index)
                    }
                    while let (done, image) = try await group.next() { images[done] = image }
                }
                let captured = try targets.enumerated().map { index, target -> ShelfIcon in
                    guard let image = images[index] else { throw Failure.message("图标采集不完整") }
                    return ShelfIcon(id: target.id, frame: target.frame, image: image)
                }
                var outsideCaptured: [ShelfIcon] = []
                for target in outside {
                    guard let window = windows[target.id] else { continue }
                    if let image = try? await Self.snapshot(window, frame: target.frame) {
                        outsideCaptured.append(ShelfIcon(id: target.id, frame: target.frame, image: image))
                    }
                }
                guard !Task.isCancelled, let self, self.token == id, self.isOrganizing else { return }
                guard let latest = self.placement(), Self.canCollapse(dividerX: latest.divider.minX, controlX: latest.control.minX, screen: latest.screen),
                      Self.hiddenWindows(self.statusWindows(), leftOf: latest.divider.minX, in: latest.screen, statusBarY: menuY).map(\.id) == targets.map(\.id) else {
                    self.status = "采集期间图标顺序发生变化，保持展开；请重试。"
                    self.showHelpPanel(); return
                }
                self.icons = captured
                self.visibleIcons = outsideCaptured
                self.divider?.length = 10_000
                // Check after reflow; never leave the recovery control hidden.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.token == id else { return }
                    guard let now = self.placement(), now.control.minX >= now.screen.minX,
                          now.control.maxX <= now.screen.maxX else {
                        self.expand(); self.status = "收纳按钮会被一起隐藏，已自动撤销。请 ⌘-拖动按钮到分隔符右侧。"; return
                    }
                    let elapsed = started.duration(to: ContinuousClock.now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    self.isCollapsed = true
                    self.status = "已收纳 \(captured.count) 个图标（\(String(format: "%.1f", seconds)) 秒）；展开后可重新排列。"
                    self.showCachedPanel()
                }
            } catch {
                guard !Task.isCancelled, let self, self.token == id else { return }
                self.expand(); self.status = "读取图标失败，保持原样：\(error.localizedDescription)"
                self.showHelpPanel()
            }
        }
    }
    private func showCachedPanel() {
        guard isCollapsed, let geometry = placement(), !icons.isEmpty else { return }
        closePanel()
        let view = NSHostingView(rootView: ShelfPanelView(plugin: self, icons: icons, outside: visibleIcons,
            onExpand: { [weak self] in self?.expand() },
            onMove: { [weak self] id, hidden in self?.moveIcon(id, intoShelf: hidden) },
            onReorder: { [weak self] id, target in self?.reorderIcon(id, nextTo: target) },
            onClick: { [weak self] id in self?.activateIcon(id) },
            onOpenToolbox: { [weak self] in self?.openToolbox() }))
        let width = min(geometry.screen.width - 24, max(380, min(660, CGFloat(max(icons.count, visibleIcons.count)) * 46 + 40)))
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: width, height: 258),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "收纳的菜单栏图标"
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.contentView = view
        let x = max(geometry.screen.minX, min(geometry.control.maxX - panel.frame.width, geometry.screen.maxX - panel.frame.width))
        panel.setFrameOrigin(CGPoint(x: x, y: geometry.control.minY - panel.frame.height - 5))
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); shelfPanel = panel
    }
    private func openToolbox() {
        closePanel()
        if let delegate = NSApp.delegate as? AppDelegate { delegate.showWindow(model: delegate.model) }
    }
    func activateIcon(_ id: CGWindowID) {
        guard isCollapsed, accessibilityReady(), let frame = icons.first(where: { $0.id == id })?.frame else { return }
        expand()
        let clickToken = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, self.token == clickToken, self.isOrganizing,
                  let current = self.statusFrame(id), abs(current.midX - frame.midX) < 50 else {
                self?.status = "图标位置已变化，未代替点击；菜单栏已展开。"; return
            }
            let point = CGPoint(x: current.midX, y: current.midY)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            self.status = "已点击原生图标；菜单栏保持展开。"
        }
    }
    func makeView() -> AnyView { AnyView(MenuBarOrganizerView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(MenuBarOrganizerMenu(plugin: self)) }
}

private struct OrganizerHelpView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("授权屏幕录制") { plugin.requestPermission() }
                Button("授权辅助功能") { plugin.requestAccessibilityPermission() }
                Button("重试") { plugin.retryOpenShelf() }
                Button("关闭") { plugin.expand() }
            }.controlSize(.small)
            Spacer(minLength: 0)
        }.padding(16)
    }
}

private struct ShelfPanelView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    @State private var hiddenDropTarget = false
    @State private var visibleDropTarget = false
    let icons: [ShelfIcon]
    let outside: [ShelfIcon]
    let onExpand: () -> Void
    let onMove: (CGWindowID, Bool) -> Void
    let onReorder: (CGWindowID, CGWindowID) -> Void
    let onClick: (CGWindowID) -> Void
    let onOpenToolbox: () -> Void
    private func row(_ items: [ShelfIcon], hidden: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { index in
                    let icon = items[index]
                    Button { if hidden { onClick(icon.id) } else { onMove(icon.id, true) } } label: {
                        Image(decorative: icon.image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 27).padding(6)
                            .background(Color.primary.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(hidden ? "收纳" : "可见")图标 \(index + 1)")
                    .help(hidden ? "点击原生图标；拖到可见区可移出" : "点击移入收纳区；也可拖动")
                    .contextMenu { Button(hidden ? "移出收纳区" : "移入收纳区") { onMove(icon.id, !hidden) } }
                    .onDrag { NSItemProvider(object: String(icon.id) as NSString) }
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let text = value as? String, let id = CGWindowID(text) else { return }
                            DispatchQueue.main.async {
                                if items.contains(where: { $0.id == id }) { onReorder(id, icon.id) }
                                else { onMove(id, hidden) }
                            }
                        }
                        return true
                    }
                }
            }
        }
        .frame(height: 43)
        .background((hidden ? hiddenDropTarget : visibleDropTarget) ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.text], isTargeted: hidden ? $hiddenDropTarget : $visibleDropTarget) { providers in
            guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let text = value as? String, let id = CGWindowID(text) else { return }
                DispatchQueue.main.async { onMove(id, hidden) }
            }
            return true
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已收纳 \(icons.count) 个图标").font(.headline)
                Spacer()
                Text(AXIsProcessTrusted() ? "点击打开 · 拖动调整" : "当前版本无法拖放")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("收纳区").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            row(icons, hidden: true)
            Text("可见区 · 拖到上排移入").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            row(outside, hidden: false)
            Text(plugin.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button("打开工具箱") { onOpenToolbox() }
                Spacer()
                Button(AXIsProcessTrusted() ? "展开全部图标" : "手动排列 · 展开全部") { onExpand() }
            }
        }.padding(14)
    }
}
private struct MenuBarOrganizerView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("状态与操作", systemImage: "rectangle.3.group").font(.headline)
                    Spacer()
                    Label(plugin.isCollapsed ? "已收纳" : plugin.isOrganizing ? "已展开" : "未启用",
                          systemImage: plugin.isOrganizing ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("菜单栏保留收纳按钮与分隔符；点击按钮打开第二排，按住 ⌘ 可在原生菜单栏移动图标。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if plugin.isOrganizing {
                        Button(plugin.isCollapsed ? "打开收纳面板" : "收纳并打开") { plugin.openShelf() }
                            .buttonStyle(.borderedProminent)
                        Button("展开全部") { plugin.expand() }
                        Spacer()
                        Button("关闭功能") { plugin.turnOff() }
                    } else {
                        Button("启用菜单栏收纳") { plugin.enable() }.buttonStyle(.borderedProminent)
                    }
                }
                Divider()
                HStack {
                    Stepper("保留 \(plugin.visibleLimit) 个可见图标", value: Binding(
                        get: { plugin.visibleLimit }, set: { plugin.setVisibleLimit($0) }), in: 1...30)
                    Spacer()
                    Button("按数量整理") { plugin.applyVisibleLimit() }.disabled(!plugin.isOrganizing)
                }
                Text(plugin.status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if plugin.isOrganizing && !AXIsProcessTrusted() {
                    Label("当前安装版本未获辅助功能信任；弹框内无法移动系统图标。可展开后在原生菜单栏按住 ⌘ 拖动可见图标。",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Menu("权限与帮助") {
                        Button("屏幕录制权限") { plugin.requestPermission() }
                        Button("辅助功能权限") { plugin.requestAccessibilityPermission() }
                    }
                    Spacer()
                    Text("紧急展开 ⌃⌥⌘R").foregroundStyle(.secondary)
                }.font(.caption)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct MenuBarOrganizerMenu: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        Button(plugin.isOrganizing ? "关闭菜单栏收纳" : "启用菜单栏收纳") { plugin.isOrganizing ? plugin.turnOff() : plugin.enable() }
        if plugin.isOrganizing {
            Button("展开并排列") { plugin.expand() }
            Button("打开收纳面板") { plugin.openShelf() }
            Button("按可见数量整理") { plugin.applyVisibleLimit() }
        }
    }
}
