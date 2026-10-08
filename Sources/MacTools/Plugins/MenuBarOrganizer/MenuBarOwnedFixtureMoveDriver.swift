// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import CoreGraphics

protocol MenuBarOwnedFixtureObservations {
    var now: UInt64 { get }
    func bindOperationStop(_ stop: MenuBarOperationStop?)
    func pair() throws -> (MenuBarHiddenMoveModel.Snapshot, MenuBarHiddenMoveModel.Snapshot)
    func admission(_ plan: MenuBarHiddenMoveModel.Plan) throws -> MenuBarRecordedTarget
    func button(_ owner: MenuBarHiddenMoveModel.Owner) throws -> CGRect
    func menu(_ owner: MenuBarHiddenMoveModel.Owner, open: Bool) throws
    func cancelMenu(_ owner: MenuBarHiddenMoveModel.Owner) throws
}
extension MenuBarOwnedFixtureObservations {
    func bindOperationStop(_ stop: MenuBarOperationStop?) {}
}
/// Isolated native driver, with an injectable observation/channel boundary for
/// faults. Nothing in the product constructs it or enables the default backend.
final class MenuBarOwnedFixtureMoveDriver: MenuBarHiddenMoveDriver {
    typealias M = MenuBarHiddenMoveModel
    enum Failure: Error { case admission, changed, visible, anchor, stale, unresolvedDown }
    let observations: any MenuBarOwnedFixtureObservations
    let mouse: MenuBarOwnedMouseTransport
    private var operationStop: MenuBarOperationStop?
    func bindOperationStop(_ stop: MenuBarOperationStop?) {
        operationStop = stop; mouse.bindOperationStop(stop); observations.bindOperationStop(stop)
    }
    func verifyNoUnresolvedDown() throws {
        guard !mouse.channel.needsRelease else { throw Failure.unresolvedDown }
    }
    let evidence: MenuBarMoveStageRecorder?
    private var destination: MenuBarRecordedTarget?
    private var admitted: M.Plan?
    private var visible: M.Snapshot?
    var now: UInt64 { observations.now }
    init(observations: any MenuBarOwnedFixtureObservations, mouse: MenuBarOwnedMouseTransport, evidence: MenuBarMoveStageRecorder? = nil) {
        self.observations = observations; self.mouse = mouse; self.evidence = evidence
    }
    func samplePair() throws -> (M.Snapshot, M.Snapshot) { try observations.pair() }
    func admit(_ plan: M.Plan) throws {
        try plan.validateStructure()
        let anchor = try observations.admission(plan)
        guard let item = plan.original.items.first(where: { $0.identity == anchor }),
              anchor != plan.original.owner.target, item.listedOnScreen,
              item.frame.minX >= plan.original.scope.rightSafe.minX,
              item.frame.maxX <= plan.original.scope.rightSafe.maxX,
              let target = plan.original.items.first(where: { $0.identity == plan.original.owner.target }),
              item.frame.minX - target.frame.width >= plan.original.scope.rightSafe.minX,
              target.frame.maxX <= item.frame.minX else { throw Failure.admission }
        destination = anchor; admitted = plan
    }
    func moveToVisible(_ plan: M.Plan, lease: MenuBarMoveInterference.Lease) throws {
        try operationStop?.check()
        guard admitted == plan, let destination else { throw Failure.admission }
        let pair = try observations.pair()
        try stable(pair)
        guard pair.1.sameFacts(as: plan.original),
              let anchor = pair.1.items.first(where: { $0.identity == destination }) else { throw Failure.changed }
        try mouse.pair(pid: plan.original.owner.target.pid, downWindow: plan.original.owner.target.windowID,
            upWindow: anchor.identity.windowID, start: CGPoint(x: 20_000, y: 20_000),
            end: CGPoint(x: anchor.frame.minX, y: anchor.frame.midY), command: true,
            gesture: lease.gesture, lease: lease, policy: .isolatedOwnedFixture)
    }
    func verifyVisible(_ plan: M.Plan) throws {
        guard let destination else { throw Failure.admission }
        let pair = try observations.pair(); try stable(pair)
        let sample = pair.1, old = plan.original, target = old.owner.target
        guard sample.scope == old.scope, sample.owner == old.owner, sample.carriers == old.carriers,
              Set(sample.membershipIDs) == Set(old.membershipIDs),
              let oldIndex = old.items.firstIndex(where: { $0.identity == target }),
              let destIndex = old.items.firstIndex(where: { $0.identity == destination }), oldIndex < destIndex,
              let moved = sample.items.first(where: { $0.identity == target }),
              moved.listedOnScreen, moved.onScreen == .ordered, moved.ownerOcclusionVisible == true,
              moved.frame.minX >= sample.scope.rightSafe.minX, moved.frame.maxX <= sample.scope.rightSafe.maxX else { throw Failure.visible }
        var expected = old.items.map(\.identity); expected.remove(at: oldIndex); expected.insert(target, at: destIndex - 1)
        guard sample.items.map(\.identity) == expected else { throw Failure.changed }
        for (i, item) in old.items.enumerated() where item.identity != target {
            guard let current = sample.items.first(where: { $0.identity == item.identity }),
                  current.frame == item.frame.offsetBy(dx: i > oldIndex && i < destIndex ? -moved.frame.width : 0, dy: 0),
                  current.alpha == item.alpha, current.spaces == item.spaces else { throw Failure.changed }
        }
        guard moved.frame.size == old.items[oldIndex].frame.size,
              let anchor = sample.items.first(where: { $0.identity == destination }), moved.frame.maxX == anchor.frame.minX else { throw Failure.changed }
        let button = try observations.button(sample.owner)
        guard moved.frame.contains(button), sample.scope.rightSafe.contains(button) else { throw Failure.visible }
        try evidence?.append("visible-verified", MenuBarMoveStageRecorder.Pair(first: pair.0, second: pair.1))
        visible = sample
    }
    func openOwnedMenu(_ owner: M.Owner, lease: MenuBarMoveInterference.Lease) throws {
        try operationStop?.check()
        guard visible?.owner == owner else { throw Failure.visible }
        let button = try observations.button(owner)
        guard visible!.scope.rightSafe.contains(button), visible!.items.first(where: { $0.identity == owner.target })!.frame.contains(button) else { throw Failure.visible }
        try mouse.pair(pid: owner.target.pid, downWindow: owner.target.windowID, upWindow: owner.target.windowID,
            start: CGPoint(x: button.midX, y: button.midY), end: CGPoint(x: button.midX, y: button.midY),
            command: false, gesture: lease.gesture, lease: lease, policy: .isolatedOwnedFixture)
        try observations.menu(owner, open: true)
    }
    func cancelOwnedMenu(_ owner: M.Owner) throws {
        try operationStop?.check(); try observations.cancelMenu(owner)
    }
    func verifyMenuClosed(_ owner: M.Owner) throws { try observations.menu(owner, open: false) }
    func restore(_ plan: M.Plan, lease: MenuBarMoveInterference.Lease) throws {
        try operationStop?.check()
        try verifyVisible(plan)
        let pair = try observations.pair(); try stable(pair)
        guard let visible, pair.1.sameFacts(as: visible),
              let target = pair.1.items.first(where: { $0.identity == plan.original.owner.target }) else { throw Failure.changed }
        // Native admission binds the original right anchor to this fixture's N.
        // Its disappearance cannot authorize a fallback to a different neighbor.
        guard let right = plan.anchor.right, let neighbor = pair.1.items.first(where: { $0.identity == right }) else { throw Failure.anchor }
        let point = CGPoint(x: neighbor.frame.minX, y: neighbor.frame.midY)
        try mouse.pair(pid: target.identity.pid, downWindow: target.identity.windowID, upWindow: neighbor.identity.windowID,
            start: CGPoint(x: 20_000, y: 20_000), end: point, command: true,
            gesture: lease.gesture, lease: lease, policy: .isolatedOwnedFixture)
    }
    private func stable(_ pair: (M.Snapshot, M.Snapshot)) throws {
        guard pair.1.sequence > pair.0.sequence, pair.1.uptimeMilliseconds >= pair.0.uptimeMilliseconds,
              (100...500).contains(pair.1.uptimeMilliseconds - pair.0.uptimeMilliseconds),
              pair.0.sameFacts(as: pair.1), now >= pair.1.uptimeMilliseconds,
              now - pair.1.uptimeMilliseconds <= 250 else { throw Failure.stale }
    }
}
