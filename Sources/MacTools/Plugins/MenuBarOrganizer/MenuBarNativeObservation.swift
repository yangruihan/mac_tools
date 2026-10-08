import AppKit
import ApplicationServices

enum MenuBarNativeObservationFailure: String, LocalizedError, MenuBarNativeDiagnosticError {
    case permission, target, topology, display, menu, recovery, overlay, stale, collapsed
    var diagnosticCode: String { "observation.\(rawValue)" }
    var errorDescription: String? {
        switch self {
        case .permission: return "辅助功能授权不可用，未改变宽度。"
        case .target: return "目标身份或辅助功能几何无法唯一核实，请刷新目录。"
        case .topology: return "菜单栏图标集合存在未知身份或显示归属，未继续。"
        case .display: return "原生菜单栏或刘海安全区域无法核实。"
        case .menu: return "前台应用菜单占用无法完整核实，未继续。"
        case .recovery: return "独立恢复入口无法唯一核实或不完整可见。"
        case .overlay: return "目标或恢复入口存在窗口覆盖，未继续。"
        case .stale: return "观测期间环境或几何发生变化，请重新读取。"
        case .collapsed: return "原生菜单栏仍收起或尚未完成展开；请先展开再刷新目录。"
        }
    }
}

/// Pure assembly of public metadata. AX frames are clipped only to their actual
/// CG backing windows, never to safe areas to manufacture visibility.
enum MenuBarNativeObservation {
    struct Context: Equatable {
        let generation: UUID
        let displays: [MenuBarDisplay]
        let windows: [MenuBarStatusTarget]
        let ownerPID: Int32
        let controlID: UInt32
        let dividerID: UInt32
        let frontPID: Int32
        let frontApplication: MenuBarApplicationIdentity
        let overlays: [CGRect]
        var unprovenPixelWindowIDs: [UInt32] = []
    }
    struct Selection {
        let display: MenuBarDisplay
        let control: MenuBarStatusTarget
        let recovery: MenuBarStatusTarget
        let peers: [MenuBarStatusTarget]
    }
    static func select(_ context: Context) throws -> Selection {
        guard Set(context.windows.map(\.id)).count == context.windows.count,
              let control = context.windows.first(where: { $0.id == context.controlID }),
              control.pid == context.ownerPID, control.onScreen, control.application != nil,
              !context.unprovenPixelWindowIDs.contains(control.id),
              let divider = context.windows.first(where: { $0.id == context.dividerID }),
              divider.pid == context.ownerPID, divider.application == control.application else { throw MenuBarNativeObservationFailure.topology }
        guard divider.frame.width <= 64 else { throw MenuBarNativeObservationFailure.collapsed }
        let screens = context.displays.filter { $0.quartzFrame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY)) }
        guard screens.count == 1, let display = screens.first,
              display.safeAreas.count == 2, abs(control.frame.minY - display.quartzFrame.minY) < 1 else {
            throw MenuBarNativeObservationFailure.display
        }
        let row = context.windows.filter { abs($0.frame.minY - display.quartzFrame.minY) < 1 }
        var peers: [MenuBarStatusTarget] = []
        for window in row {
            guard valid(window.frame), window.frame.height < 64, let app = window.application, app.launch.isFinite,
                  !app.bundleID.isEmpty, !app.bundlePath.isEmpty else { throw MenuBarNativeObservationFailure.topology }
            let containing = context.displays.filter { $0.quartzFrame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) }
            if containing.isEmpty {
                guard context.displays.filter({ abs($0.quartzFrame.minY - window.frame.minY) < 1 }).count == 1 else {
                    throw MenuBarNativeObservationFailure.topology
                }
                peers.append(window)
            } else {
                guard containing.count == 1 else { throw MenuBarNativeObservationFailure.display }
                if containing[0].id == display.id { peers.append(window) }
            }
        }
        peers.sort { $0.frame.minX == $1.frame.minX ? $0.id < $1.id : $0.frame.minX < $1.frame.minX }
        let recovery = peers.filter { $0.pid == context.ownerPID && $0.id != context.controlID && $0.id != context.dividerID
            && $0.onScreen && $0.frame.minX >= control.frame.maxX - 1 && $0.application == control.application }
        guard recovery.count == 1 else { throw MenuBarNativeObservationFailure.recovery }
        return Selection(display: display, control: control, recovery: recovery[0], peers: peers)
    }
    static func button(_ frames: [CGRect], matching target: MenuBarStatusTarget) throws -> CGRect {
        let matched = frames.filter { MenuBarIconActivation.hitMatches($0, window: target.frame) }
        guard matched.count == 1 else { throw MenuBarNativeObservationFailure.target }
        let button = matched[0].intersection(target.frame)
        guard valid(button) else { throw MenuBarNativeObservationFailure.target }
        return button
    }
    static func assemble(_ context: Context, identity: MenuBarIconIdentity,
                         targetAX: [CGRect], recoveryAX: [CGRect], menuAX: [CGRect]) throws -> MenuBarNativeRevealPlan.Observation {
        let selection = try select(context), display = selection.display
        let targets = selection.peers.filter { $0.id == identity.windowID && $0.pid == identity.pid && $0.application == identity.application }
        guard targets.count == 1, targets[0].frame.width > 8, targets[0].frame.width < 150,
              targets[0].frame.height < 64 else { throw MenuBarNativeObservationFailure.target }
        let target = targets[0], targetButton = try button(targetAX, matching: target)
        guard !context.unprovenPixelWindowIDs.contains(target.id),
              !context.unprovenPixelWindowIDs.contains(selection.recovery.id) else { throw MenuBarNativeObservationFailure.target }
        let recoveryButton = try button(recoveryAX, matching: selection.recovery)
        let safe = display.quartzSafeAreas.sorted { $0.minX < $1.minX }
        guard safe.count == 2, safe[1].contains(recoveryButton) else { throw MenuBarNativeObservationFailure.recovery }
        guard !menuAX.isEmpty, menuAX.count <= 64, menuAX.allSatisfy({ rect in
            valid(rect) && rect.height < 64 && rect.minX >= safe[0].minX - 1 && rect.maxX <= safe[0].maxX
                && rect.midY >= safe[0].minY && rect.midY <= safe[0].maxY
        }) else { throw MenuBarNativeObservationFailure.menu }
        let menuMaxX = menuAX.map(\.maxX).max()!
        let menu = CGRect(x: safe[0].minX, y: safe[0].minY, width: menuMaxX - safe[0].minX, height: safe[0].height)
        let otherWindows = selection.peers.filter { $0.onScreen && $0.id != target.id && $0.id != selection.recovery.id }.map(\.frame)
        guard !(context.overlays + otherWindows).contains(where: { overlaps($0, targetButton) || overlaps($0, recoveryButton) }),
              !overlaps(menu, recoveryButton) else { throw MenuBarNativeObservationFailure.overlay }
        return .init(generation: context.generation, displayID: display.id, target: target,
            targetButton: targetButton, ownedSpacer: selection.control.frame, recoveryButton: recoveryButton,
            safeAreas: safe, applicationMenu: menu, orderedWindowIDs: selection.peers.map(\.id), peers: selection.peers,
            frontPID: context.frontPID, frontApplication: context.frontApplication, recoveryTarget: selection.recovery)
    }
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }
    private static func valid(_ r: CGRect) -> Bool {
        !r.isNull && !r.isInfinite && r.width > 0 && r.height > 0
            && [r.minX, r.minY, r.width, r.height].allSatisfy { $0.isFinite }
    }
}

