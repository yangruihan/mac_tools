import CoreGraphics

struct MenuBarStatusTarget {
    let id: CGWindowID
    let pid: Int32
    let frame: CGRect
    let onScreen: Bool
}

enum MenuBarIconActivation {
    // Never reuse screenshot coordinates; select the current window with the original owner.
    static func target(id: CGWindowID, pid: Int32, windows: [MenuBarStatusTarget], safeAreas: [CGRect]) -> MenuBarStatusTarget? {
        let matches = windows.filter { $0.id == id && $0.pid == pid && $0.onScreen }
        guard matches.count == 1, let item = matches.first,
              !item.frame.isNull, !item.frame.isInfinite, item.frame.width > 8, item.frame.width < 150,
              item.frame.height > 0, item.frame.height < 64 else { return nil }
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        guard safeAreas.contains(where: { $0.contains(point) }),
              windows.filter({ $0.onScreen && $0.frame.contains(point) }).count == 1 else { return nil }
        return item
    }
    static func hitMatches(_ frame: CGRect, window: CGRect) -> Bool {
        frame.width > 8 && frame.width < 150 && frame.height > 0 && frame.height < 64
            && abs(frame.midX - window.midX) < 4 && frame.width <= window.width + 8
            && frame.contains(CGPoint(x: window.midX, y: window.midY))
            && abs(frame.midY - window.midY) < 4
    }
    static func unchanged(_ first: MenuBarStatusTarget, _ second: MenuBarStatusTarget) -> Bool {
        first.id == second.id && first.pid == second.pid && first.onScreen && second.onScreen
            && abs(first.frame.minX - second.frame.minX) < 1 && abs(first.frame.minY - second.frame.minY) < 1
            && abs(first.frame.width - second.frame.width) < 1 && abs(first.frame.height - second.frame.height) < 1
    }
}
