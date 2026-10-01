import SwiftUI
import Carbon
import ScreenCaptureKit
import ApplicationServices

struct ShelfIcon: Identifiable {
    let id: CGWindowID
    let frame: CGRect
    let image: CGImage?
    var identity: MenuBarIconIdentity? = nil
    var availability: MenuBarDisplay.Availability? = nil
}

enum ShelfDropAction: Equatable {
    case move(CGWindowID, Bool)
    case reorder(CGWindowID, CGWindowID)
}

final class MenuBarOrganizerPlugin: NSObject, ObservableObject, ToolPlugin, NSPopoverDelegate {
    static let id = "menu-bar-organizer"
    private static let controlName = "mactools_shelf_control"
    private static let dividerName = "mactools_shelf_divider"
    private static let mainPositionKey = "NSStatusItem Preferred Position Item-0"
    private static let priorMainPositionKey = "plugin.menu-bar-organizer.priorMainPosition"
    private static let pinnedMainPosition = 200.0
    let info = PluginInfo(id: id, title: "菜单栏收纳", symbol: "rectangle.3.group", detail: "点击展开或收起原生图标；图标面板可选", placement: .content)
    @Published private(set) var visibility = MenuBarVisibility()
    var isOrganizing: Bool { visibility.state != .disabled }
    var isCollapsed: Bool { visibility.state == .collapsed }
    @Published private(set) var presentationMode: OrganizerPresentationMode
    @Published private(set) var gallery = MenuBarGallerySession()
    var isCapturing: Bool { gallery.isCapturing }
    @Published var allowsPanelEditing = false
    @Published var showsAdvancedOptions = false
    var icons: [ShelfIcon] { gallery.icons }
    var visibleIcons: [ShelfIcon] { gallery.visibleIcons }
    @Published var visibleLimit = 6
    @Published private(set) var status = "默认关闭；启用后把要收起的原生图标 ⌘-拖到分隔符左侧。"
    private let context: PluginContext
    private var active = false
    private var control: NSStatusItem?
    private var divider: NSStatusItem?
    private var shelfPopover: NSPopover?
    private var popoverMonitors: [Any] = []
    private var popoverDeactivateObserver: NSObjectProtocol?
    private var work: Task<Void, Never>?
    private var environment = MenuBarEnvironment()
    private var environmentMonitor: MenuBarEnvironmentMonitor?
    private var environmentWork: Task<Void, Never>?
    private var token: UUID { gallery.generation }
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