/// Bounded, read-only AX IPC. No action names, titles, hit testing or input.
enum MenuBarNativeAXGeometry {
    /// Injection changes no production call: the default transport uses only
    /// the same three bounded public read APIs as before. Tests need no server.
    struct Client {
        var owner: (AXUIElement) -> (AXError, Int32)
        var timeout: (AXUIElement, Float) -> AXError
        var copy: (AXUIElement, String) -> (AXError, CFTypeRef?)
        var application: (Int32) -> MenuBarApplicationIdentity?
        var now: () -> ContinuousClock.Instant = { .now }
        static let live = Client(owner: { element in
            var pid: pid_t = 0; let error = AXUIElementGetPid(element, &pid); return (error, pid)
        }, timeout: { AXUIElementSetMessagingTimeout($0, $1) }, copy: { element, key in
            var value: CFTypeRef?; let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
            return (error, value)
        }, application: MenuBarApplicationIdentity.current)
    }
    static func frames(pid: Int32, extras: Bool, deadline: ContinuousClock.Instant,
                       scope: String? = nil, expectedApplication: MenuBarApplicationIdentity? = nil,
                       client: Client = .live) throws -> [CGRect] {
        let scope = scope ?? (extras ? "extras" : "frontMenu")
        let application = client.application(pid)
        func failure(_ operation: String, _ key: String, _ path: String, _ outcome: String,
                     _ error: AXError? = nil, owner: Int32? = nil, expected: String? = nil,
                     actual: String? = nil, count: Int? = nil) -> MenuBarNativeAXReadFailure {
            var detail = MenuBarNativeRevealDiagnostic.AXReadDetail(scope: scope, pid: pid,
                callerPID: ProcessInfo.processInfo.processIdentifier, application: application,
                expectedApplication: expectedApplication, operation: operation, attribute: key,
                elementPath: path, outcome: outcome, axError: error?.rawValue)
            detail.elementPID = owner; detail.expectedType = expected; detail.actualType = actual; detail.childrenCount = count
            return .init(detail: detail)
        }
        func checkBudget(_ key: String, _ path: String) throws {
            guard !Task.isCancelled else { throw failure("budget", key, path, "cancelled") }
            guard client.now() < deadline else { throw failure("budget", key, path, "deadline") }
        }
        func attribute(_ element: AXUIElement, _ key: String, _ path: String) throws -> CFTypeRef {
            try checkBudget(key, path)
            let (ownerError, owner) = client.owner(element)
            guard ownerError == .success else { throw failure("AXUIElementGetPid", key, path, "apiError", ownerError, owner: owner) }
            guard owner == pid else { throw failure("AXUIElementGetPid", key, path, "wrongOwner", ownerError, owner: owner) }
            let remaining = client.now().duration(to: deadline).components
            let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
            guard seconds > 0 else { throw failure("budget", key, path, "deadline") }
            let timeoutError = client.timeout(element, Float(min(seconds, 0.25)))
            guard timeoutError == .success else { throw failure("AXUIElementSetMessagingTimeout", key, path, "apiError", timeoutError, owner: owner) }
            try checkBudget(key, path)
            let (error, value) = client.copy(element, key)
            guard error == .success else { throw failure("AXUIElementCopyAttributeValue", key, path, "apiError", error, owner: owner) }
            try checkBudget(key, path)
            guard let value else { throw failure("AXUIElementCopyAttributeValue", key, path, "nilValue", error, owner: owner) }
            return value
        }
        let root = AXUIElementCreateApplication(pid)
        let key = extras ? kAXExtrasMenuBarAttribute : kAXMenuBarAttribute
        let barValue = try attribute(root, key, "application")
        guard CFGetTypeID(barValue) == AXUIElementGetTypeID() else {
            throw failure("AXUIElementCopyAttributeValue", key, "application", "unexpectedType", .success,
                          expected: "AXUIElement", actual: typeName(barValue))
        }
        let bar = barValue as! AXUIElement
        let children = try attribute(bar, kAXChildrenAttribute, "bar")
        guard let elements = children as? [AXUIElement] else {
            throw failure("AXUIElementCopyAttributeValue", kAXChildrenAttribute, "bar", "unexpectedType", .success,
                          expected: "AXUIElement array", actual: typeName(children))
        }
        guard !elements.isEmpty else {
            throw failure("AXUIElementCopyAttributeValue", kAXChildrenAttribute, "bar", "emptyChildren", .success, count: 0)
        }
        guard elements.count <= (extras ? 128 : 64) else {
            throw failure("AXUIElementCopyAttributeValue", kAXChildrenAttribute, "bar", "tooManyChildren", .success, count: elements.count)
        }
        return try elements.enumerated().map { index, element in
            let path = "bar.children[\(index)]"
            let roleValue = try attribute(element, kAXRoleAttribute, path)
            let role = roleValue as? String
            guard role == kAXMenuBarItemRole || (extras && role == kAXButtonRole) else {
                throw failure("AXUIElementCopyAttributeValue", kAXRoleAttribute, path, "unexpectedRole", .success,
                              expected: extras ? "AXMenuBarItem or AXButton" : "AXMenuBarItem", actual: role ?? typeName(roleValue))
            }
            let p = try attribute(element, kAXPositionAttribute, path)
            let s = try attribute(element, kAXSizeAttribute, path)
            guard CFGetTypeID(p) == AXValueGetTypeID() else {
                throw failure("AXUIElementCopyAttributeValue", kAXPositionAttribute, path, "unexpectedType", .success,
                              expected: "AXValue CGPoint", actual: typeName(p))
            }
            guard CFGetTypeID(s) == AXValueGetTypeID() else {
                throw failure("AXUIElementCopyAttributeValue", kAXSizeAttribute, path, "unexpectedType", .success,
                              expected: "AXValue CGSize", actual: typeName(s))
            }
            var point = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(p as! AXValue, .cgPoint, &point) else {
                throw failure("AXValueGetValue", kAXPositionAttribute, path, "decodeFailure",
                              expected: "CGPoint", actual: "AXValue type \(AXValueGetType(p as! AXValue).rawValue)")
            }
            guard AXValueGetValue(s as! AXValue, .cgSize, &size) else {
                throw failure("AXValueGetValue", kAXSizeAttribute, path, "decodeFailure",
                              expected: "CGSize", actual: "AXValue type \(AXValueGetType(s as! AXValue).rawValue)")
            }
            return CGRect(origin: point, size: size)
        }
    }
    private static func typeName(_ value: CFTypeRef) -> String {
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return "AXUIElement" }
        if CFGetTypeID(value) == AXValueGetTypeID() { return "AXValue" }
        if CFGetTypeID(value) == CFArrayGetTypeID() { return "array" }
        if CFGetTypeID(value) == CFStringGetTypeID() { return "string" }
        return "CFTypeID \(CFGetTypeID(value))"
    }
}

