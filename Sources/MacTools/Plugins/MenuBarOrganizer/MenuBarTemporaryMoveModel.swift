import Foundation
import CoreGraphics

/// A value-only contract for a future, visible self-owned-item experiment.
/// No runtime constructs this model, and it has no event, AX or journal driver.
enum MenuBarTemporaryMoveModel {
    static let backendEnabled = false
    enum OnScreen: String, Codable { case ordered, missing, falseValue, malformed }
    enum Interface: String, Codable { case closed, open, unknown }
    struct Access: Equatable {
        var ax: Bool
        var post: Bool
        var interferenceObservation: Bool
        var permitsModel: Bool { ax && post && interferenceObservation }
    }
    struct Scope: Codable, Equatable {
        let continuity: UUID // Fresh after observer/process loss; not a public Space ID.
        let spaceEpoch: UUID
        let displayUUID: String
        let displayID: UInt32
        let scale: Double
        let rotation: Double
        let frame: CGRect
        let leftSafe: CGRect
        let rightSafe: CGRect
        let frontPID: Int32
        let frontApplication: MenuBarApplicationIdentity
    }
    struct Owner: Codable, Equatable {
        let nonce: UUID
        let itemInstance: UUID
        let itemKey: String
        let signedIdentifier: String
        let team: String
        let codeHash: String
        let target: MenuBarRecordedTarget
    }
    struct Window: Codable, Equatable {
        let identity: MenuBarRecordedTarget
        var frame: CGRect
        var button: CGRect
        var onScreen: OnScreen
        var listedOnScreen: Bool
        var alpha: Double
        var ownerOcclusionVisible: Bool? // Required for the self-owned target.
    }
    struct Sample: Codable, Equatable {
        var sequence: UInt64
        var uptimeMilliseconds: UInt64
        let scope: Scope
        let owner: Owner
        var windows: [Window] // Complete same-row inventory, never hidden-filtered.
        let recovery: MenuBarRecordedTarget
        let applicationMenu: CGRect
        var overlays: [CGRect]
        var interface: Interface
        var inputIdle: Bool
        var interferenceEpoch: UUID
        func sameFacts(as other: Sample) -> Bool {
            var a = self, b = other
            a.sequence = 0; b.sequence = 0
            a.uptimeMilliseconds = 0; b.uptimeMilliseconds = 0
            return a == b
        }
    }
    enum Failure: Error, Equatable {
        case busy, permissions, unstable, invalidGeometry, identity, targetNotVisible
        case incompleteOrder, noCapacity, environment, interference, deadline
        case unexpectedOrder, staleReceipt, journal, phase, recoveryAmbiguous
    }
    struct Plan: Codable, Equatable {
        let original: Sample
        let reservationWidth: Double
        let rightInset: Double
        let shownOrder: [MenuBarRecordedTarget]
        var originalOrder: [MenuBarRecordedTarget] { original.windows.map(\.identity) }
        static func make(_ a: Sample, _ b: Sample, access: Access, now: UInt64,
                         reservationWidth: Double, rightInset: Double = 20) throws -> Plan {
            guard access.permitsModel else { throw Failure.permissions }
            try stable(a, b, now: now)
            try validate(b)
            guard b.interface == .closed else { throw Failure.recoveryAmbiguous }
            let order = try insertionOrder(b, reservationWidth: reservationWidth, rightInset: rightInset)
            return Plan(original: b, reservationWidth: reservationWidth, rightInset: rightInset, shownOrder: order)
        }
        func validateStructure() throws {
            try Self.validate(original)
            guard original.interface == .closed,
                  try Self.insertionOrder(original, reservationWidth: reservationWidth, rightInset: rightInset) == shownOrder
            else { throw Failure.journal }
        }
        private static func insertionOrder(_ b: Sample, reservationWidth: Double, rightInset: Double) throws -> [MenuBarRecordedTarget] {
            guard reservationWidth.isFinite, rightInset.isFinite, rightInset >= 0,
                  let target = b.windows.first(where: { $0.identity == b.owner.target }),
                  reservationWidth >= Double(target.frame.width) else { throw Failure.invalidGeometry }
            guard !b.scope.rightSafe.contains(target.button) else { throw Failure.noCapacity }
            let rightPeers = b.windows.filter { $0.frame.minX >= b.scope.rightSafe.minX }
            guard let first = rightPeers.first,
                  Double(first.frame.minX - b.scope.rightSafe.minX) >= reservationWidth + rightInset,
                  let recovery = b.windows.first(where: { $0.identity == b.recovery }),
                  b.scope.rightSafe.contains(recovery.button),
                  recovery.frame.minX - CGFloat(reservationWidth) >= b.scope.rightSafe.minX + CGFloat(rightInset)
            else { throw Failure.noCapacity }
            var order = b.windows.map(\.identity).filter { $0 != b.owner.target }
            guard let index = order.firstIndex(of: b.recovery) else { throw Failure.identity }
            order.insert(b.owner.target, at: index)
            return order
        }
        func check(_ sample: Sample, restored: Bool) throws {
            try validateStructure()
            try Self.validate(sample)
            guard sample.scope == original.scope else { throw Failure.environment }
            guard sample.owner == original.owner, sample.recovery == original.recovery,
                  sample.windows.count == original.windows.count,
                  Set(sample.windows.map { $0.identity.windowID }) == Set(original.windows.map { $0.identity.windowID }),
                  sample.windows.allSatisfy({ w in original.windows.contains(where: { $0.identity == w.identity }) })
            else { throw Failure.identity }
            guard sample.interferenceEpoch == original.interferenceEpoch else { throw Failure.interference }
            let order = sample.windows.map(\.identity)
            guard order == (restored ? originalOrder : shownOrder) else { throw Failure.unexpectedOrder }
            guard sample.applicationMenu == original.applicationMenu,
                  let target = sample.windows.first(where: { $0.identity == original.owner.target }),
                  let recovery = sample.windows.first(where: { $0.identity == original.recovery }),
                  let oldRecovery = original.windows.first(where: { $0.identity == original.recovery }),
                  close(recovery.frame, oldRecovery.frame), close(recovery.button, oldRecovery.button),
                  sample.windows.allSatisfy({ window in
                      guard let old = original.windows.first(where: { $0.identity == window.identity }) else { return false }
                      return abs(window.frame.width - old.frame.width) <= 1 && abs(window.frame.height - old.frame.height) <= 1
                          && abs(window.button.width - old.button.width) <= 1 && abs(window.button.height - old.button.height) <= 1
                  }) else { throw Failure.invalidGeometry }
            if restored {
                guard sample.windows.allSatisfy({ window in
                    guard let old = original.windows.first(where: { $0.identity == window.identity }) else { return false }
                    return close(window.frame, old.frame) && close(window.button, old.button)
                }) else { throw Failure.recoveryAmbiguous }
            } else {
                let slot = sample.scope.rightSafe.insetBy(dx: 0, dy: 0)
                guard target.button.minX >= slot.minX + CGFloat(rightInset), slot.contains(target.button),
                      !target.button.intersects(recovery.button) else { throw Failure.noCapacity }
            }
        }
        private static func validate(_ sample: Sample) throws {
            let s = sample.scope
            guard !s.displayUUID.isEmpty, s.displayID > 0, s.scale.isFinite, s.scale > 0,
                  s.rotation.isFinite, valid(s.frame), valid(s.leftSafe), valid(s.rightSafe),
                  s.frame.contains(s.leftSafe), s.frame.contains(s.rightSafe), s.leftSafe.maxX < s.rightSafe.minX,
                  valid(sample.applicationMenu), sample.windows.count >= 2, sample.windows.count <= 128,
                  sample.overlays.allSatisfy(valid),
                  sample.windows.allSatisfy({ valid($0.frame) && valid($0.button) && $0.frame.contains($0.button)
                      && $0.frame.height < 64 && abs($0.frame.minY - s.frame.minY) < 1
                      && s.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) })
            else { throw Failure.invalidGeometry }
            guard sample.inputIdle else { throw Failure.interference }
            guard ["mactools_native_acceptance_T", "mactools_native_acceptance_N"].contains(sample.owner.itemKey),
                  !sample.owner.team.isEmpty, !sample.owner.codeHash.isEmpty,
                  sample.owner.signedIdentifier == "com.ryanai.mactools.nativetargets",
                  let app = sample.owner.target.application, app.bundleID == sample.owner.signedIdentifier,
                  !app.bundlePath.isEmpty, app.launch.isFinite, app.launch > 0,
                  sample.owner.target.pid > 0, sample.owner.target.windowID > 0, sample.recovery != sample.owner.target,
                  s.frontPID > 0, s.frontApplication.launch.isFinite, s.frontApplication.launch > 0,
                  !s.frontApplication.bundleID.isEmpty, !s.frontApplication.bundlePath.isEmpty,
                  Set(sample.windows.map { $0.identity.windowID }).count == sample.windows.count,
                  sample.windows.allSatisfy({ w in
                      guard let app = w.identity.application else { return false }
                      return w.identity.windowID > 0 && w.identity.pid > 0 && app.launch.isFinite && app.launch > 0
                          && !app.bundleID.isEmpty && !app.bundlePath.isEmpty
                  }), sample.windows.contains(where: { $0.identity == sample.recovery }),
                  let target = sample.windows.first(where: { $0.identity == sample.owner.target })
            else { throw Failure.identity }
            guard target.onScreen == .ordered, target.listedOnScreen, target.ownerOcclusionVisible == true,
                  target.alpha.isFinite, target.alpha > 0,
                  (s.leftSafe.contains(target.button) || s.rightSafe.contains(target.button)),
                  !sample.applicationMenu.intersects(target.button),
                  !sample.overlays.contains(where: { $0.intersects(target.button) })
            else { throw Failure.targetNotVisible }
            // A future provider must supply the complete inventory. This initial
            // model cannot establish hidden peers' order, so it never drops them.
            guard sample.windows.allSatisfy({ window in
                window.onScreen == .ordered && window.listedOnScreen && window.alpha.isFinite && window.alpha > 0
                    && (s.leftSafe.contains(window.button) || s.rightSafe.contains(window.button))
                    && !sample.applicationMenu.intersects(window.button)
                    && !sample.overlays.contains(where: { $0.intersects(window.button) })
            })
            else { throw Failure.incompleteOrder }
            for (left, right) in zip(sample.windows, sample.windows.dropFirst()) {
                guard left.frame.maxX <= right.frame.minX else { throw Failure.incompleteOrder }
            }
            guard let recovery = sample.windows.first(where: { $0.identity == sample.recovery }),
                  s.rightSafe.contains(recovery.button), !sample.applicationMenu.intersects(recovery.button),
                  !sample.overlays.contains(where: { $0.intersects(recovery.button) })
            else { throw Failure.noCapacity }
        }
    }
    struct Record: Codable, Equatable {
        enum Phase: String, Codable { case prepared, moved, restorePrepared, restored }
        let schemaVersion: Int
        let transaction: UUID
        let plan: Plan
        var phase: Phase
    }
    enum Action: Equatable {
        case persist(Record), modelRelocateOnce, observeInterface, modelRestoreOnce, clearJournal, none
    }
    struct Machine {
        enum State: Equatable { case idle, prepared, moving, persistingMoved, shown, waitingForClose
            case persistingRestore, restoring, persistingRestored, clearing, needsRecovery }
        private(set) var state: State = .idle
        private(set) var pending: Record?
        private(set) var lastFailure: Failure?
        private var deadline: UInt64 = 0
        private var proof: Sample?
        private var lastSequence: UInt64 = 0
        private var relocationConsumed = false
        private var restorationConsumed = false
        init(pending: Record? = nil) {
            self.pending = pending
            if let pending { state = .needsRecovery; lastSequence = pending.plan.original.sequence }
        }
        mutating func begin(_ a: Sample, _ b: Sample, access: Access, now: UInt64,
                            budget: UInt64 = 5000, reservationWidth: Double) throws -> Action {
            guard state == .idle, pending == nil else { throw Failure.busy }
            let plan = try Plan.make(a, b, access: access, now: now, reservationWidth: reservationWidth)
            deadline = try expiry(now, budget)
            let record = Record(schemaVersion: 1, transaction: UUID(), plan: plan, phase: .prepared)
            pending = record; state = .prepared
            lastSequence = b.sequence
            return .persist(record)
        }
        mutating func persisted(_ receipt: Record, live: Sample, access: Access, now: UInt64) throws -> Action {
            guard let record = pending, receipt == record else { throw Failure.staleReceipt }
            do {
                try checkBudget(now, access)
                try fresh(live, now: now)
                guard live.sequence > lastSequence else { throw Failure.unstable }
                lastSequence = live.sequence
                switch state {
                case .prepared:
                    try record.plan.check(live, restored: true)
                    guard live.interface == .closed, !relocationConsumed else { throw Failure.phase }
                    relocationConsumed = true; state = .moving
                    return .modelRelocateOnce
                case .persistingMoved:
                    try record.plan.check(live, restored: false)
                    state = live.interface == .closed ? .shown : .waitingForClose
                    return live.interface == .closed ? .none : .observeInterface
                case .persistingRestore:
                    try record.plan.check(live, restored: false)
                    guard live.interface == .closed, !restorationConsumed else { throw Failure.phase }
                    restorationConsumed = true; state = .restoring
                    return .modelRestoreOnce
                case .persistingRestored:
                    try record.plan.check(live, restored: true)
                    guard live.interface == .closed else { throw Failure.phase }
                    state = .clearing
                    return .clearJournal
                default: throw Failure.phase
                }
            } catch { block(error); throw error }
        }
        mutating func observedMove(_ sample: Sample, access: Access, now: UInt64) throws -> Action {
            guard state == .moving, var record = pending else { throw Failure.phase }
            do {
                try checkBudget(now, access); try fresh(sample, now: now)
                guard sample.sequence > lastSequence else { throw Failure.unstable }
                lastSequence = sample.sequence
                try record.plan.check(sample, restored: false)
                if let first = proof { try stable(first, sample, now: now) }
                else { proof = sample; return .none }
                proof = nil; record.phase = .moved; pending = record; state = .persistingMoved
                return .persist(record)
            } catch { block(error); throw error }
        }
        mutating func requestReturn(_ a: Sample, _ b: Sample, access: Access, now: UInt64,
                                    budget: UInt64 = 5000) throws -> Action {
            guard var record = pending, [.shown, .waitingForClose, .needsRecovery].contains(state) else { throw Failure.phase }
            do {
                guard record.schemaVersion == 1 else { throw Failure.journal }
                try record.plan.validateStructure()
                guard access.permitsModel else { throw Failure.permissions }
                try stable(a, b, now: now)
                guard a.sequence > lastSequence else { throw Failure.unstable }
                lastSequence = b.sequence
                guard b.scope == record.plan.original.scope else { throw Failure.environment }
                deadline = try expiry(now, budget)
                if a.interface != .closed || b.interface != .closed {
                    state = .waitingForClose; return .observeInterface
                }
                let order = b.windows.map(\.identity)
                if order == record.plan.originalOrder {
                    try record.plan.check(b, restored: true)
                    record.phase = .restored; pending = record; state = .persistingRestored
                    return .persist(record)
                }
                try record.plan.check(b, restored: false)
                guard record.phase != .restorePrepared, record.phase != .restored, !restorationConsumed else {
                    throw Failure.recoveryAmbiguous
                }
                record.phase = .restorePrepared; pending = record; state = .persistingRestore
                return .persist(record)
            } catch { block(error); throw error }
        }
        mutating func observedRestore(_ sample: Sample, access: Access, now: UInt64) throws -> Action {
            guard state == .restoring, var record = pending else { throw Failure.phase }
            do {
                try checkBudget(now, access); try fresh(sample, now: now)
                guard sample.sequence > lastSequence else { throw Failure.unstable }
                lastSequence = sample.sequence
                guard sample.interface == .closed else { throw Failure.phase }
                try record.plan.check(sample, restored: true)
                if let first = proof { try stable(first, sample, now: now) }
                else { proof = sample; return .none }
                proof = nil; record.phase = .restored; pending = record; state = .persistingRestored
                return .persist(record)
            } catch { block(error); throw error }
        }
        mutating func cleared(transaction: UUID) throws {
            guard state == .clearing, pending?.transaction == transaction, pending?.phase == .restored else {
                throw Failure.staleReceipt
            }
            pending = nil; proof = nil; state = .idle
            relocationConsumed = false; restorationConsumed = false; lastFailure = nil
        }
        mutating func invalidate(_ failure: Failure) {
            lastFailure = failure; proof = nil
            state = pending == nil ? .idle : .needsRecovery
        }
        private mutating func block(_ error: Error) { invalidate((error as? Failure) ?? .journal) }
        private func checkBudget(_ now: UInt64, _ access: Access) throws {
            guard access.permitsModel else { throw Failure.permissions }
            guard now < deadline else { throw Failure.deadline }
        }
    }
    private static func expiry(_ now: UInt64, _ budget: UInt64) throws -> UInt64 {
        let (end, overflow) = now.addingReportingOverflow(budget)
        guard budget > 0, budget <= 30_000, !overflow else { throw Failure.deadline }
        return end
    }
    private static func fresh(_ sample: Sample, now: UInt64) throws {
        guard sample.uptimeMilliseconds <= now, now - sample.uptimeMilliseconds <= 250 else { throw Failure.unstable }
    }
    private static func stable(_ a: Sample, _ b: Sample, now: UInt64) throws {
        try fresh(b, now: now)
        guard b.sequence > a.sequence, b.uptimeMilliseconds >= a.uptimeMilliseconds,
              b.uptimeMilliseconds - a.uptimeMilliseconds >= 100,
              b.uptimeMilliseconds - a.uptimeMilliseconds <= 500, a.sameFacts(as: b) else { throw Failure.unstable }
    }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
    }
    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX, a.minY, a.width, a.height], [b.minX, b.minY, b.width, b.height]).allSatisfy { abs($0 - $1) <= 1 }
    }
}
