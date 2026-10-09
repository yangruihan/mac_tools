import SwiftUI
import Carbon
import ScreenCaptureKit
import ApplicationServices
import Combine

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
    @Published private(set) var allowsPanelEditing = false
    @Published var showsAdvancedOptions = false
    @Published var showsNotchDirectory = false
    @Published var showsAllDirectoryItems = false
    @Published private(set) var directoryItems: [MenuBarDirectoryItem] = []
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
    private var operationCoordinator: MenuBarOperationCoordinator?
    let nativeRevealPreviewEnabled: Bool
    @Published private(set) var nativeRevealState: MenuBarNativeRevealController.State = .idle
    @Published private(set) var nativeRevealStatus = "露出用于手动排列；完成后再打开图标菜单。"
    private var nativeRevealController: MenuBarNativeRevealController?
    private var nativeRevealSubscriptions: [AnyCancellable] = []
    private var nativeRevealWork: Task<Void, Never>?
    var nativeRevealBlocksLayout: Bool { nativeRevealState != .idle }
    // ToolPlugin lifecycle/UI callbacks run on the main thread. Keep this
    // boundary explicit without changing actor isolation of pure layout helpers.
    private var activationBlocksLayout: Bool {
        nativeRevealBlocksLayout || MainActor.assumeIsolated { operationCoordinator?.blocksLayout == true }
    }

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
        nativeRevealPreviewEnabled = Bundle.main.object(forInfoDictionaryKey: "MacToolsNativeRevealPreviewEnabled") as? Bool == true
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
        #if ICE_MENU_BAR_CANDIDATE
        // Candidate exposes only the owned Ice session; never restore formal opt-in.
        #else
        if let data = context.settings.data(forKey: "visibleLimit"), let value = try? JSONDecoder().decode(Int.self, from: data) {
            visibleLimit = min(30, max(1, value))
        }
        if let data = context.settings.data(forKey: "optedIn"), (try? JSONDecoder().decode(Bool.self, from: data)) == true { enable() }
        #endif
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
            perform: { [weak self] in MainActor.assumeIsolated { self?.operationCoordinator?.releaseUnmovedInteraction() }; self?.expand() }),
            HotKeyAction(id: "toggle-native", chord: KeyChord(key: "H", modifiers: UInt32(controlKey | optionKey | cmdKey)),
                         perform: { [weak self] in self?.toggleNative() })])
        environmentMonitor = MenuBarEnvironmentMonitor { [weak self] change in self?.environmentChanged(change) }
        environmentMonitor?.start()
        status = "已启用。请将收纳按钮留在分隔符右侧，再用 ⌘ 拖动需要收纳的图标。"
        saveOptIn(true)
        Self.prepareMainStatusPosition()
        if nativeRevealPreviewEnabled {
            MainActor.assumeIsolated {
                do { _ = try nativeRevealEngine() } // Load recovery before accepting any layout action; no length write.
                catch { nativeRevealStatus = error.localizedDescription }
            }
        }
    }
    func deactivate() {
        MainActor.assumeIsolated { nativeRevealController?.shutdown() }
        nativeRevealWork?.cancel(); nativeRevealWork = nil
        nativeRevealSubscriptions = []; nativeRevealController = nil; nativeRevealState = .idle
        directoryItems = []; showsNotchDirectory = false
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
        if change == .frontApplicationChanged {
            // AX activation itself can change the foreground app. Do not
            // invalidate that accepted path when no width session is active.
            guard nativeRevealPreviewEnabled,
                  [.preparing, .revealing, .ready, .restoring].contains(nativeRevealState) else { return }
            _ = MainActor.assumeIsolated { nativeRevealController?.requestEnd(.environmentChanged) }
            environment.receive(change); directoryItems = []; return
        }
        _ = MainActor.assumeIsolated { nativeRevealController?.requestEnd(.environmentChanged) }
        MainActor.assumeIsolated { operationCoordinator?.invalidate() }
        environment.receive(change)
        directoryItems = []
        environmentWork?.cancel(); environmentWork = nil
        guard isOrganizing else { return }
        if change == .applicationsChanged {
            work?.cancel(); work = nil
            if isCapturing || visibility.state == .collapsing { expand() }
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
                                    ("编辑布局 · 手动排列…", #selector(arrangeFromMenu)),
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
        guard isOrganizing else { return }
        guard !nativeRevealBlocksLayout else { status = "临时露出处理中；请从工具箱完成、取消，或用紧急展开恢复。"; return }
        MainActor.assumeIsolated { operationCoordinator?.releaseUnmovedInteraction() }
        if visibility.state == .collapsed || visibility.state == .collapsing || isCapturing { expand() }
        else { closePanel(); collapse() }
    }
    func arrangeNativeIcons() {
        MainActor.assumeIsolated { operationCoordinator?.releaseUnmovedInteraction() }
        expand()
        if isOrganizing { status = "手动编辑：在屏幕顶部按住 ⌘ 拖动；│ 左侧收纳、右侧常驻，同侧拖动换序。完成后点击收起。" }
    }
    func openShelf() {
        guard isOrganizing else { return }
        guard !nativeRevealBlocksLayout else { status = "请先完成或取消临时露出。"; return }
        MainActor.assumeIsolated { operationCoordinator?.releaseUnmovedInteraction() }
        if shelfPopover != nil { dismissShelf() }
        else if isCapturing { expand() }
        else { hideIntoPanel() }
    }
    func retryOpenShelf() { MainActor.assumeIsolated { operationCoordinator?.releaseUnmovedInteraction() }; expand(); hideIntoPanel() }
    func expand() {
        _ = MainActor.assumeIsolated { nativeRevealController?.requestEnd(.cancelled) }
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
        guard visibility.state == .expanded, !environment.sleeping,
              !activationBlocksLayout else { return }
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
    func refreshNotchDirectory() {
        guard isOrganizing, !environment.sleeping else { directoryItems = []; return }
        let displays = MenuBarDisplay.current()
        guard let geometry = placement(), let display = displays.first(where: { $0.quartzFrame == geometry.screen }) else {
            directoryItems = []; status = "无法确认菜单栏所在屏幕，请在布局稳定后读取。"; return
        }
        directoryItems = MenuBarItemDirectory.build(windows: statusTargets(), displays: displays,
            displayID: display.id, excludingPID: ProcessInfo.processInfo.processIdentifier,
            applicationName: { NSRunningApplication(processIdentifier: $0)?.localizedName })
        showsNotchDirectory = true
        status = "已读取 \(directoryItems.count) 个图标位置，无需截图；选择图标可尝试辅助功能打开。"
    }
    func activateDirectoryItem(_ id: CGWindowID) {
        guard !nativeRevealBlocksLayout else { status = "请先完成或取消临时露出，再打开图标菜单。"; return }
        guard isOrganizing, !environment.sleeping,
              let item = directoryItems.first(where: { $0.id == id }) else { return }
        guard accessibilityReady() else {
            status = "辅助功能授权不可用；名称列表仍可读取，未执行动作。"; return
        }
        activateIdentity(item.identity, presentFailurePopover: false)
    }
    @MainActor
    private func nativeRevealEngine() throws -> MenuBarNativeRevealController {
        if let nativeRevealController { return nativeRevealController }
        guard nativeRevealPreviewEnabled, isOrganizing, let control else { throw MenuBarNativeObservationFailure.recovery }
        let observer = MenuBarNativeLiveObserver(ownedWindows: { [weak self] in
            guard let self, self.isOrganizing, !self.environment.sleeping,
                  let control = self.control?.button?.window, let divider = self.divider?.button?.window,
                  control.isVisible, control.windowNumber > 0, divider.windowNumber > 0 else { throw MenuBarNativeObservationFailure.display }
            return (UInt32(control.windowNumber), UInt32(divider.windowNumber))
        }, generation: { [weak self] in self?.environment.generation ?? UUID() },
           diagnostic: { [weak self] transaction, phase, sample in
               self?.nativeRevealController?.recordLiveObservation(transaction: transaction, phase: phase, sample: sample)
           })
        let driver = try MenuBarOwnedStatusItemWidthDriver(item: control, itemKey: Self.controlName,
            generation: { [weak self] in self?.environment.generation ?? UUID() },
            observe: { [weak self] identity in
                let transaction = self?.nativeRevealController?.diagnostic.transaction
                return try await observer.observe(identity, diagnosticSession: transaction)
            }, restorationSafety: { [weak self] in
                let transaction = self?.nativeRevealController?.diagnostic.transaction
                try await observer.verifyRestorationSafety(diagnosticSession: transaction)
            })
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let journal = MenuBarOwnedWidthFileJournal(url: directory.appendingPathComponent("com.ryanai.mactools/menu-bar-owned-width-preview.json"))
        let diagnosticURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mactools-native-reveal-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).json")
        let engine = MenuBarNativeRevealController(driver: driver, journal: journal, diagnosticURL: diagnosticURL)
        nativeRevealController = engine
        nativeRevealSubscriptions = [engine.$state.sink { [weak self] in self?.nativeRevealState = $0 },
                                     engine.$status.sink { [weak self] in self?.nativeRevealStatus = $0 }]
        return engine
    }
    func beginNativeReveal(_ id: CGWindowID) {
        guard nativeRevealPreviewEnabled, isOrganizing, !environment.sleeping,
              visibility.state == .expanded, !activationBlocksLayout,
              let item = directoryItems.first(where: { $0.id == id }) else {
            status = "请先展开原生图标并刷新目录，或结束上一项操作。"; return
        }
        guard accessibilityReady() else { return }
        nativeRevealWork = Task { @MainActor [weak self] in
            guard let self else { return }
            do { _ = await (try self.nativeRevealEngine()).begin(item.identity) }
            catch { self.nativeRevealStatus = error.localizedDescription }
        }
    }
    func finishNativeReveal(cancel: Bool) {
        nativeRevealWork = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.nativeRevealController?.end(cancel ? .cancelled : .completed)
            if self.nativeRevealState == .idle { self.refreshNotchDirectory() }
        }
    }
    func recoverNativeReveal() {
        guard nativeRevealPreviewEnabled, isOrganizing else { return }
        nativeRevealWork = Task { @MainActor [weak self] in
            guard let self else { return }
            do { await (try self.nativeRevealEngine()).recoverOwnWidth() }
            catch { self.nativeRevealStatus = error.localizedDescription }
        }
    }
    func toolboxWillClose() { _ = MainActor.assumeIsolated { nativeRevealController?.requestEnd(.cancelled) } }
    // Compatibility entry points cannot inject input, even when called directly.
    private func automaticLayoutUnsupported() {
        status = MenuBarOperationFailure.movementUnavailable.message
    }
    func beginPanelEditing() { automaticLayoutUnsupported() }
    @MainActor
    func postDrag(from source: CGPoint, to destination: CGPoint, token moveToken: UUID) async -> Bool {
        automaticLayoutUnsupported(); return false
    }
    func moveIcon(_ id: CGWindowID, intoShelf: Bool) { automaticLayoutUnsupported() }
    func applyVisibleLimit() { automaticLayoutUnsupported() }
    func reorderIcon(_ id: CGWindowID, nextTo targetID: CGWindowID) { automaticLayoutUnsupported() }
    private func removePopoverMonitors() {
        popoverMonitors.forEach(NSEvent.removeMonitor); popoverMonitors = []
        if let popoverDeactivateObserver { NotificationCenter.default.removeObserver(popoverDeactivateObserver) }
        popoverDeactivateObserver = nil
    }
    private func closePanel() {
        MainActor.assumeIsolated { operationCoordinator?.invalidate() }
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
        guard isOrganizing, !environment.sleeping, !activationBlocksLayout else { return }
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
        let view = ShelfPanelView(icons: icons, outside: visibleIcons, width: width,
            onExpand: { [weak self] in self?.arrangeNativeIcons() },
            onClick: { [weak self] id in Task { @MainActor in self?.activateIcon(id) } },
            onOpenToolbox: { [weak self] in self?.openToolbox() })
        showPopover(AnyView(view), width: width)
    }
    func openToolbox() {
        expand(); showsAdvancedOptions = true
        context.openToolbox()
    }
    @MainActor
    private func activationEngine() -> MenuBarOperationCoordinator {
        if let operationCoordinator { return operationCoordinator }
        let driver = MenuBarLiveOperationDriver(resolve: { [weak self] identity in
            guard let self, self.isOrganizing else { throw MenuBarOperationFailure.cancelled }
            let result = MenuBarIconIdentity.identify(identity, windows: self.statusTargets(), preferredDisplay: self.placement()?.screen)
            guard let target = result.target else { throw result.failure ?? .unverifiedIdentity }
            return target
        })
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let journal = MenuBarFileRecoveryJournal(url: directory.appendingPathComponent("com.ryanai.mactools/menu-bar-recovery.json"))
        let engine = MenuBarOperationCoordinator(driver: driver, journal: journal)
        operationCoordinator = engine
        return engine
    }
    func activateIcon(_ id: CGWindowID) {
        guard !allowsPanelEditing, isCollapsed,
              icons.contains(where: { $0.id == id }) || visibleIcons.contains(where: { $0.id == id }) else { return }
        guard let identity = (icons + visibleIcons).first(where: { $0.id == id })?.identity else {
            expand(); status = MenuBarIconResolution.Failure.unverifiedIdentity.message; showHelpPanel(); return
        }
        guard accessibilityReady() else {
            expand(); status = "已展开原生图标，请直接点击；图标面板代点需辅助功能权限。"; showHelpPanel(); return
        }
        activateIdentity(identity, presentFailurePopover: true)
    }
    private func activateIdentity(_ identity: MenuBarIconIdentity, presentFailurePopover: Bool) {
        // Both thumbnail and metadata entries use the same semantic-only driver.
        closePanel()
        _ = visibility.dismissPopover()
        let clickToken = token
        work = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self, self.token == clickToken, self.isOrganizing else { return }
            let coordinator = self.activationEngine()
            // This is a new explicit request, not an automatic retry.
            coordinator.releaseUnmovedInteraction()
            let result = await coordinator.activate(identity)
            guard self.token == clickToken, self.isOrganizing else { return }
            switch result {
            case .observed: self.status = "原应用已有响应；第三方菜单不会被浮窗打断。"
            case .dispatched: self.status = "已发送核实后的原图标动作；尚未确认界面响应，不会自动补点。"
            case .uncertain: self.status = "原应用回应不确定；菜单可能已打开，未重复点击。请查看原菜单或从工具箱重试。"
            case .failed(let reason):
                self.status = reason
                if presentFailurePopover && coordinator.state == .idle {
                    self.divider?.length = NSStatusItem.variableLength; self.visibility.expand()
                    self.showHelpPanel()
                }
                return
            }
            // Observe without stealing focus or sending more input.
            for _ in 0..<20 {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard self.token == clickToken else { return }
                await coordinator.settle()
                if coordinator.state == .idle { return }
            }
        }
    }
    var toggleShortcutError: String? { context.hotkeys.error(owner: info.id, id: "toggle-native") }
    func makeView() -> AnyView {
        #if ICE_MENU_BAR_CANDIDATE
        return AnyView(MenuBarIceCandidateProductView())
        #elseif ICE_MENU_BAR_INTEGRATED
        return AnyView(VStack(alignment:.leading,spacing:20) {
            MenuBarIceCandidateProductView()
            DisclosureGroup("原有收纳设置") { MenuBarOrganizerView(plugin: self) }
        })
        #else
        return AnyView(MenuBarOrganizerView(plugin: self))
        #endif
    }
    func makeMenuItems() -> AnyView {
        #if ICE_MENU_BAR_CANDIDATE
        return AnyView(Button("打开 Ice 候选") { self.openToolbox() })
        #elseif ICE_MENU_BAR_INTEGRATED
        return AnyView(VStack {
            Button("打开 Ice 菜单栏试用") { self.openToolbox() }
            MenuBarOrganizerMenu(plugin: self)
        })
        #else
        return AnyView(MenuBarOrganizerMenu(plugin: self))
        #endif
    }
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
                Button("展开原生图标手动操作") { plugin.arrangeNativeIcons() }
                Spacer()
                Button("打开工具箱") { plugin.openToolbox() }
            }.controlSize(.small)
        }.padding(12)
    }
}