/// AppKit serves its own menu AX hierarchy on the main thread. Querying that
/// hierarchy from our detached worker returns kAXErrorFailure for AXChildren.
/// Keep the same public AX transport and geometry checks; only self-menu reads
/// run here. External applications retain bounded, cancellable background IPC.
enum MenuBarNativeFrontMenuReader {
    @MainActor
    static func frames(pid: Int32, deadline: ContinuousClock.Instant,
                       expectedApplication: MenuBarApplicationIdentity?,
                       client: MenuBarNativeAXGeometry.Client = .live) async throws -> [CGRect] {
        try Task.checkCancellation()
        if pid == ProcessInfo.processInfo.processIdentifier {
            return try MenuBarNativeAXGeometry.frames(pid: pid, extras: false, deadline: deadline,
                scope: "frontMenu", expectedApplication: expectedApplication, client: client)
        }
        let worker = Task.detached {
            try MenuBarNativeAXGeometry.frames(pid: pid, extras: false, deadline: deadline,
                scope: "frontMenu", expectedApplication: expectedApplication, client: client)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}

@MainActor
final class MenuBarNativeLiveObserver {
    let ownerPID: Int32
    private let ownedWindows: () throws -> (control: UInt32, divider: UInt32)
    private let generation: () -> UUID
    private let diagnostic: ((UUID?, String, MenuBarNativeRevealDiagnostic.Sample) -> Void)?
    init(ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         ownedWindows: @escaping () throws -> (control: UInt32, divider: UInt32), generation: @escaping () -> UUID,
         diagnostic: ((UUID?, String, MenuBarNativeRevealDiagnostic.Sample) -> Void)? = nil) {
        self.ownerPID = ownerPID; self.ownedWindows = ownedWindows; self.generation = generation
        self.diagnostic = diagnostic
    }
    func context() throws -> MenuBarNativeObservation.Context {
        let owned = try ownedWindows()
        guard let front = NSWorkspace.shared.frontmostApplication,
              let application = MenuBarApplicationIdentity.current(pid: front.processIdentifier),
              let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { throw MenuBarNativeObservationFailure.menu }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        var windows: [MenuBarStatusTarget] = [], overlays: [CGRect] = []
        var unproven: [UInt32] = []
        var applications: [Int32: MenuBarApplicationIdentity] = [:]
        for row in rows {
            guard let layer = row[kCGWindowLayer as String] as? Int else { throw MenuBarNativeObservationFailure.topology }
            guard layer >= level else { continue }
            guard let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { throw MenuBarNativeObservationFailure.topology }
            let visible = (row[kCGWindowIsOnscreen as String] as? Bool) == true
            if layer > level {
                if visible { overlays.append(frame) }
                continue
            }
            guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { throw MenuBarNativeObservationFailure.topology }
            if ((row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) <= 0 { unproven.append(id) }
            if applications[pid] == nil { applications[pid] = MenuBarApplicationIdentity.current(pid: pid) }
            windows.append(MenuBarStatusTarget(id: id, pid: pid, frame: frame, onScreen: visible, application: applications[pid]))
        }
        let displays = MenuBarDisplay.current()
        let bands = displays.map { CGRect(x: $0.quartzFrame.minX, y: $0.quartzFrame.minY, width: $0.quartzFrame.width, height: 64) }
        overlays = overlays.filter { frame in bands.contains(where: { $0.intersects(frame) }) }
        return .init(generation: generation(), displays: displays, windows: windows, ownerPID: ownerPID,
                     controlID: owned.control, dividerID: owned.divider, frontPID: front.processIdentifier,
                     frontApplication: application, overlays: overlays, unprovenPixelWindowIDs: unproven)
    }
    func observe(_ identity: MenuBarIconIdentity, diagnosticSession: UUID? = nil) async throws -> MenuBarNativeRevealPlan.Observation {
        guard AXIsProcessTrusted() else { throw MenuBarNativeObservationFailure.permission }
        let initial = try context()
        diagnostic?(diagnosticSession, "cg-before-ax", sample(initial))
        let owner = ownerPID
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        let worker = Task.detached {
            var completed: [MenuBarNativeRevealDiagnostic.AXReadDetail.CompletedGroup] = []
            func read(_ pid: Int32, _ extras: Bool, _ scope: String, _ application: MenuBarApplicationIdentity?) throws -> [CGRect] {
                let frames = try MenuBarNativeAXGeometry.frames(pid: pid, extras: extras, deadline: deadline,
                    scope: scope, expectedApplication: application)
                completed.append(.init(scope: scope, pid: pid, application: application, frames: frames))
                return frames
            }
            do {
                let target = try read(identity.pid, true, "targetExtras", identity.application)
                let recovery = identity.pid == owner ? target : try read(owner, true, "recoveryExtras",
                    initial.windows.first { $0.pid == owner }?.application)
                return (target, recovery, completed)
            } catch var error as MenuBarNativeAXReadFailure {
                error.detail.completedGroups = completed
                throw error
            }
        }
        let frames = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        let menu: [CGRect]
        do {
            menu = try await MenuBarNativeFrontMenuReader.frames(pid: initial.frontPID, deadline: deadline,
                expectedApplication: initial.frontApplication)
        } catch var error as MenuBarNativeAXReadFailure {
            error.detail.completedGroups = frames.2
            throw error
        }
        let final = try context()
        diagnostic?(diagnosticSession, "cg-after-ax", sample(final, targetAX: frames.0, recoveryAX: frames.1, menuAX: menu))
        guard final == initial else { throw MenuBarNativeObservationFailure.stale }
        return try MenuBarNativeObservation.assemble(initial, identity: identity, targetAX: frames.0, recoveryAX: frames.1, menuAX: menu)
    }
    private func sample(_ context: MenuBarNativeObservation.Context, targetAX: [CGRect] = [],
                        recoveryAX: [CGRect] = [], menuAX: [CGRect] = []) -> MenuBarNativeRevealDiagnostic.Sample {
        .init(generation: context.generation, frontPID: context.frontPID, frontApplication: context.frontApplication,
              safeAreas: context.displays.flatMap(\.quartzSafeAreas), windows: context.windows,
              overlays: context.overlays, unprovenPixelWindowIDs: context.unprovenPixelWindowIDs,
              targetAX: targetAX, recoveryAX: recoveryAX, menuAX: menuAX)
    }
    func verifyRestorationSafety(diagnosticSession: UUID? = nil) async throws {
        let snapshot = try context(), selection = try MenuBarNativeObservation.select(snapshot)
        let identity = MenuBarIconIdentity(capturing: selection.recovery, peersOnDisplay: selection.peers)
        let observed = try await observe(identity, diagnosticSession: diagnosticSession)
        guard observed.target.onScreen, observed.safeAreas.contains(where: { $0.contains(observed.recoveryButton) }) else {
            throw MenuBarNativeObservationFailure.recovery
        }
    }
}
