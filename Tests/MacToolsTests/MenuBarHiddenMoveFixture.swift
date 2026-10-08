// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import CoreGraphics
import Foundation
@testable import MacTools

struct MenuBarHiddenMoveFixture {
    typealias M = MenuBarHiddenMoveModel
    let original: M.Snapshot
    init() {
        func identity(_ id: UInt32) -> MenuBarRecordedTarget {
            let app = MenuBarApplicationIdentity(bundleID: id == 2 ? "com.ryanai.mactools.nativetargets" : "fixture.peer.\(id)",
                bundlePath: "/Fixture\(id).app", launch: Double(100 + id))
            return .init(MenuBarStatusTarget(id: id, pid: Int32(200 + id), frame: .zero, onScreen: false, application: app))
        }
        let target = identity(2)
        let owner = M.Owner(target: target, signedIdentifier: "com.ryanai.mactools.nativetargets", team: "fixture-team",
            codeHash: String(repeating: "a", count: 64), itemKey: "mactools_native_acceptance_T", nonce: UUID(), itemInstance: UUID())
        let items = zip([UInt32(1), 2, 3], [-4371.0, -4341, -4312]).map { id, x in
            M.Item(identity: identity(id), frame: CGRect(x: x, y: 0, width: id == 2 ? 29 : 30, height: 37),
                listedOnScreen: false, onScreen: .missing, alpha: 1, spaces: [7], ownerOcclusionVisible: id == 2 ? false : nil)
        }
        let scope = M.Scope(profile: .trial, continuity: UUID(), displayUUID: "fixture-display", displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2, rotation: 0, activeSpace: 7,
            rightSafe: CGRect(x: 956, y: 0, width: 772, height: 32))
        original = .init(sequence: 1, uptimeMilliseconds: 1000, scope: scope, owner: owner, items: items,
                         membershipIDs: [1, 2, 3], orderEvidence: .observedCoordinates)
    }
    func sample(_ sequence: UInt64, _ time: UInt64, items: [M.Item]? = nil, scope: M.Scope? = nil,
                owner: M.Owner? = nil, membership: [UInt32]? = nil, evidence: M.OrderEvidence? = nil) -> M.Snapshot {
        .init(sequence: sequence, uptimeMilliseconds: time, scope: scope ?? original.scope, owner: owner ?? original.owner,
              items: items ?? original.items, membershipIDs: membership ?? original.membershipIDs,
              orderEvidence: evidence ?? original.orderEvidence)
    }
    func scope(continuity: UUID? = nil, space: UInt64? = nil, scale: Double? = nil) -> M.Scope {
        let s = original.scope
        return .init(profile: s.profile, continuity: continuity ?? s.continuity, displayUUID: s.displayUUID,
            displayID: s.displayID, displayFrame: s.displayFrame, scale: scale ?? s.scale, rotation: s.rotation,
            activeSpace: space ?? s.activeSpace, rightSafe: s.rightSafe)
    }
    func owner(nonce: UUID? = nil, instance: UUID? = nil, target: MenuBarRecordedTarget? = nil) -> M.Owner {
        let o = original.owner
        return .init(target: target ?? o.target, signedIdentifier: o.signedIdentifier, team: o.team, codeHash: o.codeHash,
                     itemKey: o.itemKey, nonce: nonce ?? o.nonce, itemInstance: instance ?? o.itemInstance)
    }
    func item(_ i: Int, frame: CGRect? = nil, listed: Bool? = nil, onScreen: M.OnScreen? = nil,
              visibility: Bool? = nil, identity: MenuBarRecordedTarget? = nil) -> M.Item {
        let old = original.items[i]
        return .init(identity: identity ?? old.identity, frame: frame ?? old.frame, listedOnScreen: listed ?? old.listedOnScreen,
            onScreen: onScreen ?? old.onScreen, alpha: old.alpha, spaces: old.spaces,
            ownerOcclusionVisible: visibility ?? old.ownerOcclusionVisible)
    }
    func plan() throws -> M.Plan { try .capture(sample(1, 1000), sample(2, 1100), now: 1100) }
    func record() throws -> M.Record { try .prepared(plan: plan()) }
    func phase(_ phase: M.Record.Phase, from original: M.Record) throws -> M.Record {
        var record = original; record.phase = phase
        if phase == .restored { record = try record.confirmedReturned(sample(10, 2000), sample(11, 2100), now: 2100) }
        return record
    }
}
