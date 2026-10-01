import AppKit

// A display-local transform avoids assuming that the focused or first screen is the Quartz origin.
struct MenuBarDisplay: Equatable {
    enum Availability: Equatable { case visible, occluded, outsideDisplay }
    let id: CGDirectDisplayID
    let frame: CGRect
    let quartzFrame: CGRect
    let safeAreas: [CGRect] // AppKit coordinates; notch-free displays use the full frame.

    func quartz(_ rectangle: CGRect) -> CGRect {
        CGRect(x: quartzFrame.minX + rectangle.minX - frame.minX,
               y: quartzFrame.minY + frame.maxY - rectangle.maxY,
               width: rectangle.width, height: rectangle.height)
    }
    var quartzSafeAreas: [CGRect] { (safeAreas.isEmpty ? [frame] : safeAreas).map(quartz) }
    func availability(of rectangle: CGRect) -> Availability {
        let point = CGPoint(x: rectangle.midX, y: rectangle.midY)
        guard quartzFrame.contains(point) else { return .outsideDisplay }
        return quartzSafeAreas.contains(where: { $0.contains(point) }) ? .visible : .occluded
    }
    func anchorSafe(_ rectangle: CGRect) -> Bool {
        MenuBarVisibility.recoveryVisible(rectangle, safeAreas: safeAreas.isEmpty ? [frame] : safeAreas)
    }
    func anchorSafe(_ button: CGRect, clippedTo window: CGRect) -> Bool {
        // NSStatusBarButton's layout can be 27pt inside a 24pt external-display window.
        // Only pixels inside the actual backing window are visible; never clip to the safe area itself.
        anchorSafe(button.intersection(window))
    }
    func containsStatusPair(divider: CGRect, control: CGRect) -> Bool {
        // A collapsed divider intentionally extends beyond the left edge; its trailing edge is the anchor.
        frame.contains(CGPoint(x: control.midX, y: control.midY))
            && frame.contains(CGPoint(x: divider.maxX - 1, y: divider.midY))
            && abs(divider.midY - control.midY) < 8
    }
    static func current() -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            return Self(id: id, frame: screen.frame, quartzFrame: CGDisplayBounds(id),
                        safeAreas: [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 })
        }
    }
}

struct MenuBarEnvironment {
    enum Change: Equatable { case displaysChanged, willSleep, didWake, applicationsChanged }
    private(set) var generation = UUID()
    private(set) var sleeping = false
    mutating func receive(_ change: Change) {
        generation = UUID()
        if change == .willSleep { sleeping = true }
        if change == .didWake { sleeping = false }
    }
    func accepts(_ generation: UUID) -> Bool { !sleeping && self.generation == generation }
}

// Workspace notifications are delivered on its own center, not NotificationCenter.default.
final class MenuBarEnvironmentMonitor {
    private let screenCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let receive: (MenuBarEnvironment.Change) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(screenCenter: NotificationCenter = .default,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         receive: @escaping (MenuBarEnvironment.Change) -> Void) {
        self.screenCenter = screenCenter; self.workspaceCenter = workspaceCenter; self.receive = receive
    }
    func start() {
        guard observers.isEmpty else { return }
        let names: [(NotificationCenter, Notification.Name, MenuBarEnvironment.Change)] = [
            (screenCenter, NSApplication.didChangeScreenParametersNotification, .displaysChanged),
            (workspaceCenter, NSWorkspace.willSleepNotification, .willSleep),
            (workspaceCenter, NSWorkspace.didWakeNotification, .didWake),
            (workspaceCenter, NSWorkspace.didLaunchApplicationNotification, .applicationsChanged),
            (workspaceCenter, NSWorkspace.didTerminateApplicationNotification, .applicationsChanged)]
        for (center, name, change) in names {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.receive(change) }))
        }
    }
    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }; observers = []
    }
    deinit { stop() }
}
