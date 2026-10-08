import Foundation
import CoreGraphics
@testable import MacTools

/// Constructed data only. No positive facts are asserted for the real desktop.
struct MenuBarMoveAdapterFixture {
    typealias M = MenuBarTemporaryMoveModel
    let record: M.Record
    var owner: M.Owner { record.plan.original.owner }
    init() throws {
        let windows: [M.Window] = zip([UInt32(1), 2, 3, 4], [500.0, 600, 1050, 1650]).map { id, x in
            let app = MenuBarApplicationIdentity(bundleID: id == 2 ? "com.ryanai.mactools.nativetargets" : "model.peer.\(id)",
                                                 bundlePath: "/Model\(id).app", launch: Double(id) + 100)
            let identity = MenuBarRecordedTarget(MenuBarStatusTarget(id: id, pid: Int32(id) + 20,
                frame: .zero, onScreen: true, application: app))
            return M.Window(identity: identity, frame: CGRect(x: x, y: 0, width: 40, height: 37),
                button: CGRect(x: x + 4, y: 6.5, width: 32, height: 24), onScreen: .ordered,
                listedOnScreen: true, alpha: 1, ownerOcclusionVisible: id == 2 ? true : nil)
        }
        let scope = M.Scope(continuity: UUID(), spaceEpoch: UUID(), displayUUID: "model-display", displayID: 1,
            scale: 2, rotation: 0, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            leftSafe: CGRect(x: 0, y: 0, width: 771, height: 32), rightSafe: CGRect(x: 956, y: 0, width: 772, height: 32),
            frontPID: 10, frontApplication: MenuBarApplicationIdentity(bundleID: "model.front", bundlePath: "/ModelFront.app", launch: 10))
        let owner = M.Owner(nonce: UUID(), itemInstance: UUID(), itemKey: "mactools_native_acceptance_T",
            signedIdentifier: "com.ryanai.mactools.nativetargets", team: "model-team", codeHash: "model-code-hash", target: windows[1].identity)
        let a = M.Sample(sequence: 1, uptimeMilliseconds: 1000, scope: scope, owner: owner, windows: windows,
            recovery: windows[3].identity, applicationMenu: CGRect(x: 0, y: 0, width: 470, height: 32),
            overlays: [], interface: .closed, inputIdle: true, interferenceEpoch: UUID())
        var b = a; b.sequence = 2; b.uptimeMilliseconds = 1100
        let plan = try M.Plan.make(a, b, access: M.Access(ax: true, post: true, interferenceObservation: true), now: 1100, reservationWidth: 42)
        record = M.Record(schemaVersion: 1, transaction: UUID(), plan: plan, phase: .prepared)
    }
    func phase(_ phase: M.Record.Phase) -> M.Record { var next = record; next.phase = phase; return next }
}
