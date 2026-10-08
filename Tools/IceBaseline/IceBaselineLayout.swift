// Copyright (c) 2026 Ryan.AI. MIT. Pure read-only layout admission/replay.
import AppKit

struct IceBaselineLayout: Equatable {
    struct Item: Equatable {
        let id: UInt32, instance: String, key: String, frame: CGRect, visible: Bool, screen: UInt32
    }
    let target: Item, neighbor: Item, anchor: Item, divider: Item
    let returnOnLeft: Bool
    enum Failure: Error { case identity, geometry, notHidden, anchorInvisible, noRoom }
    struct Stability {
        private var previous: IceBaselineLayout?, sequence = -1, at = -Double.infinity, count = 0
        mutating func observe(_ layout: IceBaselineLayout, sequence next: Int, at nextAt: Double, now: Double) -> Bool {
            guard next > sequence, nextAt - at >= 0.1, (0...1).contains(now - nextAt) else { return false }
            count = layout == previous ? count + 1 : 1
            previous = layout; sequence = next; at = nextAt
            return count >= 3
        }
        mutating func reset() { previous = nil; sequence = -1; at = -Double.infinity; count = 0 }
    }
    struct ReturnStability {
        let expected: IceBaselineLayout, pid: Int32, nonce: String, minimumSequence: Int
        private var stability = Stability()
        init(expected: IceBaselineLayout, pid: Int32, nonce: String, minimumSequence: Int) {
            self.expected = expected; self.pid = pid; self.nonce = nonce; self.minimumSequence = minimumSequence
        }
        mutating func observe(_ d: [String: Any], area: CGRect, display: UInt32, now: Double) throws -> Bool {
            guard d["nonce"] as? String == nonce, d["pid"] as? Int32 == pid,
                  let sequence = d["sequence"] as? Int, let at = d["atUnix"] as? Double,
                  let models = d["modelsAfter"] as? [[String: Any]], models.count == 2,
                  let menu = d["menuControl"] as? [String: Any],
                  let h = menu["visibleAnchorModel"] as? [String: Any], let divider = menu["dividerModel"] as? [String: Any],
                  let rows = (d["cgAllAfter"] as? [String: Any])?["ownRows"] as? [[String: Any]] else { throw Failure.identity }
            let original = [expected.target, expected.neighbor, expected.anchor, expected.divider]
            let titles: [UInt32: String] = [expected.target.id:"T",expected.neighbor.id:"N",expected.anchor.id:"H",expected.divider.id:"D"]
            let actual = models + [h, divider]
            guard Set(actual.compactMap { $0["windowNumber"] as? UInt32 }).count == 4,
                  original.allSatisfy({ e in actual.contains { m in
                      m["windowNumber"] as? UInt32 == e.id && m["itemInstance"] as? String == e.instance && m["itemKey"] as? String == e.key
                          && m["title"] as? String == titles[e.id] && m["windowLevel"] as? Int == Int(CGWindowLevelForKey(.statusWindow))
                          && m["screenDisplayID"] as? UInt32 == e.screen && m["windowOnActiveSpace"] as? Bool == true
                  } }) else { throw Failure.identity }
            let status = rows.filter { ($0["kCGWindowLayer"] as? [String: Any])?["value"] as? Int == Int(CGWindowLevelForKey(.statusWindow)) }
            guard status.count == 4, Set(status.compactMap { ($0["kCGWindowNumber"] as? [String: Any])?["value"] as? UInt32 }) == Set(original.map(\.id)),
                  status.allSatisfy({ ($0["kCGWindowOwnerPID"] as? [String: Any])?["value"] as? Int32 == pid }) else { throw Failure.identity }
            guard sequence > minimumSequence, (0...1).contains(now - at) else { stability.reset(); return false }
            // A coherent original layout is mandatory. Frame-only settling does
            // not authorize a new effect; changed identity above is terminal.
            let layout: IceBaselineLayout
            do { layout = try IceBaselineLayout.read(d, area: area, display: display) }
            catch { stability.reset(); return false }
            guard layout == expected else { stability.reset(); return false }
            return stability.observe(layout, sequence: sequence, at: at, now: now)
        }
    }
    static func rect(_ d: [String: Any]?) throws -> CGRect {
        guard let d, let x = d["x"] as? Double, let y = d["y"] as? Double,
              let w = d["width"] as? Double, let h = d["height"] as? Double,
              [x,y,w,h].allSatisfy({ $0.isFinite }), w > 0, h > 0 else { throw Failure.geometry }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    static func item(_ d: [String: Any], title: String, key: String) throws -> Item {
        guard d["title"] as? String == title, d["itemKey"] as? String == key,
              let id = d["windowNumber"] as? UInt32, id > 0,
              let instance = d["itemInstance"] as? String, UUID(uuidString: instance) != nil,
              d["windowLevel"] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
              d["windowOnActiveSpace"] as? Bool == true,
              let visible = d["windowOcclusionVisible"] as? Bool,
              let screen = d["screenDisplayID"] as? UInt32 else { throw Failure.identity }
        let f = try rect(d["windowFrameAppKit"] as? [String: Any]), s = try rect(d["screenFrameAppKit"] as? [String: Any])
        return Item(id: id, instance: instance, key: key,
            frame: CGRect(x: f.minX, y: s.maxY - f.maxY, width: f.width, height: f.height), visible: visible, screen: screen)
    }
    static func read(_ d: [String: Any], area: CGRect, display: UInt32) throws -> Self {
        guard let models = d["modelsAfter"] as? [[String: Any]], models.count == 2,
              let t = models.first(where: { $0["title"] as? String == "T" }),
              let n = models.first(where: { $0["title"] as? String == "N" }),
              let menu = d["menuControl"] as? [String: Any],
              let h = menu["visibleAnchorModel"] as? [String: Any],
              let dividerModel = menu["dividerModel"] as? [String: Any],
              let nonce = d["nonce"] as? String, UUID(uuidString: nonce) != nil,
              let pid = d["pid"] as? Int32, pid > 0,
              let rows = (d["cgAllAfter"] as? [String: Any])?["ownRows"] as? [[String: Any]],
              let onScreen = (d["cgOnScreen"] as? [String: Any])?["ownRows"] as? [[String: Any]] else { throw Failure.identity }
        let target = try item(t, title: "T", key: "mactools_native_acceptance_T")
        let neighbor = try item(n, title: "N", key: "mactools_native_acceptance_N")
        let anchor = try item(h, title: "H", key: "ice_baseline_H_\(nonce)")
        let divider = try item(dividerModel, title: "D", key: "ice_baseline_D_\(nonce)")
        let all = [target,neighbor,anchor,divider]
        guard Set(all.map(\.id)).count == 4, Set(all.map(\.instance)).count == 4,
              all.allSatisfy({ $0.screen == display }) else { throw Failure.identity }
        let statusIDs = rows.filter { ($0["kCGWindowLayer"] as? [String: Any])?["value"] as? Int == Int(CGWindowLevelForKey(.statusWindow)) }
            .compactMap { ($0["kCGWindowNumber"] as? [String: Any])?["value"] as? UInt32 }
        guard statusIDs.count == 4, Set(statusIDs) == Set(all.map(\.id)) else { throw Failure.identity }
        for item in all {
            let matches = rows.filter { ($0["kCGWindowNumber"] as? [String: Any])?["value"] as? UInt32 == item.id }
            guard matches.count == 1, let row = matches.first,
                  (row["kCGWindowOwnerPID"] as? [String: Any])?["value"] as? Int32 == pid,
                  (row["kCGWindowLayer"] as? [String: Any])?["value"] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let b = (row["kCGWindowBounds"] as? [String: Any])?["value"] as? [String: Any],
                  b["X"] as? Double == item.frame.minX, b["Y"] as? Double == item.frame.minY,
                  b["Width"] as? Double == item.frame.width, b["Height"] as? Double == item.frame.height else { throw Failure.identity }
        }
        guard !target.visible, !neighbor.visible, target.frame.maxX <= 0, neighbor.frame.maxX <= 0 else { throw Failure.notHidden }
        guard let screen = n["screenFrameAppKit"] as? [String: Any], let screenWidth = screen["width"] as? Double,
              divider.frame.width >= screenWidth * 2, divider.frame.minX == max(target.frame.maxX, neighbor.frame.maxX),
              divider.frame.minY == target.frame.minY, divider.frame.height == target.frame.height else { throw Failure.geometry }
        guard anchor.visible, onScreen.contains(where: { ($0["kCGWindowNumber"] as? [String: Any])?["value"] as? UInt32 == anchor.id }) else { throw Failure.anchorInvisible }
        guard anchor.frame.minX - target.frame.width >= area.minX + 20, anchor.frame.maxX <= area.maxX,
              anchor.frame.minY == target.frame.minY, anchor.frame.height == target.frame.height else { throw Failure.noRoom }
        let left = target.frame.maxX == neighbor.frame.minX
        guard left || target.frame.minX == neighbor.frame.maxX else { throw Failure.geometry }
        return Self(target: target, neighbor: neighbor, anchor: anchor, divider: divider, returnOnLeft: left)
    }
}