    init(context: PluginContext) {
        self.context = context
        presentationMode = OrganizerPresentationMode.load(from: context.settings)
        super.init()
        if context.settings.data(forKey: "presentationMode") == nil,
           let data = try? JSONEncoder().encode(presentationMode) {
            context.settings.set(data, forKey: "presentationMode")
        }
    }
    func setPresentationMode(_ mode: OrganizerPresentationMode) {
        expand(); allowsPanelEditing = false
        presentationMode = mode
        if let data = try? JSONEncoder().encode(mode) { context.settings.set(data, forKey: "presentationMode") }
        status = mode == .native ? "普通点击只展开或收起；直接操作原生图标，无需录屏或辅助功能权限。" : "普通点击打开图标面板；不会自动移动图标，需屏幕录制权限。"
    }
    func start() {
        active = true
        if let data = context.settings.data(forKey: "visibleLimit"), let value = try? JSONDecoder().decode(Int.self, from: data) {
            visibleLimit = min(30, max(1, value))
        }
        if let data = context.settings.data(forKey: "optedIn"), (try? JSONDecoder().decode(Bool.self, from: data)) == true { enable() }
    }
    func stop() { deactivate(); allowsPanelEditing = false; active = false }
    deinit {
        work?.cancel(); environmentWork?.cancel(); environmentMonitor?.stop()
        removePopoverMonitors()
        shelfPopover?.delegate = nil; shelfPopover?.close()
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
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = Self.dividerName
        divider.button?.title = "│"; divider.button?.toolTip = "按住 ⌘，将原生菜单栏图标拖到分隔符左右两侧"
        self.control = control; self.divider = divider; visibility.enable()
        environment = MenuBarEnvironment()
        context.hotkeys.replace(owner: info.id, actions: [HotKeyAction(id: "emergency-reveal",
            chord: KeyChord(key: "R", modifiers: UInt32(controlKey | optionKey | cmdKey)),
            perform: { [weak self] in self?.expand() }),
            HotKeyAction(id: "toggle-native", chord: KeyChord(key: "H", modifiers: UInt32(controlKey | optionKey | cmdKey)),
                         perform: { [weak self] in self?.toggleNative() })])
        environmentMonitor = MenuBarEnvironmentMonitor { [weak self] change in self?.environmentChanged(change) }
        environmentMonitor?.start()
        status = "已启用。请将收纳按钮留在分隔符右侧，再用 ⌘ 拖动需要收纳的图标。"
        saveOptIn(true)
        Self.prepareMainStatusPosition()
    }
    func deactivate() {
        expand(); closePanel(); context.hotkeys.remove(owner: info.id)
        environmentMonitor?.stop(); environmentMonitor = nil
        environmentWork?.cancel(); environmentWork = nil
        environment = MenuBarEnvironment()
        if let control { NSStatusBar.system.removeStatusItem(control) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        control = nil; divider = nil; visibility.disable()
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
    static func residentWindows(_ windows: [(id: CGWindowID, frame: CGRect)], after divider: CGRect,
                                in screen: CGRect, statusBarY: CGFloat) -> [(id: CGWindowID, frame: CGRect)] {
        visibleWindows(windows, rightOf: divider.maxX, in: screen, statusBarY: statusBarY)
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
    static func shelfDrop(source: CGWindowID, at point: CGPoint, hidden: [CGWindowID], visible: [CGWindowID],
                          hiddenRow: CGRect, visibleRow: CGRect, iconFrames: [CGWindowID: CGRect]) -> ShelfDropAction? {
        let wasHidden = hidden.contains(source)
        guard wasHidden || visible.contains(source) else { return nil }
        let targetHidden: Bool
        if hiddenRow.contains(point) { targetHidden = true }
        else if visibleRow.contains(point) { targetHidden = false }
        else { return nil }
        if targetHidden != wasHidden { return .move(source, targetHidden) }
        let targets = (targetHidden ? hidden : visible).filter { $0 != source && iconFrames[$0] != nil }
        guard let target = targets.min(by: { abs(iconFrames[$0]!.midX - point.x) < abs(iconFrames[$1]!.midX - point.x) }) else { return nil }
        return .reorder(source, target)
    }
    func environmentChanged(_ change: MenuBarEnvironment.Change) {
        environment.receive(change)
        environmentWork?.cancel(); environmentWork = nil
        guard isOrganizing else { return }
        if change == .applicationsChanged {
            work?.cancel(); work = nil
            if isCapturing || moving || visibility.state == .collapsing { expand() }
            else { gallery.invalidateTargets(); _ = visibility.dismissPopover() }
            status = "应用状态发生变化；下次点击会重新核实身份，无法唯一确认时可重试采集。"
            return
        }
        // Never leave an old large divider or coordinates active across display/sleep changes.
        expand()
        status = change == .willSleep ? "即将睡眠；已展开并清除截图，唤醒后重新核实屏幕。" : "屏幕布局发生变化；已展开，正在重新核实收纳按钮位置。"
        guard change != .willSleep else { return }
        let generation = environment.generation, layoutGeneration = visibility.generation
        environmentWork = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self, self.environment.accepts(generation), self.visibility.generation == layoutGeneration, self.isOrganizing else { return }
            let first = MenuBarDisplay.current()
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            guard self.environment.accepts(generation), self.visibility.generation == layoutGeneration, self.isOrganizing else { return }
            guard first == MenuBarDisplay.current(), self.placement() != nil, self.recoveryControlVisible() else {
                self.status = "屏幕布局尚未稳定，或收纳按钮被刘海 / 屏幕边界遮挡；保持展开。可从工具箱重试，⌃⌥⌘R 可展开。"
                return
            }
            self.status = "已按当前显示器重新核实位置；保持展开，请点击收起或重新打开图标面板。"
        }
    }
    private func captureIdentitiesUnchanged(_ identities: [CGWindowID: MenuBarIconIdentity], ids: [CGWindowID]) -> Bool {
        let latest = statusTargets()
        return ids.allSatisfy { id in
            guard let original = identities[id], let current = latest.first(where: { $0.id == id }) else { return false }
            return original.pid == current.pid && original.application == current.application
        }
    }
    private func statusWindows() -> [(id: CGWindowID, frame: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { item in
            guard (item[kCGWindowLayer as String] as? Int) == level,
                  (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ProcessInfo.processInfo.processIdentifier,
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
              let display = MenuBarDisplay.current().first(where: { $0.frame.contains(CGPoint(x: controlFrame.midX, y: controlFrame.midY)) }),
              display.containsStatusPair(divider: dividerFrame, control: controlFrame) else { return nil }
        return (display.quartz(dividerFrame), display.quartz(controlFrame), display.quartzFrame)
    }
    @objc private func controlClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp, let button = control?.button {
            let menu = NSMenu()
            for (title, action) in [("展开 / 收起原生图标", #selector(toggleFromMenu)),
                                    ("排列原生图标…", #selector(arrangeFromMenu)),
                                    ("打开图标面板…", #selector(panelFromMenu)),
                                    ("打开工具箱", #selector(toolboxFromMenu))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self; menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }
        if presentationMode == .native { toggleNative() } else { openShelf() }
    }
    @objc private func toggleFromMenu() { toggleNative() }
    @objc private func arrangeFromMenu() { arrangeNativeIcons() }
    @objc private func panelFromMenu() { openShelf() }
    @objc private func toolboxFromMenu() { openToolbox() }

    func toggleNative() {
        guard isOrganizing, !moving else { return }
        if visibility.state == .collapsed || visibility.state == .collapsing || isCapturing { expand() }
        else { closePanel(); collapse() }
    }
    func arrangeNativeIcons() {
        expand()
        if isOrganizing { status = "排列模式：在原生菜单栏按住 ⌘ 拖动图标跨分隔符；完成后点击收起。不会自动移动图标。" }
    }
    func openShelf() {
        guard isOrganizing, !moving else { return }
        if shelfPopover != nil { dismissShelf() }
        else if isCapturing { expand() }
        else { hideIntoPanel() }
    }
    func retryOpenShelf() { expand(); hideIntoPanel() }
    func expand() {
        closePanel()
        divider?.length = NSStatusItem.variableLength
        visibility.expand()
        if isOrganizing { status = "已展开；直接点击原生图标，或按住 ⌘ 手动排列。再次点击 / ⌃⌥⌘H 收起。" }
    }
    private func recoveryControlVisible() -> Bool {
        guard let button = control?.button, let window = button.window, window.isVisible else { return false }
        // A notched bar's backing window is taller than its safe area; validate the visible button.
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let display = MenuBarDisplay.current().first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return false }
        return display.anchorSafe(frame, clippedTo: window.frame)
    }
    private func collapse(presentPanel: Bool = false) {
        guard visibility.state == .expanded, !moving, !environment.sleeping else { return }
        if let error = context.hotkeys.error(owner: info.id, id: "emergency-reveal") {
            expand(); status = "紧急展开快捷键不可用（\(error)），保持展开。"; showHelpPanel(); return
        }
        guard let layout = placement(), Self.canCollapse(dividerX: layout.divider.minX,
              controlX: layout.control.minX, screen: layout.screen), recoveryControlVisible() else {
            expand(); status = "控制图标或分隔符位置不安全，保持展开；请按住 ⌘ 手动排列。"; showHelpPanel(); return
        }
        let expandedWidth = layout.divider.width
        guard let collapseToken = visibility.beginCollapse() else { return }
        divider?.length = MenuBarVisibility.collapsedLength(screenWidths: NSScreen.screens.map { $0.frame.width })
        status = "正在收起…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.visibility.generation == collapseToken,
                  self.visibility.state == .collapsing else { return }
            let reflowed = (self.divider?.button?.window?.frame.width ?? 0) > expandedWidth + 8
            if self.visibility.finishCollapse(collapseToken, recoveryVisible: reflowed && self.recoveryControlVisible()) {
                self.status = "已收起；点击展开原生图标，⌃⌥⌘R 可紧急展开。"
                if presentPanel { self.showCachedPanel() }
            } else {
                self.expand(); self.status = "布局未确认或控制图标不可见，已恢复展开。"; self.showHelpPanel()
            }
        }
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
    private func statusTargets() -> [MenuBarStatusTarget] {
        let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard (item[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let identity = MenuBarApplicationIdentity.current(pid: pid)
            return MenuBarStatusTarget(id: id, pid: pid, frame: frame,
                onScreen: (item[kCGWindowIsOnscreen as String] as? Bool) == true, application: identity)
        }
    }
    private func activationSafeAreas() -> [CGRect] {
        MenuBarDisplay.current().flatMap(\.quartzSafeAreas)
    }
    private func activationResolution(_ identity: MenuBarIconIdentity) -> MenuBarIconResolution {
        guard let display = placement()?.screen else { return .failed(.offScreen) }
        return MenuBarIconIdentity.resolve(identity, windows: statusTargets(), safeAreas: activationSafeAreas(), preferredDisplay: display)
    }
    private func activationHitMatches(_ target: MenuBarStatusTarget) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(target.frame.midX), Float(target.frame.midY), &hit) == .success else { return false }
        // A status item's image may be the deepest hit element; only accept a matching parent within this item.
        for _ in 0..<4 {
            guard let element = hit else { return false }
            var owner: Int32 = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == target.pid else { return false }
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?, role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let positionValue, let sizeValue, CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                var position = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
                   [kAXMenuBarItemRole as String, kAXButtonRole as String].contains(role as? String ?? ""),
                   MenuBarIconActivation.hitMatches(CGRect(origin: position, size: size), window: target.frame) { return true }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            hit = (parent as! AXUIElement)
        }
        return false
    }
    func beginPanelEditing() {
        guard accessibilityReady() else { let reason = status; expand(); status = reason; showHelpPanel(); return }
        allowsPanelEditing = true
    }
    private func dragPointVisible(_ point: CGPoint) -> Bool {
        MenuBarVisibility.interactionPointVisible(point, safeAreas: activationSafeAreas())
    }
    @MainActor
    func postDrag(from source: CGPoint, to destination: CGPoint, token moveToken: UUID) async -> Bool {
        guard token == moveToken, isOrganizing, dragPointVisible(source), dragPointVisible(destination) else {
            status = "此图标或目标被刘海 / 屏幕边界遮挡，无法可靠移动；已保持展开。可从浮窗尝试打开图标，或在有足够空间的屏幕上编辑。"
            showHelpPanel(); return false
        }
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
        if !completed { status = "移动已取消；菜单栏保持展开。" }
        return completed
    }
    func moveIcon(_ id: CGWindowID, intoShelf: Bool) {
        guard isOrganizing, allowsPanelEditing, !moving, icons.contains(where: { $0.id == id }) || visibleIcons.contains(where: { $0.id == id }),
              accessibilityReady() else { return }
        guard let identity = (icons + visibleIcons).first(where: { $0.id == id })?.identity else {
            expand(); status = "无法核实图标身份，未移动；请重试采集。"; showHelpPanel(); return
        }
        moving = true
        expand()
        status = "正在移动图标…"
        let moveToken = token
        Task { @MainActor [weak self] in
            guard let self else { return }
            let moved = await self.moveExpandedIcon(id, intoShelf: intoShelf, generation: moveToken, identity: identity)
            self.moving = false
            if moved { self.hideIntoPanel() }
        }
    }
    @MainActor
    private func moveExpandedIcon(_ id: CGWindowID, intoShelf: Bool, generation moveToken: UUID, identity: MenuBarIconIdentity) async -> Bool {
        status = "正在等待菜单栏展开…"
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard token == moveToken, isOrganizing else { status = "移动已取消；菜单栏保持展开。"; return false }
        let resolution = activationResolution(identity)
        guard let resolved = resolution.target else {
            status = (resolution.failure?.message ?? "无法核实图标身份。") + " 未移动，菜单栏保持展开。"; showHelpPanel(); return false
        }
        let currentID = resolved.id
        guard let layout = placement(), let frame = statusFrame(currentID),
              Self.canCollapse(dividerX: layout.divider.minX, controlX: layout.control.minX, screen: layout.screen) else {
            status = "图标或分隔符已不可见，保持展开；请手动 ⌘ 拖动。"; return false
        }
        guard frame.minX >= layout.screen.minX, frame.maxX <= layout.screen.maxX,
              (frame.maxX <= layout.divider.minX + 1 || frame.minX >= layout.divider.maxX - 1) else {
            status = "图标不在可安全拖动的区域，保持展开。"; return false
        }
        let wasHidden = frame.maxX <= layout.divider.minX + 1
        guard wasHidden != intoShelf else { status = "图标已在目标区域。"; return true }
        let destinationX = intoShelf ? layout.divider.minX - max(20, frame.width) : layout.divider.maxX + max(20, frame.width)
        guard destinationX > layout.screen.minX + 8, destinationX < layout.screen.maxX - 8 else {
            status = "目标位置不在可见菜单栏内，保持展开。"; return false
        }
        guard activationHitMatches(resolved) else { status = "原图标被其他菜单或窗口覆盖，未移动；请展开后重试。"; return false }
        status = "正在拖动原生图标…"
        guard await postDrag(from: CGPoint(x: frame.midX, y: frame.midY),
                             to: CGPoint(x: destinationX, y: frame.midY), token: moveToken) else {
            return false
        }
        status = "正在确认图标位置…"
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard token == moveToken, isOrganizing else { status = "移动已取消；菜单栏保持展开。"; return false }
        guard let afterTarget = activationResolution(identity).target, afterTarget.id == currentID,
              afterTarget.pid == resolved.pid, afterTarget.application == resolved.application,
              let after = statusFrame(currentID), let latest = placement() else { status = "无法确认图标移动或身份发生变化，保持展开。"; return false }
        let crossed = intoShelf ? after.maxX <= latest.divider.minX + 1 : after.minX >= latest.divider.maxX - 1
        status = crossed ? "图标已移到\(intoShelf ? "收纳区" : "可见区")；菜单栏保持展开，可继续调整。" : "系统没有接受这次移动，保持展开；可手动 ⌘ 拖动。"
        return crossed
    }
    func applyVisibleLimit() {
        guard isOrganizing, !moving, accessibilityReady() else { return }
        moving = true
        expand()
        let moveToken = token
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.moving = false }
            var moved = 0
            while moved < 30 {
                guard self.token == moveToken, self.isOrganizing else { return }
                guard let layout = self.placement(), Self.canCollapse(dividerX: layout.divider.minX,
                    controlX: layout.control.minX, screen: layout.screen) else {
                    self.status = "分隔符或控制图标不可见，已停止自动收纳。"; return
                }
                let menuY = layout.screen.minY
                let visible = Self.visibleWindows(self.statusWindows(), rightOf: layout.divider.maxX,
                                                  in: layout.screen, statusBarY: menuY)
                guard visible.count > self.visibleLimit else {
                    self.status = "可见区有 \(visible.count) 个图标，已符合上限 \(self.visibleLimit)。"
                    return
                }
                let inventory = self.statusTargets()
                let peers = inventory.filter { abs($0.frame.minY - menuY) < 48 && layout.screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                guard let candidate = visible.last, let owner = inventory.first(where: { $0.id == candidate.id }),
                      await self.moveExpandedIcon(candidate.id, intoShelf: true, generation: moveToken,
                        identity: MenuBarIconIdentity(capturing: owner, peersOnDisplay: peers)) else {
                    self.status = "自动收纳在第 \(moved + 1) 个图标处停止：\(self.status)"; return
                }
                moved += 1
            }
            self.status = "已移动 30 个图标；为避免持续重排已停止，请检查菜单栏。"
        }
    }
    func reorderIcon(_ id: CGWindowID, nextTo targetID: CGWindowID) {
        guard id != targetID, isOrganizing, allowsPanelEditing, !moving, accessibilityReady(),
              (icons.contains(where: { $0.id == id }) && icons.contains(where: { $0.id == targetID })) ||
              (visibleIcons.contains(where: { $0.id == id }) && visibleIcons.contains(where: { $0.id == targetID })) else { return }
        guard let sourceIdentity = (icons + visibleIcons).first(where: { $0.id == id })?.identity,
              let targetIdentity = (icons + visibleIcons).first(where: { $0.id == targetID })?.identity else {
            expand(); status = "无法核实排序目标身份，未移动；请重试采集。"; showHelpPanel(); return
        }
        moving = true; expand()
        let moveToken = token
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.moving = false }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.token == moveToken, self.isOrganizing, let layout = self.placement(),
                  let sourceResolved = self.activationResolution(sourceIdentity).target,
                  let targetResolved = self.activationResolution(targetIdentity).target,
                  let source = self.statusFrame(sourceResolved.id), let target = self.statusFrame(targetResolved.id),
                  let destination = Self.reorderTarget(source: source, target: target,
                        dividerX: layout.divider.minX, controlX: layout.divider.maxX, screen: layout.screen) else {
                self.status = "两个图标不在同一安全区域，保持展开。"; return
            }
            guard self.activationHitMatches(sourceResolved), self.activationHitMatches(targetResolved) else {
                self.status = "排序图标被其他菜单或窗口覆盖，未移动；请展开后重试。"; return
            }
            guard await self.postDrag(from: CGPoint(x: source.midX, y: source.midY),
                                      to: CGPoint(x: destination.x, y: target.midY), token: moveToken) else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.token == moveToken, let afterResolved = self.activationResolution(sourceIdentity).target,
                  let targetAfterResolved = self.activationResolution(targetIdentity).target,
                  afterResolved.id == sourceResolved.id, afterResolved.application == sourceResolved.application,
                  targetAfterResolved.id == targetResolved.id, targetAfterResolved.application == targetResolved.application else {
                if self.token == moveToken { self.status = "无法确认排序后图标身份，保持展开。" }; return
            }
            let after = afterResolved.frame, targetAfter = targetAfterResolved.frame
            let ordered = destination.after ? after.midX > targetAfter.midX : after.midX < targetAfter.midX
            self.status = ordered ? "已调整原生图标顺序；菜单栏保持展开。" : "系统未接受顺序调整；可手动 ⌘ 拖动。"
            if ordered { self.moving = false; self.hideIntoPanel() }
        }
    }
    private func removePopoverMonitors() {
        popoverMonitors.forEach(NSEvent.removeMonitor); popoverMonitors = []
        if let popoverDeactivateObserver { NotificationCenter.default.removeObserver(popoverDeactivateObserver) }
        popoverDeactivateObserver = nil
    }
    private func closePanel() {
        gallery.clear(); work?.cancel(); work = nil
        dismissPopoverOnly()
    }
    private func dismissPopoverOnly() {
        removePopoverMonitors()
        let popover = shelfPopover; shelfPopover = nil
        popover?.delegate = nil; popover?.close(); popover?.contentViewController = nil
    }
    private func dismissShelf() {
        closePanel()
        let keptCollapsed = visibility.dismissPopover()
        if !keptCollapsed { divider?.length = NSStatusItem.variableLength }
        if isOrganizing {
            status = keptCollapsed ? "已收起；浮窗已关闭，常驻图标保持可见。⌃⌥⌘H / ⌃⌥⌘R 或右键菜单可展开。" : "采集已取消；原生图标保持展开。"
        }
    }
    func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover, popover === shelfPopover { dismissShelf() }
    }
    private func showPopover(_ content: AnyView, width: CGFloat) {
        guard shelfPopover == nil, let button = control?.button, button.window?.isVisible == true, recoveryControlVisible(), !environment.sleeping else {
            expand(); status = "控制图标不可见，已展开；请从工具箱手动排列。"; return
        }
        let controller = NSHostingController(rootView: content.frame(width: width).fixedSize(horizontal: false, vertical: true))
        controller.title = "菜单栏收纳"
        let popover = NSPopover()
        // Handle only this opening's mouse events. The anchor click reaches controlClicked to toggle once.
        popover.behavior = .applicationDefined; popover.animates = false
        popover.contentViewController = controller; popover.delegate = self
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = NSSize(width: width, height: max(48, controller.view.fittingSize.height))
        shelfPopover = popover
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self, weak popover] event in
            guard let self, let popover, self.shelfPopover === popover else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismissShelf(); return nil }
                return event
            }
            if event.window === popover.contentViewController?.view.window { return event }
            if let button = self.control?.button, event.window === button.window,
               button.bounds.contains(button.convert(event.locationInWindow, from: nil)) { return event }
            self.dismissShelf(); return event
        }) { popoverMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self, weak popover] _ in
            guard let self, let popover, self.shelfPopover === popover else { return }
            self.dismissShelf()
        }) {
            popoverMonitors.append(monitor)
        }
        popoverDeactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self, weak popover] _ in
            guard let self, let popover, self.shelfPopover === popover else { return }
            self.dismissShelf()
        }
        // Install handlers before the window becomes visible, then give the activated popover key focus.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else { expand(); status = "浮窗无法显示，已恢复展开。"; return }
        controller.view.window?.title = "菜单栏收纳"
        NSApp.activate(ignoringOtherApps: true)
        controller.view.window?.makeKey()
    }
    private func showHelpPanel() {
        guard let frame = control?.button?.window?.frame, let screen = screen(for: frame) else { expand(); return }
        closePanel()
        showPopover(AnyView(OrganizerHelpView(plugin: self)), width: min(340, screen.width - 32))
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
    func hideIntoPanel(retriesRemaining: Int = 1) {
        guard isOrganizing, !moving, !environment.sleeping else { return }
        expand()
        guard CGPreflightScreenCaptureAccess() else {
            status = "先点击「授权屏幕录制」；未授权时不会隐藏任何图标。"
            showHelpPanel(); return
        }
        let id = gallery.beginCapture()
        status = "正在等待菜单栏展开…"
        showPopover(AnyView(OrganizerCaptureView(plugin: self)), width: 300)
        guard token == id, shelfPopover != nil else { return }
        work = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard !Task.isCancelled, let self, self.token == id, self.isOrganizing else { return }
            self.captureExpandedPanel(id, retriesRemaining: retriesRemaining)
        }
    }
    private func captureExpandedPanel(_ id: UUID, retriesRemaining: Int) {
        guard token == id, isOrganizing else { return }
        if let error = context.hotkeys.error(owner: info.id, id: "emergency-reveal") {
            status = "紧急展开快捷键不可用（\(error)），不会隐藏图标；请解除冲突后重试。"
            showHelpPanel(); return
        }
        guard let geometry = placement(), Self.canCollapse(dividerX: geometry.divider.minX, controlX: geometry.control.minX, screen: geometry.screen) else {
            status = "收纳按钮必须在分隔符右侧且可见；请按住 ⌘ 拖动两者后重试。"
            showHelpPanel(); return
        }
        let separatorX = geometry.divider.minX
        let menuY = geometry.screen.minY
        let targets = Self.hiddenWindows(statusWindows(), leftOf: separatorX, in: geometry.screen, statusBarY: menuY)
        guard !targets.isEmpty else {
            status = "分隔符左侧尚无可收纳图标；先按住 ⌘ 拖动图标。"
            showHelpPanel(); return
        }
        let outside = Self.residentWindows(statusWindows(), after: geometry.divider, in: geometry.screen, statusBarY: menuY)
        // Capture application identity with the window inventory, before asynchronous screenshots.
        let inventory = statusTargets()
        let captureDisplay = MenuBarDisplay.current().first { $0.quartzFrame == geometry.screen }
        let peers = inventory.filter { abs($0.frame.minY - menuY) < 48 && geometry.screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        let identities = Dictionary(inventory.map { ($0.id, MenuBarIconIdentity(capturing: $0, peersOnDisplay: peers)) }, uniquingKeysWith: { first, _ in first })
        status = "正在读取 \(targets.count) 个图标…"
        work = Task { @MainActor [weak self] in
            guard #available(macOS 14, *) else { return }
            do {
                try Task.checkCancellation()
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let windows = Dictionary(shareable.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                let matches = try targets.map { target -> SCWindow in
                    guard let window = windows[target.id] else { throw Failure.message("有图标无法读取，本次不隐藏") }
                    return window
                }
                let images = try await MenuBarCapture.ordered(count: targets.count) { index in
                    try await Self.snapshot(matches[index], frame: targets[index].frame)
                }
                let captured = targets.enumerated().map { index, target in
                    ShelfIcon(id: target.id, frame: target.frame, image: images[index], identity: identities[target.id], availability: captureDisplay?.availability(of: target.frame))
                }
                var outsideCaptured: [ShelfIcon] = []
                for target in outside {
                    try Task.checkCancellation()
                    let image: CGImage?
                    if let window = windows[target.id] { image = try? await Self.snapshot(window, frame: target.frame) }
                    else { image = nil }
                    outsideCaptured.append(ShelfIcon(id: target.id, frame: target.frame, image: image, identity: identities[target.id], availability: captureDisplay?.availability(of: target.frame)))
                }
                guard !Task.isCancelled, let self, self.token == id, self.isOrganizing else { return }
                guard let latest = self.placement(), Self.canCollapse(dividerX: latest.divider.minX, controlX: latest.control.minX, screen: latest.screen),
                      latest.screen == geometry.screen,
                      Self.hiddenWindows(self.statusWindows(), leftOf: latest.divider.minX, in: latest.screen, statusBarY: latest.screen.minY).map(\.id) == targets.map(\.id),
                      Self.residentWindows(self.statusWindows(), after: latest.divider, in: latest.screen, statusBarY: latest.screen.minY).map(\.id) == outside.map(\.id),
                      self.captureIdentitiesUnchanged(identities, ids: (targets + outside).map(\.id)) else {
                    if retriesRemaining > 0 {
                        self.work = nil
                        self.hideIntoPanel(retriesRemaining: retriesRemaining - 1)
                    } else {
                        self.status = "菜单栏仍在变化，保持展开；请稍后重试或手动排列。"
                        self.showHelpPanel()
                    }
                    return
                }
                self.work = nil
                guard self.gallery.finishCapture(id, icons: captured, visible: outsideCaptured) else { return }
                self.collapse(presentPanel: true)
            } catch {
                guard !Task.isCancelled, let self, self.token == id else { return }
                self.expand(); self.status = "读取图标失败，保持原样：\(error.localizedDescription)"
                self.showHelpPanel()
            }
        }
    }
    private func showCachedPanel() {
        guard isCollapsed, let geometry = placement(), !icons.isEmpty else { expand(); return }
        dismissPopoverOnly()
        let width = MenuBarPopoverLayout.width(iconCount: max(icons.count, visibleIcons.count), screenWidth: geometry.screen.width)
        let view = ShelfPanelView(plugin: self, icons: icons, outside: visibleIcons, width: width,
            onExpand: { [weak self] in self?.arrangeNativeIcons() },
            onMove: { [weak self] id, hidden in self?.moveIcon(id, intoShelf: hidden) },
            onReorder: { [weak self] id, target in self?.reorderIcon(id, nextTo: target) },
            onClick: { [weak self] id in Task { @MainActor in self?.activateIcon(id) } },
            onOpenToolbox: { [weak self] in self?.openToolbox() })
        showPopover(AnyView(view), width: width)
    }
    func openToolbox() {
        expand(); showsAdvancedOptions = true
        context.openToolbox()
    }
    @MainActor
    func activateIcon(_ id: CGWindowID) {
        guard !allowsPanelEditing, isCollapsed,
              icons.contains(where: { $0.id == id }) || visibleIcons.contains(where: { $0.id == id }) else { return }
        guard let identity = (icons + visibleIcons).first(where: { $0.id == id })?.identity else {
            expand(); status = MenuBarIconResolution.Failure.unverifiedIdentity.message; showHelpPanel(); return
        }
        guard accessibilityReady() else {
            expand(); status = "已展开原生图标，请直接点击；图标面板代点需辅助功能权限。"; showHelpPanel(); return
        }
        // Remove all popover monitors before handing the click/focus to another application.
        expand()
        let clickToken = token
        work = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self, self.token == clickToken, self.isOrganizing else { return }
            let resolution = self.activationResolution(identity)
            guard let first = resolution.target else {
                self.status = resolution.failure?.message ?? "无法确认图标；未发送点击。"; self.showHelpPanel(); return
            }
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard self.token == clickToken, let target = self.activationResolution(identity).target,
                  MenuBarIconActivation.unchanged(first, target) else {
                if self.token == clickToken { self.status = "图标布局仍在变化；保持展开，未发送点击。"; self.showHelpPanel() }
                return
            }
            // Use a normal click only after confirming the current owner, unique visible window and stable geometry.
            guard self.token == clickToken, let fresh = self.activationResolution(identity).target,
                  MenuBarIconActivation.unchanged(target, fresh) else { return }
            guard self.activationHitMatches(fresh) else {
                self.status = "原图标被其他菜单或窗口遮挡，无法核实点击目标；已展开，未发送点击。"; self.showHelpPanel(); return
            }
            let point = CGPoint(x: fresh.frame.midX, y: fresh.frame.midY)
            guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
                  let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
                self.status = "无法创建点击事件；保持展开，请直接操作原生图标。"; self.showHelpPanel(); return
            }
            move.flags = []; down.flags = []; up.flags = []
            move.post(tap: .cghidEventTap); down.post(tap: .cghidEventTap)
            // Mouse-up must be delivered even if the task is cancelled after mouse-down.
            try? await Task.sleep(nanoseconds: 80_000_000)
            up.post(tap: .cghidEventTap)
            if self.token == clickToken { self.status = "已点击核实后的原图标；菜单栏保持展开，第三方菜单不会被浮窗打断。" }
        }
    }
    var toggleShortcutError: String? { context.hotkeys.error(owner: info.id, id: "toggle-native") }
    func makeView() -> AnyView { AnyView(MenuBarOrganizerView(plugin: self)) }
    func makeMenuItems() -> AnyView { AnyView(MenuBarOrganizerMenu(plugin: self)) }
}

