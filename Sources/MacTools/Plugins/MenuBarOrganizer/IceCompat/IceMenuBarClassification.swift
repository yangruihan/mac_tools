// Adapted classification condition from Ice 0.11.12 WindowInfo.isMenuBarItem.
// Jordan Baird and contributors, GPLv3. Ryan.AI modifications 2026-10-03:
// exhaustive raw-member partition, authenticated carrier and no unknown filter.
import Foundation
import CoreGraphics

enum IceMenuBarClassification {
    struct PublicMember: Equatable {
        let windowID: UInt32
        let pid: Int32
        let frame: CGRect
        let layer: Int
        let alpha: Double
    }
    struct Partition {
        let rawIDs: [UInt32]
        let statusIDs: [UInt32] // Includes divider/control windows of any width.
        let carriers: [MenuBarHiddenMoveModel.Carrier]
        var logicalOrderProven: Bool { false }
    }
    enum Failure: Error, Equatable { case inventory, changed, unknown, carrier }
    static func partition(_ directory: IceMenuBarReadAdapter.Directory,
                          before: [PublicMember], after: [PublicMember],
                          display: CGRect, signatures: [MenuBarProcessSignature.Proof]) throws -> Partition {
        guard directory.enumerationComplete, before == after,
              Set(before.map(\.windowID)).count == before.count,
              Set(before.map(\.windowID)) == Set(directory.memberIDs),
              Set(directory.members.map(\.windowID)) == Set(directory.memberIDs),
              directory.spaceBefore > 0, directory.spaceBefore == directory.spaceAfter else { throw Failure.inventory }
        var statuses: [UInt32] = [], carriers: [MenuBarHiddenMoveModel.Carrier] = []
        for native in directory.members {
            guard let row = before.first(where: { $0.windowID == native.windowID }), row.pid > 0,
                  row.frame == native.frame, row.alpha.isFinite, row.alpha > 0, row.alpha <= 1,
                  native.spaces.contains(directory.spaceBefore) else { throw Failure.changed }
            if row.layer == Int(CGWindowLevelForKey(.statusWindow)) {
                statuses.append(row.windowID) // Do not discard wide control items.
                continue
            }
            guard row.layer == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let proof = signatures.first(where: { $0.pid == row.pid }), proof.appleAnchor,
                  proof.identifier == "com.apple.WindowServer",
                  proof.executable == "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
                  proof.launch.map({ $0.isFinite && $0 > 0 }) ?? true, proof.sha256.count == 64,
                  row.frame.minX == display.minX, row.frame.minY == display.minY,
                  row.frame.width == display.width, row.frame.height > 0, row.frame.height < 64 else { throw Failure.unknown }
            carriers.append(.init(windowID: row.windowID, signature: proof, frame: row.frame,
                                  layer: row.layer, spaces: native.spaces))
        }
        guard carriers.count == 1 else { throw Failure.carrier }
        return .init(rawIDs: directory.memberIDs, statusIDs: statuses, carriers: carriers)
    }
}
