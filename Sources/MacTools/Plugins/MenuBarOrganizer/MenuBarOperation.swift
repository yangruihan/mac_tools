import Foundation
import CoreGraphics

enum MenuBarActionOutcome: Equatable {
    case observed, accepted, refused, uncertain
}
enum MenuBarInterfaceState { case open, closed, unknown }
enum MenuBarOperationFailure: Error, Equatable {
    case busy, cancelled, deadline, movementUnavailable, journalUnavailable, recoveryRequired, refused, permissionUnavailable
    case axUnavailable(String)
    var message: String {
        switch self {
        case .axUnavailable(let reason): return reason + " 请展开原生图标后手动操作；本版本不模拟点击或自动搬移。"
        case .permissionUnavailable: return "辅助功能授权已不可用；未继续点击或移动，保持现有配置。"
        case .busy: return "上一项操作或菜单仍在处理中；请结束后重试。"
        case .cancelled: return "环境已变化，已停止后续点击；保持展开。"
        case .deadline: return "操作超过期限，已停止自动重试；保持展开。"
        case .movementUnavailable: return "本版本不支持自动搬移或归位；请展开原生图标后按住 ⌘ 手动排列。"
        case .journalUnavailable: return "无法保存恢复记录；未开始移动。"
        case .recoveryRequired: return "有未完成的布局记录，自动激活已暂停。请先检查原生排列；记录保留，未自动移动或再次激活。"
        case .refused: return "原应用未接受操作；未确认功能已打开。"
        }
    }
}
struct MenuBarOperationContext {
    let generation: UUID
    let deadline: ContinuousClock.Instant
    let currentGeneration: @MainActor () -> UUID
    @MainActor func check() throws {
        try Task.checkCancellation()
        guard currentGeneration() == generation else { throw MenuBarOperationFailure.cancelled }
        guard ContinuousClock.now < deadline else { throw MenuBarOperationFailure.deadline }
    }
}