private struct OrganizerCaptureView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(plugin.status).font(.callout)
            }
            HStack {
                Button("取消") { plugin.expand() }
                Spacer()
                Button("打开工具箱") { plugin.openToolbox() }
            }.controlSize(.small)
        }.padding(12).fixedSize(horizontal: false, vertical: true)
    }
}

private struct OrganizerHelpView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Menu("权限") {
                    Button("屏幕录制权限") { plugin.requestPermission() }
                    Button("辅助功能权限") { plugin.requestAccessibilityPermission() }
                }
                Button("重试") { plugin.retryOpenShelf() }
                Spacer()
                Button("打开工具箱") { plugin.openToolbox() }
            }.controlSize(.small)
        }.padding(12)
    }
}

private struct ShelfIconFramesKey: PreferenceKey {
    static var defaultValue: [CGWindowID: CGRect] = [:]
    static func reduce(value: inout [CGWindowID: CGRect], nextValue: () -> [CGWindowID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
private struct ShelfRowFramesKey: PreferenceKey {
    static var defaultValue: [Bool: CGRect] = [:]
    static func reduce(value: inout [Bool: CGRect], nextValue: () -> [Bool: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ShelfPanelView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    @State private var iconFrames: [CGWindowID: CGRect] = [:]
    @State private var rowFrames: [Bool: CGRect] = [:]
    @State private var draggedID: CGWindowID?
    @State private var dragPoint: CGPoint?
    @State private var selectedID: CGWindowID?
    @State private var hiddenPage = 0
    @State private var visiblePage = 0
    let icons: [ShelfIcon]
    let outside: [ShelfIcon]
    let width: CGFloat
    let onExpand: () -> Void
    let onMove: (CGWindowID, Bool) -> Void
    let onReorder: (CGWindowID, CGWindowID) -> Void
    let onClick: (CGWindowID) -> Void
    let onOpenToolbox: () -> Void
    private func thumbnail(_ icon: ShelfIcon) -> some View {
        Group {
            if let image = icon.image {
                Image(decorative: image, scale: 2).renderingMode(.original)
                    .resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo.badge.exclamationmark").resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .frame(width: MenuBarPopoverLayout.tile, height: MenuBarPopoverLayout.tile)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
    private func finishDrag(_ id: CGWindowID, at point: CGPoint) {
        draggedID = nil; dragPoint = nil
        guard let action = MenuBarOrganizerPlugin.shelfDrop(source: id, at: point,
            hidden: icons.map(\.id), visible: outside.map(\.id),
            hiddenRow: rowFrames[true] ?? .null, visibleRow: rowFrames[false] ?? .null,
            iconFrames: iconFrames) else { return }
        switch action {
        case .move(let source, let hidden): onMove(source, hidden)
        case .reorder(let source, let target): onReorder(source, target)
        }
    }
    @ViewBuilder
    private func iconButton(_ icon: ShelfIcon, index: Int, hidden: Bool) -> some View {
        let button = Button {
            if plugin.allowsPanelEditing { selectedID = icon.id }
            else { onClick(icon.id) }
        } label: { thumbnail(icon) }
        .buttonStyle(.plain)
        .background(selectedID == icon.id ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedID == icon.id ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .scaleEffect(draggedID == icon.id ? 1.08 : 1)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ShelfIconFramesKey.self,
                       value: [icon.id: proxy.frame(in: .named("shelf"))])
        })
        .accessibilityLabel("\(hidden ? "收纳" : "可见")图标 \(index + 1)")
        .accessibilityIdentifier("menu-bar-icon-\(icon.id)")
        .overlay(alignment: .bottomTrailing) {
            if icon.availability == .occluded {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                    .padding(3).background(.regularMaterial, in: Circle()).allowsHitTesting(false)
            }
        }
        .help(icon.availability == .occluded ? "已保留此图标；采集时原图标被刘海遮挡，点击或移动前将重新核实安全位置。" : icon.image == nil ? "缩略图暂不可用；此项仍保留，未删除或移出常驻区。可展开原生菜单栏查看。" : plugin.allowsPanelEditing ? "选择后用下方按钮移区或排序；也可拖动" : "点击展开并尝试打开原生图标")
        .contextMenu {
            if plugin.allowsPanelEditing { Button(hidden ? "移出收纳区" : "移入收纳区") { onMove(icon.id, !hidden) } }
        }
        if plugin.allowsPanelEditing {
            button.highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("shelf"))
                .onChanged { value in draggedID = icon.id; dragPoint = value.location }
                .onEnded { value in finishDrag(icon.id, at: value.location) })
        } else {
            button
        }
    }
    private func pageControls(count: Int, page: Int, columns: Int, hidden: Bool) -> some View {
        let pages = max(1, (count + columns * 2 - 1) / (columns * 2))
        return HStack(spacing: 10) {
            Button {
                if hidden { hiddenPage -= 1 } else { visiblePage -= 1 }
            } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0).accessibilityLabel(hidden ? "上一页收纳图标" : "上一页常驻图标")
            Text("\(page + 1) / \(pages)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button {
                if hidden { hiddenPage += 1 } else { visiblePage += 1 }
            } label: { Image(systemName: "chevron.right") }
                .disabled(page + 1 >= pages).accessibilityLabel(hidden ? "下一页收纳图标" : "下一页常驻图标")
        }.buttonStyle(.borderless).controlSize(.small)
    }
    private func iconGrid(_ items: [ShelfIcon], range: Range<Int>, columns: Int, hidden: Bool) -> some View {
        let gridColumns = Array(repeating: GridItem(.fixed(MenuBarPopoverLayout.tile), spacing: MenuBarPopoverLayout.gap), count: columns)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: MenuBarPopoverLayout.gap) {
            ForEach(Array(range), id: \.self) { index in
                iconButton(items[index], index: index, hidden: hidden)
            }
        }
    }
    private func row(_ items: [ShelfIcon], hidden: Bool) -> some View {
        let columns = MenuBarPopoverLayout.columns(width: width)
        let page = hidden ? hiddenPage : visiblePage
        let range = MenuBarPopoverLayout.pageRange(count: items.count, page: page, columns: columns)
        let highlight = dragPoint.map { rowFrames[hidden]?.contains($0) == true } ?? false
        return VStack(spacing: 4) {
            iconGrid(items, range: range, columns: columns, hidden: hidden)
            if items.count > columns * 2 { pageControls(count: items.count, page: page, columns: columns, hidden: hidden) }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ShelfRowFramesKey.self, value: [hidden: proxy.frame(in: .named("shelf"))])
        })
        .background(highlight ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
    private var selectedItems: [ShelfIcon] { icons.contains(where: { $0.id == selectedID }) ? icons : outside }
    private func reorderSelection(offset: Int) {
        guard let selectedID, let index = selectedItems.firstIndex(where: { $0.id == selectedID }), selectedItems.indices.contains(index + offset) else { return }
        onReorder(selectedID, selectedItems[index + offset].id)
    }
    private func canReorder(offset: Int) -> Bool {
        guard let selectedID, let index = selectedItems.firstIndex(where: { $0.id == selectedID }) else { return false }
        return selectedItems.indices.contains(index + offset)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("收纳区 · \(icons.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if plugin.allowsPanelEditing {
                    Text("选择图标调整").font(.caption2).foregroundStyle(.secondary)
                }
            }
            row(icons, hidden: true)
            if !outside.isEmpty {
                Divider()
                Text("常驻图标 · \(outside.count)").font(.caption2).foregroundStyle(.secondary)
                row(outside, hidden: false)
            }
            if plugin.allowsPanelEditing {
                Divider()
                HStack(spacing: 8) {
                    Button(selectedID.map { id in icons.contains(where: { $0.id == id }) ? "移到常驻区" : "移到收纳区" } ?? "选择图标") {
                        if let selectedID { onMove(selectedID, !icons.contains(where: { $0.id == selectedID })) }
                    }.disabled(selectedID == nil)
                    Button("前移") { reorderSelection(offset: -1) }.disabled(!canReorder(offset: -1))
                    Button("后移") { reorderSelection(offset: 1) }.disabled(!canReorder(offset: 1))
                    Spacer(minLength: 0)
                }.controlSize(.small)
                Text("被刘海遮挡或系统拒绝的图标无法可靠移动，会保持展开并说明原因。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if (icons + outside).contains(where: { $0.availability == .occluded }) {
                Text("⚠︎ 标记表示采集时原图标被刘海遮挡，图标仍保留；无法确认安全位置时会保持展开。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if outside.contains(where: { $0.image == nil }) {
                Text("部分缩略图暂不可用，已保留对应图标；与刘海遮挡或移区失败不同。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 8) {
                Button(plugin.allowsPanelEditing ? "完成编辑" : "编辑") {
                    selectedID = nil
                    if plugin.allowsPanelEditing { plugin.allowsPanelEditing = false } else { plugin.beginPanelEditing() }
                }
                Button("⌘ 排列") { onExpand() }.help("展开后按住 ⌘，在原生菜单栏拖动图标")
                Spacer(minLength: 0)
                Button("打开工具箱") { onOpenToolbox() }.help("打开菜单栏收纳的编辑设置")
            }.controlSize(.small)
        }.padding(10)
            .coordinateSpace(name: "shelf")
            .accessibilityIdentifier("menu-bar-shelf-popover")
            .onPreferenceChange(ShelfIconFramesKey.self) { iconFrames = $0 }
            .onPreferenceChange(ShelfRowFramesKey.self) { rowFrames = $0 }
    }
}

private struct MenuBarOrganizerView: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("菜单栏收纳", systemImage: "rectangle.3.group").font(.headline)
                    Spacer()
                    Text(plugin.visibility.state == .collapsing ? "正在收起" : plugin.isCollapsed ? "已收起" : plugin.isOrganizing ? "已展开" : "未启用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("普通点击", selection: Binding(get: { plugin.presentationMode }, set: plugin.setPresentationMode)) {
                    ForEach(OrganizerPresentationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("原生展开无需录屏或辅助功能权限；点击后直接操作真实图标。刘海或菜单栏拥挤时，展开也可能显示不全。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if plugin.isOrganizing {
                        Button(plugin.presentationMode == .native ? (plugin.isCollapsed ? "展开原生图标" : "收起原生图标") : "打开 / 关闭图标面板") {
                            plugin.presentationMode == .native ? plugin.toggleNative() : plugin.openShelf()
                        }.buttonStyle(.borderedProminent)
                        Button("排列原生图标…") { plugin.arrangeNativeIcons() }
                        Spacer()
                        Button("关闭功能") { plugin.turnOff() }
                    } else {
                        Button("启用菜单栏收纳") { plugin.enable() }.buttonStyle(.borderedProminent)
                    }
                }
                Text(plugin.status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("手动按住 ⌘ 将图标拖到分隔符左侧；完成后点击收起。不会按数量自动整理，也不会在原生菜单操作中自动收起。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("高级 · 图标面板与布局编辑", isExpanded: $plugin.showsAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("图标面板需要屏幕录制权限，代点或移动需要辅助功能权限；只在主动打开时采集。外点 / Esc 关闭浮窗并清除缓存，已收起的原生图标保持隐藏；显式展开或失败才恢复展开。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(plugin.isCapturing ? "取消图标采集" : "打开 / 关闭图标面板") { plugin.openShelf() }.disabled(!plugin.isOrganizing)
                            Menu("权限与帮助") {
                                Button("屏幕录制权限") { plugin.requestPermission() }
                                Button("辅助功能权限") { plugin.requestAccessibilityPermission() }
                            }
                        }
                        Toggle("允许浮窗调整真实图标（本次运行）", isOn: $plugin.allowsPanelEditing)
                            .toggleStyle(.checkbox)
                        HStack {
                            Stepper("保留 \(plugin.visibleLimit) 个可见图标", value: Binding(
                                get: { plugin.visibleLimit }, set: { plugin.setVisibleLimit($0) }), in: 1...30)
                            Button("主动按数量整理") { plugin.applyVisibleLimit() }.disabled(!plugin.isOrganizing)
                        }
                        Text("数量整理会逐个移动真实图标；只有点击此按钮才执行。失败保持展开；也可完全使用原生 ⌘ 拖动。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
                HStack {
                    Text("展开 / 收起 ⌃⌥⌘H").foregroundStyle(.secondary)
                    Spacer()
                    Text("紧急展开 ⌃⌥⌘R").foregroundStyle(.secondary)
                }.font(.caption)
                if let error = plugin.toggleShortcutError {
                    Text("展开 / 收起快捷键不可用：\(error)").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct MenuBarOrganizerMenu: View {
    @ObservedObject var plugin: MenuBarOrganizerPlugin
    var body: some View {
        Button(plugin.isOrganizing ? "关闭菜单栏收纳" : "启用菜单栏收纳") { plugin.isOrganizing ? plugin.turnOff() : plugin.enable() }
        if plugin.isOrganizing {
            Button(plugin.isCollapsed ? "展开原生图标" : "收起原生图标") { plugin.toggleNative() }
            Button("排列原生图标…") { plugin.arrangeNativeIcons() }
            Button("打开 / 关闭图标面板…") { plugin.openShelf() }
        }
    }
}
