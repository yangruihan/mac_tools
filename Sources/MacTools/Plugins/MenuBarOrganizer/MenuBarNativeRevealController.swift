import Foundation
import CoreGraphics
import Combine

struct MenuBarOwnedWidthState: Equatable {
    let binding: MenuBarOwnedWidthBinding
    let length: CGFloat
    let effectiveLength: CGFloat
    let backingFrame: CGRect
    let environment: UUID
}
@MainActor
protocol MenuBarNativeRevealWidthDriver: AnyObject {
    func widthState() throws -> MenuBarOwnedWidthState
    func observe(_ identity: MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation
    func setLength(_ length: CGFloat, matching binding: MenuBarOwnedWidthBinding) throws
    func verifyRestorationSafety() async throws
}

/// Own-length effects only. The main plugin binds this controller exclusively
/// in an explicitly enabled preview bundle; ordinary builds keep the gate off.
@MainActor
final class MenuBarNativeRevealController: ObservableObject {
    enum State: String { case idle, preparing, revealing, ready, restoring, needsRecovery }
    enum EndReason: String { case completed, cancelled, environmentChanged, timeout, failed, shutdown }
    enum Failure: String, Error, Equatable, MenuBarNativeDiagnosticError {
        case busy, cancelled, staleObservation, wrongOwner, recoveryRequired, restorationUnverified, environmentChanged, timeout
        var diagnosticCode: String { "controller.\(rawValue)" }
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var status = "选择图标后检查是否有足够的可见空间。"
    private(set) var diagnostic = MenuBarNativeRevealDiagnostic(transaction: UUID())
    private(set) var diagnosticWriteFailed = false
    let diagnosticURL: URL?
    private var diagnosticStage = "idle"
    private var diagnosticStartedAt = ProcessInfo.processInfo.systemUptime
    private(set) var pending: MenuBarOwnedWidthRecord?
    private let driver: MenuBarNativeRevealWidthDriver
    private let journal: MenuBarOwnedWidthJournal
    private let sampleDelay: Duration
    private let editingBudget: Duration
    private let preparationBudget: Duration
    private var operation = UUID()
    private var activeBinding: MenuBarOwnedWidthBinding?
    private var watchdog: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var restorationWork: Task<Void, Never>?

    init(driver: MenuBarNativeRevealWidthDriver, journal: MenuBarOwnedWidthJournal,
         sampleDelay: Duration = .milliseconds(200), editingBudget: Duration = .seconds(30), preparationBudget: Duration = .seconds(5), diagnosticURL: URL? = nil) {
        self.driver = driver; self.journal = journal; self.diagnosticURL = diagnosticURL
        self.sampleDelay = sampleDelay; self.editingBudget = editingBudget
        self.preparationBudget = preparationBudget
        do {
            pending = try journal.load()
            if pending != nil { state = .needsRecovery; status = "上次临时宽度尚未确认恢复，请先恢复自有间隔。" }
        } catch { diagnosticStage = "journal.load"; state = .needsRecovery; record("failure", error: error); status = "宽度恢复记录不可读取，操作已暂停。" }
    }

