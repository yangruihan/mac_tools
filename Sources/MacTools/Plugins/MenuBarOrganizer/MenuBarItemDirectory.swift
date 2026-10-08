import AppKit

/// A metadata directory, independent of thumbnails and screen-capture access.
/// Labels/ordinals are presentation only; actions retain the exact launch/window identity.
struct MenuBarDirectoryItem: Identifiable {
    enum Position: Equatable {
        case notch, offscreen, nativeBar
        var title: String {
            switch self {
            case .notch: return "刘海区域"
            case .offscreen: return "屏外 / 收纳"
            case .nativeBar: return "原生栏位置"
            }
        }
    }
    let id: CGWindowID
    let applicationName: String
    let ordinal: Int
    let applicationItemCount: Int
    let position: Position
    let identity: MenuBarIconIdentity
    var title: String {
        applicationItemCount > 1 ? "\(applicationName) · 图标 \(ordinal)" : applicationName
    }
}

enum MenuBarItemDirectory {
    static func build(windows: [MenuBarStatusTarget], displays: [MenuBarDisplay],
                      displayID: CGDirectDisplayID, excludingPID: Int32,
                      applicationName: (Int32) -> String?) -> [MenuBarDirectoryItem] {
        let matching = displays.filter { $0.id == displayID }
        guard matching.count == 1, let display = matching.first else { return [] }
        let duplicates = Dictionary(grouping: windows, by: \.id)
        let peers = windows.filter { target in
            guard target.pid != excludingPID, duplicates[target.id]?.count == 1,
                  let application = target.application, application.launch.isFinite,
                  !application.bundleID.isEmpty, !application.bundlePath.isEmpty,
                  !target.frame.isNull, !target.frame.isInfinite,
                  [target.frame.minX, target.frame.minY, target.frame.width, target.frame.height].allSatisfy({ $0.isFinite }),
                  target.frame.width > 8, target.frame.width < 150,
                  target.frame.height > 0, target.frame.height < 64,
                  abs(target.frame.minY - display.quartzFrame.minY) < 1 else { return false }
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            let containing = displays.filter { $0.quartzFrame.contains(center) }
            if !containing.isEmpty { return containing.count == 1 && containing[0].id == displayID }
            // A collapsed separator may park an exact window offscreen. With
            // side-by-side display rows, that alone cannot identify its display.
            return displays.filter { abs($0.quartzFrame.minY - target.frame.minY) < 1 }.count == 1
        }.sorted { $0.frame.minX == $1.frame.minX ? $0.id < $1.id : $0.frame.minX < $1.frame.minX }
        let byPID = Dictionary(grouping: peers, by: \.pid)
        return peers.map { target in
            let siblings = byPID[target.pid] ?? []
            let ordinal = (siblings.firstIndex(where: { $0.id == target.id }) ?? 0) + 1
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            let position: MenuBarDirectoryItem.Position
            if !display.quartzFrame.contains(center) { position = .offscreen }
            else if display.quartzSafeAreas.contains(where: {
                target.frame.minX >= $0.minX && target.frame.maxX <= $0.maxX
            }) { position = .nativeBar }
            else { position = .notch }
            let name = applicationName(target.pid)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MenuBarDirectoryItem(id: target.id,
                applicationName: name.flatMap { $0.isEmpty ? nil : $0 } ?? target.application!.bundleID,
                ordinal: ordinal, applicationItemCount: siblings.count, position: position,
                // A second item on another display still makes restart rematching ambiguous.
                identity: MenuBarIconIdentity(capturing: target, peersOnDisplay: windows))
        }
    }
}
