import AppKit
import ApplicationServices

@MainActor
final class MenuBarLiveOperationDriver: MenuBarOperationDriver {
    private let resolveTarget: (MenuBarIconIdentity) throws -> MenuBarStatusTarget
    private let observer = MenuBarReactionObserver()
    init(resolve: @escaping (MenuBarIconIdentity) throws -> MenuBarStatusTarget) { resolveTarget = resolve }
    func resolve(_ identity: MenuBarIconIdentity) throws -> MenuBarStatusTarget { try resolveTarget(identity) }
    func activateAX(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome {
        try context.check()
        guard AXIsProcessTrusted() else { throw MenuBarOperationFailure.permissionUnavailable }
        observer.begin(target)
        // Synchronous AX IPC has bounded messaging timeouts and runs off the UI thread.
        let worker = Task.detached(priority: .userInitiated) { MenuBarAXActivator.activate(target, deadline: context.deadline) }
        let reply = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        try context.check()
        guard AXIsProcessTrusted() else { throw MenuBarOperationFailure.permissionUnavailable }
        if reply.outcome == .refused {
            throw MenuBarOperationFailure.axUnavailable(reply.refusalReason ?? "此图标未提供可核实的辅助功能动作。")
        }
        if reply.outcome != .refused {
            for _ in 0..<3 {
                if observer.reaction(target) { return .observed }
                try await Task.sleep(nanoseconds: 100_000_000)
                try context.check()
            }
        }
        return reply.outcome
    }
    func activateVisible(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarActionOutcome {
        try context.check()
        throw MenuBarOperationFailure.axUnavailable("此版本仅支持辅助功能激活。")
    }
    func prepareReveal(_ target: MenuBarStatusTarget, context: MenuBarOperationContext) async throws -> MenuBarRestoreAnchor {
        try context.check()
        // Deliberate capability gate: no unvalidated targeting shim is shipped.
        throw MenuBarOperationFailure.movementUnavailable
    }
    func reveal(_ target: MenuBarStatusTarget, anchor: MenuBarRestoreAnchor, context: MenuBarOperationContext) async throws {
        throw MenuBarOperationFailure.movementUnavailable
    }
    func interfaceState(_ target: MenuBarStatusTarget) async -> MenuBarInterfaceState { observer.interfaceState(target) }
    func recoveryInterfaceState(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws -> MenuBarInterfaceState {
        try context.check()
        // No production move provider has been validated. Never infer closure
        // from the absence of a pre-crash observer or an old window identifier.
        return .unknown
    }
    func restore(_ record: MenuBarRecoveryRecord, context: MenuBarOperationContext) async throws {
        throw MenuBarOperationFailure.movementUnavailable
    }
}
