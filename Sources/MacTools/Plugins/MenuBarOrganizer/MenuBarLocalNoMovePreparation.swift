// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import CoreGraphics

/// Local acceptance has no destination, move plan, event channel or upgrade API.
/// A Ready value authorizes only a local presentation, never a move admission.
enum MenuBarLocalNoMovePreparation {
    enum Failure: Error { case mode, identity, publication, geometry, stale, listener }
    enum Mode: String {
        case local = "--local-dry-run"
        case complete = "--local-virtual-check-complete"
        case cancel = "--local-virtual-check-cancel"
        case activity = "--local-virtual-check-activity"
        var scenario: String? { self == .local ? nil : String(rawValue.dropFirst("--local-virtual-check-".count)) }
    }
    struct Binding: Equatable {
        let pid: Int32, launch: Double, nonce: UUID, executable: String, hash: String
        let identifier: String, team: String
    }
    struct Item: Equatable {
        let key: String, instance: UUID, window: UInt32, pid: Int32, frame: CGRect
    }
    struct Snapshot {
        let binding: Binding, sequence: UInt64, uptime: UInt64, items: [Item]
    }
    struct Ready {
        let binding: Binding, items: [Item], mode: Mode
        let nativeDispatchEnabled = false
        let senderCapability = "absent"
        fileprivate init(binding: Binding, items: [Item], mode: Mode) {
            self.binding = binding; self.items = items; self.mode = mode
        }
    }
    /// Shared public-window decoder, also exercised by historical owned-data replay.
    static func items(models: [[String: Any]], publicRows: [[String: Any]], pid: Int32, screenTop: Double) throws -> [Item] {
        try models.map { model in
            guard let key = model["itemKey"] as? String, let instance = model["itemInstance"] as? String,
                  let uuid = UUID(uuidString: instance), let window = model["windowNumber"] as? UInt32,
                  let f = model["windowFrameAppKit"] as? [String: Double], let x = f["x"], let y = f["y"], let w = f["width"], let h = f["height"],
                  let row = publicRows.first(where: { $0["kCGWindowNumber"] as? UInt32 == window }),
                  row["kCGWindowOwnerPID"] as? Int32 == pid, row["kCGWindowLayer"] as? Int == 25,
                  let bounds = row["kCGWindowBounds"] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame == CGRect(x: x, y: screenTop - y - h, width: w, height: h)
            else { throw Failure.geometry }
            return Item(key: key, instance: uuid, window: window, pid: pid, frame: frame)
        }
    }
    static func prepare(expected: Binding, first: Snapshot, second: Snapshot, now: UInt64,
                        listenerHealthy: Bool, mode: Mode) throws -> Ready {
        guard expected.pid > 0, expected.launch > 0, expected.hash.count == 64,
              expected.identifier == "com.ryanai.mactools.nativetargets", expected.team == "58TJ64422P",
              expected.executable.hasPrefix("/tmp/mac-tools-hidden-driver-task7/"),
              first.binding == expected, second.binding == expected else { throw Failure.identity }
        guard second.sequence > first.sequence, second.uptime >= first.uptime,
              (100...500).contains(second.uptime - first.uptime), now >= second.uptime,
              now - first.uptime <= 500 else { throw Failure.stale }
        let keys: Set<String> = ["mactools_native_acceptance_T", "mactools_native_acceptance_N"]
        guard first.items == second.items, second.items.count == 2,
              Set(second.items.map(\.key)) == keys, Set(second.items.map(\.instance)).count == 2,
              Set(second.items.map(\.window)).count == 2 else { throw Failure.publication }
        for item in second.items {
            guard item.pid == expected.pid, item.window > 0,
                  [item.frame.minX, item.frame.minY, item.frame.width, item.frame.height].allSatisfy(\.isFinite),
                  item.frame.width > 0, item.frame.height > 0 else { throw Failure.geometry }
        }
        guard listenerHealthy else { throw Failure.listener }
        return Ready(binding: expected, items: second.items, mode: mode)
    }
}
