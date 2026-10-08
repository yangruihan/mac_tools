// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

protocol MenuBarHiddenMoveDriver {
    var now: UInt64 { get }
    // This must include authenticated complete classification, all old width/v1
    // and v2 recovery responsibilities, permission and destination-capacity gate.
    func bindOperationStop(_ stop: MenuBarOperationStop?)
    func verifyNoUnresolvedDown() throws
    func admit(_ plan: MenuBarHiddenMoveModel.Plan) throws
    func samplePair() throws -> (MenuBarHiddenMoveModel.Snapshot, MenuBarHiddenMoveModel.Snapshot)
    func moveToVisible(_ plan: MenuBarHiddenMoveModel.Plan, lease: MenuBarMoveInterference.Lease) throws
    func verifyVisible(_ plan: MenuBarHiddenMoveModel.Plan) throws
    func openOwnedMenu(_ owner: MenuBarHiddenMoveModel.Owner, lease: MenuBarMoveInterference.Lease) throws
    func cancelOwnedMenu(_ owner: MenuBarHiddenMoveModel.Owner) throws
    // Two fresh, authenticated closed observations; unknown is an error.
    func verifyMenuClosed(_ owner: MenuBarHiddenMoveModel.Owner) throws
    func restore(_ plan: MenuBarHiddenMoveModel.Plan, lease: MenuBarMoveInterference.Lease) throws
}

extension MenuBarHiddenMoveDriver {
    func bindOperationStop(_ stop: MenuBarOperationStop?) {}
}