@MainActor
protocol MenuBarOperationDriver: AnyObject {
    func resolve(_ identity: MenuBarIconIdentity) throws -> MenuBarStatusTarget
    func activateAX(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome
    func activateVisible(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome
    func prepareReveal(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarRestoreAnchor
    func reveal(_ target: MenuBarStatusTarget, anchor: MenuBarRestoreAnchor, context: MenuBarOperationContext) async throws
    func interfaceState(_ target: MenuBarStatusTarget) async -> MenuBarInterfaceState
    func recoveryInterfaceState(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws -> MenuBarInterfaceState
    func restore(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws
}

/// A single owner spans resolution, activation and any compensating move.
/// A third-party interaction keeps a logical lease after event posting has finished.
@MainActor
final class MenuBarOperationCoordinator {
    enum State: Equatable { case idle, resolving, activating, preparing, moving, foreignInteraction, uncertain, recovering, needsRecovery }
    enum Result: Equatable {
        case observed, dispatched, uncertain, failed(String)
    }
    private(set) var state: State = .idle
    private(set) var pending: MenuBarRecoveryRecord?
    private(set) var interaction: MenuBarStatusTarget?
    private(set) var generation = UUID()
    private let driver: MenuBarOperationDriver
    private let journal: MenuBarRecoveryJournal
    private let budget: Duration
    private var executing = false
    private var closedSamples = 0

    init(driver: MenuBarOperationDriver, journal: MenuBarRecoveryJournal, budget: Duration = .seconds(5)) {
        self.driver = driver; self.journal = journal; self.budget = budget
        do {
            pending = try journal.load()
            if pending != nil { state = .needsRecovery }
        } catch { state = .needsRecovery }
    }
    var blocksLayout: Bool { executing || state != .idle }
    func invalidate() {
        generation = UUID()
        // Never forget a compensating move, even when its task is cancelled.
        if pending != nil { state = .needsRecovery }
        else if !executing && interaction == nil { state = .idle }
    }
    // An explicit user reveal can relinquish a non-moving interaction; it
    // never replays activation or discards a pending move.
    func releaseUnmovedInteraction() {
        guard !executing, pending == nil, state != .needsRecovery else { return }
        interaction = nil; state = .idle
    }
    private func context() -> MenuBarOperationContext {
        MenuBarOperationContext(generation: generation, deadline: .now.advanced(by: budget), currentGeneration: { [weak self] in self?.generation ?? UUID() })
    }
    func activate(_ identity: MenuBarIconIdentity) async -> Result {
        guard pending == nil, state != .needsRecovery else { return .failed(MenuBarOperationFailure.recoveryRequired.message) }
        guard !blocksLayout else { return .failed(MenuBarOperationFailure.busy.message) }
        executing = true
        defer { executing = false }
        let ctx = context()
        var activationAttempted = false
        do {
            state = .resolving; try ctx.check()
            var target = try driver.resolve(identity)
            state = .activating
            interaction = target; activationAttempted = true
            let ax = try await driver.activateAX(target, context: ctx)
            try ctx.check()
            if ax != .refused { return handOff(ax, target: target) }
            interaction = nil; activationAttempted = false
            // Fresh resolution is mandatory between providers.
            target = try driver.resolve(identity); try ctx.check()
            interaction = target; activationAttempted = true
            let visible = try await driver.activateVisible(target, context: ctx)
            try ctx.check()
            if visible != .refused { return handOff(visible, target: target) }
            interaction = nil; activationAttempted = false
            state = .preparing
            let anchor = try await driver.prepareReveal(target, context: ctx)
            try ctx.check()
            let record = MenuBarRecoveryRecord(transactionID: UUID(), target: MenuBarRecordedTarget(target), anchor: anchor, phase: .prepared)
            // A prepared record is already a possible move: event posting and
            // filesystem writes cannot be atomic with WindowServer.
            do { try journal.save(record) } catch { throw MenuBarOperationFailure.journalUnavailable }
            pending = record
            state = .moving
            try await driver.reveal(target, anchor: anchor, context: ctx)
            try ctx.check()
            var moved = record; moved.phase = .moved
            pending = moved; try journal.save(moved)
            target = try driver.resolve(identity); try ctx.check()
            state = .activating; interaction = target; activationAttempted = true
            let outcome = try await driver.activateAX(target, context: ctx)
            try ctx.check()
            // Uncertain AX results must never receive a fallback click.
            let final: MenuBarActionOutcome
            if outcome == .refused {
                target = try driver.resolve(identity); try ctx.check()
                final = try await driver.activateVisible(target, context: ctx)
                try ctx.check()
            } else { final = outcome }
            if final == .refused {
                interaction = nil; activationAttempted = false
                try await restorePending()
                return .failed(MenuBarOperationFailure.refused.message)
            }
            return handOff(final, target: target)
        } catch {
            if let failure = error as? MenuBarOperationFailure, case .axUnavailable = failure, pending == nil {
                interaction = nil; state = .idle
                return .failed(failure.message)
            }
            if pending != nil {
                state = .needsRecovery
                // Cancellation can happen after a menu opened. Do not move it
                // merely because the caller lost interest.
                if !activationAttempted { try? await restorePending() }
            } else if activationAttempted {
                state = .uncertain
            } else { state = .idle }
            return .failed((error as? MenuBarOperationFailure)?.message ?? error.localizedDescription)
        }
    }
    private func handOff(_ outcome: MenuBarActionOutcome, target: MenuBarStatusTarget) -> Result {
        interaction = target; closedSamples = 0
        state = outcome == .uncertain ? .uncertain : .foreignInteraction
        switch outcome {
        case .observed: return .observed
        case .accepted: return .dispatched
        case .uncertain: return .uncertain
        case .refused: return .failed(MenuBarOperationFailure.refused.message)
        }
    }
    /// Unknown is deliberately not closed. A caller may poll while a menu exists.
    func settle() async {
        guard !executing, let target = interaction else { return }
        guard await driver.interfaceState(target) == .closed else { closedSamples = 0; return }
        closedSamples += 1
        guard closedSamples >= 2 else { return }
        interaction = nil
        if pending != nil { try? await restorePending() }
        else { state = .idle }
    }
    /// Only a menu with confirmed absence can release an uncertain lease.
    func recover() async throws {
        guard !executing else { throw MenuBarOperationFailure.busy }
        if let target = interaction, await driver.interfaceState(target) != .closed {
            throw MenuBarOperationFailure.recoveryRequired
        }
        interaction = nil
        if pending == nil {
            // A corrupt journal remains a blocker: it is not silently deleted.
            if state == .needsRecovery { throw MenuBarOperationFailure.recoveryRequired }
            state = .idle; return
        }
        try await restorePending()
    }
    private func restorePending() async throws {
        guard let record = pending else { return }
        state = .recovering
        // Recovery gets a fresh bounded transaction, never another activation.
        let ctx = context()
        do {
            try ctx.check()
            // A restarted manager has no interaction lease. The persisted
            // record still requires a fresh interface check before any move.
            guard try await driver.recoveryInterfaceState(record, context: ctx) == .closed else {
                throw MenuBarOperationFailure.recoveryRequired
            }
            try ctx.check()
            try await driver.restore(record, context: ctx)
            try ctx.check()
            try journal.clear()
            pending = nil; state = .idle
        } catch { state = .needsRecovery; throw error }
    }
}
