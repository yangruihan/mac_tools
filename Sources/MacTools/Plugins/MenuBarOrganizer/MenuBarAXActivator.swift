import AppKit
import ApplicationServices

/// Semantic actions only; no event injection or private API.
enum MenuBarAXActivator {
    struct Reply {
        let outcome: MenuBarActionOutcome
        let supportedActions: [String]
        var rawError: Int32? = nil
        var refusalReason: String? = nil
    }
    static func activate(_ target: MenuBarStatusTarget, deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(5))) -> Reply {
        func refuse(_ reason: String, actions: [String] = []) -> Reply {
            Reply(outcome: .refused, supportedActions: actions, refusalReason: reason)
        }
        guard AXIsProcessTrusted() else { return refuse("辅助功能授权不可用。") }
        guard target.application != nil, target.application == MenuBarApplicationIdentity.current(pid: target.pid) else {
            return refuse("图标所属应用已变化或无法核实。")
        }
        guard geometryCurrent(target) else { return refuse("图标布局已变化，请重新采集。") }
        let app = AXUIElementCreateApplication(target.pid)
        guard let extras = attribute(app, kAXExtrasMenuBarAttribute as CFString, deadline: deadline),
              CFGetTypeID(extras) == AXUIElementGetTypeID() else { return refuse("此应用未提供可核实的辅助功能菜单栏。") }
        let bar = extras as! AXUIElement
        guard let children = attribute(bar, kAXChildrenAttribute as CFString, deadline: deadline) as? [AXUIElement],
              children.count <= 128 else { return refuse("此应用的辅助功能图标列表不可用或过多。") }
        var matches: [AXUIElement] = []
        for element in children {
            guard prepare(element, deadline: deadline) else { return refuse("辅助功能查询已停止。") }
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == target.pid,
                  let role = attribute(element, kAXRoleAttribute as CFString, deadline: deadline) as? String,
                  [kAXMenuBarItemRole as String, kAXButtonRole as String].contains(role),
                  let frame = frame(element, deadline: deadline) else { continue }
            if MenuBarIconActivation.hitMatches(frame, window: target.frame) { matches.append(element) }
        }
        guard matches.count == 1, let element = matches.first else {
            return refuse(matches.isEmpty ? "未找到此图标的可核实辅助功能项。" : "多个辅助功能项匹配此图标，无法唯一确认。")
        }
        var actions: CFArray?
        guard prepare(element, deadline: deadline), AXUIElementCopyActionNames(element, &actions) == .success,
              let names = actions as? [String] else { return refuse("无法读取此图标的辅助功能动作。") }
        guard let action = [kAXShowMenuAction as String, kAXPressAction as String].first(where: names.contains) else {
            return refuse("此图标不支持辅助功能打开。", actions: names)
        }
        // Revalidate both independent identities immediately before the single action.
        var owner: pid_t = 0
        guard target.application == MenuBarApplicationIdentity.current(pid: target.pid), geometryCurrent(target),
              AXUIElementGetPid(element, &owner) == .success, owner == target.pid,
              let latest = frame(element, deadline: deadline), MenuBarIconActivation.hitMatches(latest, window: target.frame) else {
            return refuse("动作前图标身份或布局已变化。", actions: names)
        }
        guard prepare(element, deadline: deadline) else { return refuse("辅助功能动作已停止。", actions: names) }
        let error = AXUIElementPerformAction(element, action as CFString)
        return Reply(outcome: classify(error), supportedActions: names, rawError: error.rawValue,
                     refusalReason: classify(error) == .refused ? "原应用不支持或拒绝此辅助功能动作（\(error.rawValue)）。" : nil)
    }
    static func classify(_ error: AXError) -> MenuBarActionOutcome {
        switch error {
        case .success: return .accepted
        case .actionUnsupported, .notImplemented, .invalidUIElement, .illegalArgument, .apiDisabled: return .refused
        default: return .uncertain
        }
    }
    static func geometryMatches(_ target: MenuBarStatusTarget, current: MenuBarStatusTarget) -> Bool {
        target.id == current.id && target.pid == current.pid && target.application == current.application
            && [current.frame.minX, current.frame.minY, current.frame.width, current.frame.height].allSatisfy { $0.isFinite }
            && abs(target.frame.minX - current.frame.minX) < 1 && abs(target.frame.minY - current.frame.minY) < 1
            && abs(target.frame.width - current.frame.width) < 1 && abs(target.frame.height - current.frame.height) < 1
    }
    private static func geometryCurrent(_ target: MenuBarStatusTarget) -> Bool {
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let owned = rows.filter { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.id
            && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.pid }
        guard owned.count == 1, let bounds = owned[0][kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
        return geometryMatches(target, current: MenuBarStatusTarget(id: target.id, pid: target.pid, frame: frame,
            onScreen: false, application: MenuBarApplicationIdentity.current(pid: target.pid)))
    }
    private static func prepare(_ element: AXUIElement, deadline: ContinuousClock.Instant) -> Bool {
        guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { return false }
        return AXUIElementSetMessagingTimeout(element, Float(min(0.25, seconds))) == .success
    }
    private static func attribute(_ element: AXUIElement, _ name: CFString, deadline: ContinuousClock.Instant) -> CFTypeRef? {
        guard prepare(element, deadline: deadline) else { return nil }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    private static func frame(_ element: AXUIElement, deadline: ContinuousClock.Instant) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute as CFString, deadline: deadline),
              let s = attribute(element, kAXSizeAttribute as CFString, deadline: deadline),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

/// Metadata-only observation; no desktop pixels or menu titles are collected.
@MainActor
final class MenuBarReactionObserver {
    struct Window: Equatable {
        let id: UInt32; let pid: Int32; let level: Int
    }
    private var baseline: Set<UInt32> = []
    private var observed: Set<UInt32> = []
    private var owner: Int32?
    private var activeBefore: Int32?
    static func windows() -> [Window] {
        let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.compactMap {
            guard let id = ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let level = $0[kCGWindowLayer as String] as? Int else { return nil }
            return Window(id: id, pid: pid, level: level)
        }
    }
    func begin(_ target: MenuBarStatusTarget) {
        owner = target.pid
        baseline = Set(Self.windows().filter { $0.pid == target.pid }.map(\.id))
        observed = []
        activeBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    func reaction(_ target: MenuBarStatusTarget) -> Bool {
        guard owner == target.pid else { return false }
        let added = Self.windows().filter { $0.pid == target.pid && !baseline.contains($0.id) }
        // Only native menu-level windows may establish a closable interface.
        // App activation or an incidental ordinary window proves a reaction,
        // but never proves that a third-party menu has finished.
        observed.formUnion(added.filter { $0.level == Int(CGWindowLevelForKey(.popUpMenuWindow)) }.map(\.id))
        return !added.isEmpty || (activeBefore != target.pid && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid)
    }
    func interfaceState(_ target: MenuBarStatusTarget) -> MenuBarInterfaceState {
        guard owner == target.pid else { return .unknown }
        let current = Set(Self.windows().filter { $0.pid == target.pid }.map(\.id))
        if !observed.isEmpty { return observed.isDisjoint(with: current) ? .closed : .open }
        // An accepted action is not evidence that its menu has already closed.
        return .unknown
    }
}