private struct ShelfPanelView: View {
    @State private var hiddenPage = 0
    @State private var visiblePage = 0
    let icons: [ShelfIcon]
    let outside: [ShelfIcon]
    let width: CGFloat
    let onExpand: () -> Void
    let onClick: (CGWindowID) -> Void
    let onOpenToolbox: () -> Void
    private func iconButton(_ icon: ShelfIcon, index: Int, hidden: Bool) -> some View {
        Button { onClick(icon.id) } label: {
            Group {
                if let image = icon.image {
                    Image(decorative: image, scale: 2).renderingMode(.original).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo.badge.exclamationmark").resizable().aspectRatio(contentMode: .fit).foregroundStyle(.secondary)
                }
            }.frame(width: 44, height: 44)
                .frame(width: MenuBarPopoverLayout.tile, height: MenuBarPopoverLayout.tile)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(hidden ? "收纳" : "可见")图标 \(index + 1)")
            .accessibilityIdentifier("menu-bar-icon-\(icon.id)")
            .overlay(alignment: .bottomTrailing) {
                if icon.availability == .occluded {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                        .padding(3).background(.regularMaterial, in: Circle()).allowsHitTesting(false)
                }
            }
            .help("尝试辅助功能打开；不支持时请展开原生图标手动操作。")
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
        return VStack(spacing: 4) {
            iconGrid(items, range: range, columns: columns, hidden: hidden)
            if items.count > columns * 2 { pageControls(count: items.count, page: page, columns: columns, hidden: hidden) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("收纳区 · \(icons.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            row(icons, hidden: true)
            if !outside.isEmpty {
                Divider()
                Text("常驻图标 · \(outside.count)").font(.caption2).foregroundStyle(.secondary)
                row(outside, hidden: false)
            }
            Text("仅自动打开支持辅助功能的图标；不支持的项请在原生栏操作。自动搬移、归位和模拟点击未启用。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("编辑布局 · 手动排列") { onExpand() }
                    .help("在屏幕顶部按住 ⌘ 拖动：分隔符左侧收纳、右侧常驻，同侧拖动换序。")
                Spacer()
                Button("打开工具箱") { onOpenToolbox() }
            }.controlSize(.small)
        }.padding(10).accessibilityIdentifier("menu-bar-shelf-popover")
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
                            .disabled(plugin.nativeRevealBlocksLayout)
                        Button("编辑布局…") { plugin.arrangeNativeIcons() }
                            .accessibilityIdentifier("menu-bar-edit-native-layout")
                            .disabled(plugin.nativeRevealBlocksLayout)
                        Button("刘海图标…") { plugin.refreshNotchDirectory() }
                            .accessibilityIdentifier("menu-bar-open-notch-directory")
                        Spacer()
                        Button("关闭功能") { plugin.turnOff() }
                    } else {
                        Button("启用菜单栏收纳") { plugin.enable() }.buttonStyle(.borderedProminent)
                    }
                }
                Text(plugin.status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if plugin.isOrganizing {
                    MenuBarNativeEditingView(isExpanded: plugin.visibility.state == .expanded,
                                             onFinish: { plugin.toggleNative() })
                        .disabled(plugin.nativeRevealBlocksLayout)
                    if plugin.nativeRevealPreviewEnabled {
                        GroupBox("临时露出 · 预览验收") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(plugin.nativeRevealStatus).font(.callout)
                                Text("只调整自有间隔宽度；核实完整露出后，可在顶部按住 ⌘ 手动排列。完成或取消恢复宽度，保留手动顺序。最多30秒；此期间先完成，再打开图标菜单。")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("完成露出编辑") { plugin.finishNativeReveal(cancel: false) }.disabled(plugin.nativeRevealState != .ready)
                                        .accessibilityIdentifier("menu-bar-finish-native-reveal")
                                    Button("取消露出") { plugin.finishNativeReveal(cancel: true) }.disabled(!plugin.nativeRevealBlocksLayout)
                                        .accessibilityIdentifier("menu-bar-cancel-native-reveal")
                                    Button("核实恢复宽度") { plugin.recoverNativeReveal() }
                                        .accessibilityIdentifier("menu-bar-recover-native-reveal")
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    DisclosureGroup("刘海与收纳图标 · 无需截图", isExpanded: $plugin.showsNotchDirectory) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button("重新读取") { plugin.refreshNotchDirectory() }
                                Toggle("同时显示原生栏位置", isOn: $plugin.showsAllDirectoryItems)
                                    .toggleStyle(.checkbox)
                            }
                            let items = plugin.directoryItems.filter { plugin.showsAllDirectoryItems || $0.position != .nativeBar }
                            if items.isEmpty {
                                Text(plugin.directoryItems.isEmpty ? "点击读取，列出可核实的图标所属应用。" : "当前目录没有刘海或屏外项；可显示全部原生栏位置。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(items) { item in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(item.title).lineLimit(1)
                                                    Text(item.position.title).font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Button("打开") { plugin.activateDirectoryItem(item.id) }
                                                    .accessibilityLabel("通过辅助功能打开 \(item.title)")
                                                    .disabled(plugin.nativeRevealBlocksLayout)
                                                if plugin.nativeRevealPreviewEnabled {
                                                    Button("露出以编辑") { plugin.beginNativeReveal(item.id) }
                                                        .disabled(plugin.nativeRevealBlocksLayout || plugin.visibility.state != .expanded)
                                                        .accessibilityLabel("核实并露出 \(item.title) 以手动排列")
                                                }
                                            }
                                        }
                                    }
                                }.frame(maxHeight: 220)
                            }
                            Text("目录按窗口位置分类，不保证原图标可见。打开使用原图标的辅助功能动作，无需录屏；不支持时不会补点。拖动整理仍需原图标进入可见区。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }
                }
                DisclosureGroup("高级 · 图标面板", isExpanded: $plugin.showsAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("图标面板采集需要屏幕录制权限；仅使用辅助功能打开支持的图标，不模拟点击、不自动搬移或归位。外点 / Esc 清除浮窗缓存，原生收纳保持。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(plugin.isCapturing ? "取消图标采集" : "打开 / 关闭图标面板") { plugin.openShelf() }.disabled(!plugin.isOrganizing)
                            Menu("权限与帮助") {
                                Button("屏幕录制权限") { plugin.requestPermission() }
                                Button("辅助功能权限") { plugin.requestAccessibilityPermission() }
                            }
                        }
                        Text("排列请展开原生菜单栏，按住 ⌘ 手动拖动；本版本不按数量自动整理。")
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
            Button("编辑布局 · 手动排列…") { plugin.arrangeNativeIcons() }
            Button("打开 / 关闭图标面板…") { plugin.openShelf() }
        }
    }
}