    @discardableResult
    func begin(_ identity: MenuBarIconIdentity) async -> Bool {
        guard state == .idle, pending == nil else { return false }
        operation = UUID(); let token = operation
        diagnostic = MenuBarNativeRevealDiagnostic(transaction: token, targetWindowID: identity.windowID, targetPID: identity.pid)
        diagnosticStartedAt = ProcessInfo.processInfo.systemUptime; diagnosticWriteFailed = false
        diagnosticStage = "before.first.width"
        state = .preparing; status = "正在核实目标、可见空间和恢复入口…"
        armWatchdog(token: token, budget: preparationBudget)
        var postcheck: MenuBarNativeRevealDiagnostic.PostcheckDetail?
        do {
            let width = try driver.widthState(); record("width", width: width)
            diagnosticStage = "before.first.observe"
            let first = try await driver.observe(identity); try check(token); record("observation", sample: .init(first))
            diagnosticStage = "before.first.verify"
            guard width == (try driver.widthState()), first.generation == width.environment,
                  first.ownedSpacer == width.backingFrame,
                  first.target.id == identity.windowID, first.target.pid == identity.pid,
                  first.target.application == identity.application else { throw Failure.staleObservation }
            diagnosticStage = "plan.make"
            let plan = try MenuBarNativeRevealPlan.make(first)
            record("planned:\(plan.purpose.rawValue)")
            try await pause(); try check(token)
            diagnosticStage = "before.second.observe"
            let second = try await driver.observe(identity); try check(token); record("observation", sample: .init(second))
            diagnosticStage = "before.second.verify"
            guard second == first, try driver.widthState() == width else { throw Failure.staleObservation }
            let proposed = width.effectiveLength + plan.requestedExtraLength
            guard proposed.isFinite, proposed >= 0, proposed <= 2048 else { throw Failure.staleObservation }
            let record = MenuBarOwnedWidthRecord(schemaVersion: 1, transaction: token, binding: width.binding,
                originalLength: Double(width.length), originalBackingWidth: Double(width.backingFrame.width), environment: width.environment)
            diagnosticStage = "journal.save"
            try journal.save(record) // Durable before the only effect; a throwing setter may still have applied.
            pending = record; activeBinding = width.binding; state = .revealing
            status = "仅调整自有占位；核实完整显示前，请勿操作目标图标。"
            diagnosticStage = "width.apply"
            try driver.setLength(proposed, matching: width.binding)
            self.record("applied", width: try? driver.widthState())
            try await pause(); try check(token)
            diagnosticStage = "after.first.observe"
            let after = try await driver.observe(identity); try check(token); self.record("observation", sample: .init(after))
            diagnosticStage = "after.first.verify"
            postcheck = .init(before: plan.before, after: after)
            try plan.verify(after); self.record("verified")
            postcheck = nil
            try await pause(); try check(token)
            diagnosticStage = "after.second.observe"
            let confirmed = try await driver.observe(identity); try check(token); self.record("observation", sample: .init(confirmed))
            diagnosticStage = "after.second.verify"
            postcheck = .init(before: plan.before, after: confirmed)
            try plan.verify(confirmed); self.record("verified")
            guard confirmed == after, try driver.widthState().binding == width.binding else { throw Failure.staleObservation }
            postcheck = nil
            diagnosticStage = "ready"; state = .ready; self.record("confirmed"); status = "目标已在当前可见区域完整露出；可手动排列，完成或取消后恢复间隔宽度。"
            armWatchdog(token: token, budget: editingBudget)
            monitor = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard let self, self.operation == token, self.state == .ready else { return }
                    do {
                        self.diagnosticStage = "editing.observe"
                        let current = try await self.driver.observe(identity)
                        guard self.operation == token, self.state == .ready else { return }
                        self.record("observation", sample: .init(current)); self.diagnosticStage = "editing.verify"
                        try plan.verifyEditing(current, confirmed: confirmed)
                    } catch {
                        guard self.operation == token else { return }
                        self.record("failure", error: error, persist: false)
                        await self.end(.failed); return
                    }
                }
            }
            return true
        } catch {
            guard operation == token else { return false }
            record("failure", error: error, postcheck: postcheck, persist: false)
            watchdog?.cancel(); watchdog = nil
            if pending != nil { await end(.failed) }
            else { state = .idle; record("refused") }
            if state != .needsRecovery {
                status = (error as? LocalizedError)?.errorDescription ?? "目标没有通过身份、空间或稳定性检查；未继续操作。"
            }
            return false
        }
    }

