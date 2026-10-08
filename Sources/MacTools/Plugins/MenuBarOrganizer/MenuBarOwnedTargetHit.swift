// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import ApplicationServices
import Foundation

/// Exact public AX hit for the authenticated T after it becomes visible. No
/// action, coordinates fallback, private AX window lookup or permission request.
enum MenuBarOwnedTargetHit {
    struct Proof: Codable {
        let pid: Int32, windowID: UInt32, role: String, help: String
        let frame: CGRect, point: CGPoint
        let at: UInt64
    }
    struct Reads {
        let app: (Int32) -> AXUIElement
        let attribute: (AXUIElement, String) -> CFTypeRef?
        let owner: (AXUIElement) -> Int32?
        let hit: (CGPoint) -> AXUIElement?
        let same: (AXUIElement, AXUIElement) -> Bool
        static let native = Reads(app: AXUIElementCreateApplication, attribute: { e, key in
            AXUIElementSetMessagingTimeout(e, 0.1)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success ? value : nil
        }, owner: { e in var pid: pid_t = 0; return AXUIElementGetPid(e, &pid) == .success ? pid : nil },
        hit: { point in
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.1)
            var element: AXUIElement?
            return AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success ? element : nil
        }, same: { CFEqual($0, $1) })
    }
    enum Failure: Error { case geometry, extras, target, globalHit, changed }
    static func verify(pid: Int32, window: UInt32, frame: CGRect, now: UInt64, reads: Reads = .native) throws -> Proof {
        guard pid > 0, window > 0, [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0 else { throw Failure.geometry }
        let help = "MacTools 自建验收图标 T"
        func matches(_ e: AXUIElement) -> Bool {
            guard reads.owner(e) == pid,
                  reads.attribute(e, kAXRoleAttribute) as? String == kAXMenuBarItemRole,
                  reads.attribute(e, kAXHelpAttribute) as? String == help,
                  let p = reads.attribute(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
                  let s = reads.attribute(e, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return false }
            var point = CGPoint.zero, size = CGSize.zero
            return AXValueGetValue(p as! AXValue, .cgPoint, &point) && AXValueGetValue(s as! AXValue, .cgSize, &size)
                && CGRect(origin: point, size: size) == frame
        }
        let app = reads.app(pid)
        guard reads.owner(app) == pid, let extras = reads.attribute(app, kAXExtrasMenuBarAttribute),
              CFGetTypeID(extras) == AXUIElementGetTypeID(), reads.owner(extras as! AXUIElement) == pid,
              let children = reads.attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { throw Failure.extras }
        let candidates = children.filter(matches)
        guard candidates.count == 1 else { throw Failure.target }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let hit = reads.hit(point), reads.same(hit, candidates[0]), matches(hit) else { throw Failure.globalHit }
        guard matches(candidates[0]) else { throw Failure.changed }
        return .init(pid: pid, windowID: window, role: kAXMenuBarItemRole, help: help, frame: frame, point: point, at: now)
    }
}