/// No app/UI wiring. Native driver is standalone opt-in; real route and
/// full return evidence still need a coordinated self-owned fixture trial.
final class MenuBarHiddenMoveCoordinator {
    enum Policy { case disabled, isolatedOwnedFixture }
    enum Failure: Error, Equatable { case disabled, busy, pendingRecovery, cancelled, deadline }
    private let journal: MenuBarHiddenMoveJournal
    private let input: any MenuBarHiddenInterferenceSource
    private let driver: any MenuBarHiddenMoveDriver
    private let evidence: MenuBarMoveStageRecorder?
    private(set) var operationStop = MenuBarOperationStop()
    private var gate = MenuBarMoveInterference.Gate()
    private(set) var active = false
    private(set) var retained: MenuBarHiddenMoveModel.Record?
    private(set) var completedFullCycle = false
    init(journal: MenuBarHiddenMoveJournal, input: any MenuBarHiddenInterferenceSource, driver: any MenuBarHiddenMoveDriver,
         evidence: MenuBarMoveStageRecorder? = nil) {
        self.journal = journal; self.input = input; self.driver = driver; self.evidence = evidence
    }
    func run(_ policy: Policy = .disabled, startPermit: MenuBarRealLocalAuthorization.Permit? = nil,
             consumeAction: (() throws -> Void)? = nil,
             cancelled: () -> Bool = { false }) throws {
        guard policy == .isolatedOwnedFixture else { throw Failure.disabled }
        guard !active else { throw Failure.busy }
        #if OWNED_LIVE_CONTROLLER
        guard startPermit != nil, consumeAction != nil else { throw MenuBarRealLocalAuthorization.Failure.nonNative }
        #endif
        try operationStop.withCancellation(cancelled) {
            input.bindOperationStop(operationStop); driver.bindOperationStop(operationStop)
            defer { input.bindOperationStop(nil); driver.bindOperationStop(nil) }
            do {
                guard evidence?.poisoned != true else { throw MenuBarMoveStageRecorder.Failure.poisoned }
                active = true; completedFullCycle = false
                defer { active = false; gate.finish() }
                guard try journal.inspect() == nil else { throw Failure.pendingRecovery }
                let start = driver.now
                func budget() throws {
                    try operationStop.check()
                    guard driver.now >= start, driver.now - start <= 5000 else { throw Failure.deadline }
                }
                let pair = try driver.samplePair()
                let plan = try MenuBarHiddenMoveModel.Plan.capture(pair.0, pair.1, now: driver.now)
                if let evidence {
                    guard evidence.nonce == plan.original.owner.nonce else { throw Failure.cancelled }
                    try evidence.append("original-plan", plan)
                }
                try driver.admit(plan)
                try budget()
                try operationStop.check()
                // Fresh target/destination admission and absence of recovery precede
                // attempt consumption. Recheck both live monitors again when arming.
                try MenuBarRealLocalAuthorization.checkGateEntry(plan, permit: startPermit)
                try consumeAction?()
                try budget()
                try operationStop.check()
                try MenuBarRealLocalAuthorization.armAndHandoff(plan, permit: startPermit, input: input,
                    gate: &gate, now: { self.driver.now })
                let prepared = try MenuBarHiddenMoveModel.Record.prepared(plan: plan)
                retained = prepared
                // Unknown persistence result remains possibly committed. Never dispatch
                // an event if this does not return a durable matching receipt.
                let saved = try journal.persist(prepared, replacing: nil, boundTo: plan.original.owner)
                retained = saved
                try evidence?.append("prepared", saved)
                try boundary(); try budget()
                try operationStop.check()
                try driver.moveToVisible(plan, lease: gate.lease!)
                var moved = saved; moved.phase = .moved
                // Persistence/verification failure after send retains the prepared
                // possible-effect record, never retries the move or deletes it.
                retained = try journal.persist(moved, replacing: saved, boundTo: plan.original.owner)
                try evidence?.append("moved", moved)
                try driver.verifyVisible(plan)
                try boundary(); try budget()
                try operationStop.check()
                try driver.openOwnedMenu(plan.original.owner, lease: gate.lease!)
                try boundary(); try budget(); try operationStop.check()
                try driver.cancelOwnedMenu(plan.original.owner)
                try driver.verifyMenuClosed(plan.original.owner)
                try boundary(); try budget()
                try operationStop.check()
                var restoring = moved; restoring.phase = .restorePrepared
                retained = try journal.persist(restoring, replacing: moved, boundTo: plan.original.owner)
                try evidence?.append("restore-prepared", restoring)
                try boundary(); try budget()
                try operationStop.check()
                try driver.restore(plan, lease: gate.lease!)
                let returnedPair = try driver.samplePair()
                // Return observations pump the listener too. Exact geometry does not
                // erase input/loss/cancellation after the final mouse pair.
                try boundary(); try budget()
                try operationStop.check()
                let returned = try restoring.confirmedReturned(returnedPair.0, returnedPair.1, now: driver.now)
                let verified = try journal.persist(returned, replacing: restoring, boundTo: plan.original.owner)
                retained = verified
                try evidence?.append("returned", verified) // Durable full return proof BEFORE clear.
                try evidence?.append("complete", ["returnEvidenceComplete": true])
                try boundary(); try budget()
                try operationStop.check()
                try driver.verifyNoUnresolvedDown()
                try journal.clear(verified, boundTo: plan.original.owner)
                retained = nil
                completedFullCycle = true
            } catch { operationStop.request(.failed); throw error }
        }
    }
    private func boundary() throws {
        try operationStop.check()
        // Reading pumps the live tap; its events precede the returned snapshot
        // in the shared sequence. Observe them before acknowledging that sample.
        let sample = input.read()
        for event in input.drainEvents() { try gate.observe(event, now: driver.now) }
        _ = try gate.verifyBoundary(sample, now: driver.now)
        try operationStop.check()
    }
    /// Explicit same-session recovery only. No startup replay or wait for quiet.
    /// A new request must obtain a new idle lease; old owner/scope/anchor proofs
    /// and current menu closure remain mandatory. Interference retains the log.
    func restoreRetained(_ policy: Policy = .disabled, cancelled: () -> Bool = { false }) throws {
        guard policy == .isolatedOwnedFixture else { throw Failure.disabled }
        guard !active else { throw Failure.busy }
        operationStop = MenuBarOperationStop()
        try operationStop.withCancellation(cancelled) {
            input.bindOperationStop(operationStop); driver.bindOperationStop(operationStop)
            defer { input.bindOperationStop(nil); driver.bindOperationStop(nil) }
            do {
                guard evidence?.poisoned != true else { throw MenuBarMoveStageRecorder.Failure.poisoned }
                guard let record = try journal.inspect() else { return }
                retained = record
                active = true; defer { active = false; gate.finish() }
                let start = driver.now
                func budget() throws {
                    try operationStop.check()
                    guard driver.now >= start, driver.now - start <= 5000 else { throw Failure.deadline }
                }
                try budget()
                let pair = try driver.samplePair()
                try budget()
                try driver.verifyNoUnresolvedDown()
                if try MenuBarHiddenMoveModel.inspectRecovery(record, first: pair.0, second: pair.1, now: driver.now) == .originalStateObserved {
                    // Geometry alone cannot discharge an uncertain down route.
                    try driver.verifyNoUnresolvedDown()
                    let returned = try record.confirmedReturned(pair.0, pair.1, now: driver.now)
                    let saved = try journal.persist(returned, replacing: record, boundTo: record.plan.original.owner)
                    try evidence?.append("recovery-original-observed", saved)
                    try budget()
                    try driver.verifyNoUnresolvedDown()
                    try journal.clear(saved, boundTo: record.plan.original.owner); retained = nil; return
                }
                // Visible proof enforces scope continuity, current owner, exact peer
                // permutation and anchor. Unknown menu state cannot trigger an inverse.
                try driver.verifyVisible(record.plan)
                try driver.verifyMenuClosed(record.plan.original.owner)
                try budget()
                let availability = input.read(); _ = input.drainEvents()
                _ = try gate.begin(availability, now: driver.now)
                var restoring = record; restoring.phase = .restorePrepared
                if record.phase != .restorePrepared {
                    restoring = try journal.persist(restoring, replacing: record, boundTo: record.plan.original.owner)
                }
                retained = restoring
                try evidence?.append("recovery-restore-prepared", restoring)
                try boundary(); try budget()
                try driver.restore(record.plan, lease: gate.lease!)
                let returnedPair = try driver.samplePair()
                try boundary(); try budget()
                let returned = try restoring.confirmedReturned(returnedPair.0, returnedPair.1, now: driver.now)
                let verified = try journal.persist(returned, replacing: restoring, boundTo: record.plan.original.owner)
                retained = verified
                try evidence?.append("recovery-returned", verified)
                try boundary(); try budget()
                try driver.verifyNoUnresolvedDown()
                try journal.clear(verified, boundTo: record.plan.original.owner); retained = nil
            } catch { operationStop.request(.failed); throw error }
        }
    }
    /// Restart inspection performs no activation, event replay or automatic move.
    /// New continuity, unknown menu state or incomplete evidence retains the log.
    func inspectRecovery() throws -> MenuBarHiddenMoveModel.RecoveryDisposition? {
        guard !active else { throw Failure.busy }
        guard let record = try journal.inspect() else { retained = nil; return nil }
        retained = record
        let pair = try driver.samplePair()
        return try MenuBarHiddenMoveModel.inspectRecovery(record, first: pair.0, second: pair.1, now: driver.now)
    }
}