    /// Invalidates pending awaits before immediately requesting original length.
    /// Geometry acknowledgement follows; a failed acknowledgement retains recovery.
    func end(_ reason: EndReason) async {
        await requestEnd(reason)?.value
    }
    @discardableResult
    func requestEnd(_ reason: EndReason) -> Task<Void, Never>? {
        if state == .restoring { return restorationWork }
        // Capture interruptions even when they invalidate a still-pending await.
        if reason == .environmentChanged || reason == .timeout {
            record(reason.rawValue, error: reason == .timeout ? Failure.timeout : Failure.environmentChanged, persist: false)
        } else { record(reason.rawValue, persist: false) }
        operation = UUID(); let token = operation
        watchdog?.cancel(); watchdog = nil
        monitor?.cancel(); monitor = nil
        guard let record = pending else { if state != .needsRecovery { state = .idle }; persistDiagnostic(); return nil }
        state = .restoring
        let binding = activeBinding ?? record.binding
        do {
            diagnosticStage = "restore.setLength"
            try driver.setLength(CGFloat(record.originalLength), matching: binding)
            self.record("restore-requested")
        } catch { self.record("failure", error: error); restoreFailed(); return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                await self.restorationPause(); guard token == self.operation else { return }
                self.diagnosticStage = "restore.first.width"
                let first = try self.driver.widthState(); self.record("width", width: first)
                try self.verifyRestore(first, record: record, binding: binding)
                self.diagnosticStage = "restore.first.safety"
                try await self.driver.verifyRestorationSafety(); guard token == self.operation else { return }
                await self.restorationPause(); guard token == self.operation else { return }
                self.diagnosticStage = "restore.second.width"
                let second = try self.driver.widthState(); self.record("width", width: second)
                try self.verifyRestore(second, record: record, binding: binding)
                self.diagnosticStage = "restore.second.safety"
                try await self.driver.verifyRestorationSafety(); guard token == self.operation else { return }
                guard first == second else { throw Failure.restorationUnverified }
                self.diagnosticStage = "restore.clearJournal"
                try self.journal.clear(); self.pending = nil; self.activeBinding = nil; self.state = .idle
                self.record("restored")
                self.status = reason == .completed ? "已恢复间隔宽度；手动排列的位置由系统保留。" : "已恢复间隔宽度；没有撤销手动排列的位置。"
            } catch { if token == self.operation { self.record("failure", error: error); self.restoreFailed() } }
            if token == self.operation { self.restorationWork = nil }
        }
        restorationWork = task
        return task
    }
    private func restoreFailed() {
        state = .needsRecovery; record("recovery-required"); status = "自有宽度或恢复入口尚未确认恢复；记录保留，其他操作已暂停。"
    }

    func environmentChanged() async { await end(.environmentChanged) }

    /// A new process may restore only its explicitly owned item with the same
    /// app path/bundle and item key. It never applies old third-party geometry.
    func recoverOwnWidth() async {
        guard state == .needsRecovery, let record = pending else { return }
        diagnosticStage = "recovery.verifyOwner"
        do {
            let current = try driver.widthState()
            guard current.binding.itemKey == record.binding.itemKey,
                  current.binding.application.sameApplication(record.binding.application) else { throw Failure.wrongOwner }
            activeBinding = current.binding
            await end(.failed)
        } catch { self.record("failure", error: error); status = "恢复记录与当前自有间隔不匹配，未修改宽度。" }
    }

    /// Synchronous termination hook. If physical reflow is not yet confirmed,
    /// retain the journal for the next explicitly owned instance to recover.
    func shutdown() {
        diagnosticStage = "shutdown"; record("shutdown")
        operation = UUID(); watchdog?.cancel(); watchdog = nil
        monitor?.cancel(); monitor = nil
        guard let record = pending else { return }
        do {
            let binding = activeBinding ?? record.binding
            try driver.setLength(CGFloat(record.originalLength), matching: binding)
            try verifyRestore(driver.widthState(), record: record, binding: binding)
            // Termination cannot await two stable samples. Keep the record even
            // after an immediate match; next launch acknowledges before clearing.
            state = .needsRecovery
        } catch { self.record("failure", error: error); state = .needsRecovery }
        self.record("shutdown-record-retained")
    }
    func recordLiveObservation(transaction: UUID?, phase: String, sample: MenuBarNativeRevealDiagnostic.Sample) {
        guard transaction == diagnostic.transaction else { return }
        record(phase, sample: sample)
    }
    private func record(_ event: String, error: Error? = nil,
                        sample: MenuBarNativeRevealDiagnostic.Sample? = nil, width: MenuBarOwnedWidthState? = nil,
                        postcheck: MenuBarNativeRevealDiagnostic.PostcheckDetail? = nil, persist: Bool = true) {
        diagnostic.append(stage: diagnosticStage, event: event, state: state.rawValue,
            elapsed: max(0, (ProcessInfo.processInfo.systemUptime - diagnosticStartedAt) * 1000),
            error: error, sample: sample, width: width, postcheck: postcheck)
        if persist { persistDiagnostic() }
    }
    private func persistDiagnostic() {
        guard let diagnosticURL else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(diagnostic).write(to: diagnosticURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: diagnosticURL.path)
        } catch { diagnosticWriteFailed = true } // Logging cannot cancel restoration or authorize effects.
    }
    private func verifyRestore(_ width: MenuBarOwnedWidthState, record: MenuBarOwnedWidthRecord,
                               binding: MenuBarOwnedWidthBinding) throws {
        guard width.binding == binding, width.length == CGFloat(record.originalLength),
              width.backingFrame.width.isFinite, width.backingFrame.width > 0,
              abs(width.backingFrame.width - CGFloat(record.originalBackingWidth)) <= 1 else {
            throw Failure.restorationUnverified
        }
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard operation == token else { throw Failure.cancelled }
    }
    private func pause() async throws { try await Task.sleep(for: sampleDelay) }
    private func restorationPause() async {
        // A cancelled caller still owes restoration acknowledgement.
        let delay = sampleDelay
        _ = await Task.detached { try? await Task.sleep(for: delay) }.value
    }
    private func armWatchdog(token: UUID, budget: Duration) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: budget) } catch { return }
            guard let self, self.operation == token else { return }
            await self.end(.timeout)
        }
    }
}
