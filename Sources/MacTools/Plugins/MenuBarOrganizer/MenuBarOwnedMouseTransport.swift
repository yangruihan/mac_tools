// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE. Linked packet adapter is GPLv3.
import Foundation
import ApplicationServices

protocol MenuBarOwnedEventChannel: AnyObject {
    var privateEventSource: CGEventSource { get }
    var needsRelease: Bool { get }
    func authorize(_ lease: MenuBarMoveInterference.Lease?) throws
    func emit(_ event: CGEvent, gesture: UUID) throws
    /// Records unresolved down responsibility; the native channel sends no cleanup.
    func release(_ event: CGEvent, gesture: UUID)
    func bindOperationStop(_ stop: MenuBarOperationStop?)
}
extension MenuBarOwnedEventChannel {
    var needsRelease: Bool { true }
    func authorize(_ lease: MenuBarMoveInterference.Lease?) throws {}
    func bindOperationStop(_ stop: MenuBarOperationStop?) {}
}
final class MenuBarOwnedMouseTransport {
    enum Failure: Error { case disabled, busy }
    enum Policy { case disabled, isolatedOwnedFixture }
    let channel: any MenuBarOwnedEventChannel
    private(set) var active = false
    private var operationStop: MenuBarOperationStop?
    func bindOperationStop(_ stop: MenuBarOperationStop?) {
        operationStop = stop; channel.bindOperationStop(stop)
    }
    private var serial: Int64 = 1
    private var nextEventNumber: Int16
    init(channel: any MenuBarOwnedEventChannel, firstEventNumber: Int16 = 1) {
        self.channel = channel; nextEventNumber = firstEventNumber
    }
    func pair(pid: Int32, downWindow: UInt32, upWindow: UInt32, start: CGPoint, end: CGPoint,
              command: Bool, gesture: UUID, lease: MenuBarMoveInterference.Lease? = nil, policy: Policy = .disabled) throws {
        guard policy == .isolatedOwnedFixture else { throw Failure.disabled }
        guard !active else { throw Failure.busy }
        try operationStop?.check()
        try channel.authorize(lease)
        active = true; defer { active = false }
        // A down/up pair shares its mouse number; the source marker remains
        // unique per packet. Wrap in the native signed domain, never normalize
        // a received event to manufacture an exact attribution match.
        let number = Int64(nextEventNumber); nextEventNumber = nextEventNumber &+ 1
        let down = try packet(.leftMouseDown, start, pid, downWindow, command, number)
        let up = try packet(.leftMouseUp, end, pid, upWindow, command, number)
        // The native channel records this bound possible-down responsibility;
        // failure never grants an implicit cleanup post, fallback or inverse.
        let release = try packet(.leftMouseUp, start, pid, downWindow, command, number)
        var completed = false
        defer { if !completed && channel.needsRelease { channel.release(release, gesture: gesture) } }
        try operationStop?.check()
        try channel.emit(down, gesture: gesture)
        try operationStop?.check()
        try channel.emit(up, gesture: gesture)
        completed = true
    }
    private func packet(_ type: CGEventType, _ point: CGPoint, _ pid: Int32, _ window: UInt32, _ command: Bool, _ number: Int64) throws -> CGEvent {
        serial += 1
        return try IceOwnedMouseEvent.make(type: type, point: point, pid: pid, window: window,
            command: command, marker: serial, number: number, source: channel.privateEventSource)
    }
}

/// Injectable seams replace observations and posts for offline tests. Native
/// defaults retain the existing permission, exact receipt and ANY/age checks.
protocol MenuBarOwnedEventInput: MenuBarMoveInterferenceSource {
    var privateEventSource: CGEventSource { get }
    var monitoringHealthy: Bool { get }
    func registerForReceipt(_ event: CGEvent, gesture: UUID, expectedEpoch: UUID?, expectedContinuity: UUID?) throws -> MenuBarListenOnlyInterferenceSource.Ticket
    func receipt(_ ticket: MenuBarListenOnlyInterferenceSource.Ticket) -> MenuBarListenOnlyInterferenceSource.Receipt
    func abandonReceipt()
}
extension MenuBarListenOnlyInterferenceSource: MenuBarOwnedEventInput {
    var monitoringHealthy: Bool { diagnostics().monitoringHealthy }
}

/// Possible-effect bookkeeping, never proof that a physical button is up.
struct MenuBarOwnedDownResponsibility: Codable {
    enum Phase: String, Codable { case possibleDown, upAttempted, pairDelivered, retainedForExplicitRecovery }
    let down: MenuBarInputAttribution.Envelope, gesture: UUID
    var phase: Phase = .possibleDown
    var downRoutes: [String] = [], upRoutes: [String] = []
    var unresolved: Bool { phase != .pairDelivered }
}

/// Every native route has its own last stop check and serialized admission.
/// Exact session receipt is still mandatory before PID delivery. No implicit
/// cleanup, re-enable, input suppression, route fallback or automatic retry.
final class MenuBarSessionOwnedEventChannel: MenuBarOwnedEventChannel {
    enum Failure: Error { case permissions, interrupted, unknownReceipt, missingDispatchWitness, postingDisabled, unresolvedDown }
    struct Delivery {
        var permission: () -> Bool = { CGPreflightPostEventAccess() }
        var now: () -> Double = { ProcessInfo.processInfo.systemUptime }
        var pump: () -> Void = { _ = CFRunLoopRunInMode(.defaultMode, 0.002, false) }
        var session: (CGEvent) throws -> Void = { $0.post(tap: .cgSessionEventTap) }
        var pid: (CGEvent) throws -> Void = { $0.postToPid(Int32($0.getIntegerValueField(.eventTargetUnixProcessID))) }
    }
    var privateEventSource: CGEventSource { input.privateEventSource }
    let input: any MenuBarOwnedEventInput
    private(set) var sessionPosts = 0, pidPosts = 0, emergencyReleases = 0
    let witness: MenuBarDispatchWitness?
    let evidence: MenuBarMoveStageRecorder?
    let postingDisabled: Bool
    private let delivery: Delivery
    private(set) var operationStop = MenuBarOperationStop()
    private(set) var downResponsibilities: [MenuBarOwnedDownResponsibility] = []
    var needsRelease: Bool { downResponsibilities.last?.unresolved == true }
    private var boundLease: MenuBarMoveInterference.Lease?
    func bindOperationStop(_ stop: MenuBarOperationStop?) {
        if let stop { operationStop = stop }
        else { boundLease = nil }
    }
    func authorize(_ lease: MenuBarMoveInterference.Lease?) throws {
        guard !postingDisabled else { throw Failure.postingDisabled }
        try operationStop.check()
        guard !needsRelease else { operationStop.request(.possibleDown); throw Failure.unresolvedDown }
        guard let lease, case .available(let sample) = input.read(), sample.buttons.isEmpty,
              sample.keys.isEmpty, sample.modifiers == 0, sample.continuity == lease.continuity,
              sample.externalEpoch == lease.externalEpoch else {
            operationStop.request(.interference); throw Failure.interrupted
        }
        try operationStop.check()
        boundLease = lease
    }
    init(input: any MenuBarOwnedEventInput, witness: MenuBarDispatchWitness? = nil, postingDisabled: Bool = false,
         evidence: MenuBarMoveStageRecorder? = nil, delivery: Delivery = .init()) {
        self.input = input; self.witness = witness; self.postingDisabled = postingDisabled
        self.evidence = evidence; self.delivery = delivery
    }
    func emit(_ event: CGEvent, gesture: UUID) throws {
        guard !postingDisabled else { throw Failure.postingDisabled }
        do { try deliver(event, gesture: gesture) }
        catch {
            operationStop.request(.failed); input.abandonReceipt(); throw error
        }
    }
    private func check(_ ticket: MenuBarListenOnlyInterferenceSource.Ticket? = nil) throws {
        try operationStop.check()
        guard delivery.permission() else { operationStop.request(.monitorLost); throw Failure.permissions }
        guard input.monitoringHealthy else { operationStop.request(.monitorLost); throw Failure.interrupted }
        if let ticket, case .interrupted = input.receipt(ticket) {
            operationStop.request(.interference); throw Failure.interrupted
        }
        try operationStop.check()
    }
    private func deliver(_ event: CGEvent, gesture: UUID) throws {
        try check()
        guard let lease = boundLease, lease.gesture == gesture else { throw Failure.interrupted }
        if event.type == .leftMouseDown {
            guard !needsRelease else { throw Failure.unresolvedDown }
        } else if event.type == .leftMouseUp {
            let packet = MenuBarListenOnlyInterferenceSource.envelope(event)
            guard let responsibility = downResponsibilities.last, responsibility.unresolved,
                  responsibility.gesture == gesture, responsibility.down.number == packet.number,
                  responsibility.down.sourcePID == packet.sourcePID,
                  responsibility.down.sourceState == packet.sourceState,
                  responsibility.down.targetPID == packet.targetPID,
                  responsibility.down.flags == packet.flags else { throw Failure.unresolvedDown }
        } else { throw Failure.interrupted }
        guard let witness else { throw Failure.missingDispatchWitness }
        try evidence?.append("packet-intent", MenuBarListenOnlyInterferenceSource.envelope(event))
        let ticket = try input.registerForReceipt(event, gesture: gesture,
            expectedEpoch: lease.externalEpoch, expectedContinuity: lease.continuity)
        try witness.beforePost(route: "session", windowID: UInt32(event.getIntegerValueField(.mouseEventWindowUnderMousePointer)))
        try check(ticket) // includes cancellation delivered while witness was persisted
        try operationStop.perform("session-post") {
            trackPossible(event, gesture: gesture, route: "session")
            sessionPosts += 1 // attempts, not evidence of target processing
            try delivery.session(event)
        }
        let deadline = delivery.now() + 0.1
        while delivery.now() < deadline {
            delivery.pump()
            try check(ticket) // explicit cancellation is live inside the receipt wait
            switch input.receipt(ticket) {
            case .matched:
                try evidence?.appendJSON("session-receipt", ["marker": ticket.marker, "gesture": gesture.uuidString,
                    "epoch": ticket.epoch.uuidString, "sessionPosts": sessionPosts, "pidPosts": pidPosts])
                try witness.beforePost(route: "pid", windowID: UInt32(event.getIntegerValueField(.mouseEventWindowUnderMousePointer)))
                delivery.pump()
                try check(ticket)
                guard delivery.now() < deadline, case .matched = input.receipt(ticket) else { throw Failure.interrupted }
                try operationStop.perform("pid-post") {
                    trackPossible(event, gesture: gesture, route: "pid")
                    pidPosts += 1
                    try delivery.pid(event)
                }
                if event.type == .leftMouseUp, !downResponsibilities.isEmpty {
                    // Both routes returned, not a physical or target release proof.
                    downResponsibilities[downResponsibilities.count - 1].phase = .pairDelivered
                }
                try evidence?.appendJSON("packet-delivered", ["marker": ticket.marker, "gesture": gesture.uuidString,
                    "sessionPosts": sessionPosts, "pidPosts": pidPosts])
                return
            case .interrupted: throw Failure.interrupted
            case .pending: break
            }
        }
        throw Failure.unknownReceipt
    }
    private func trackPossible(_ event: CGEvent, gesture: UUID, route: String) {
        if event.type == .leftMouseDown {
            if route == "session" {
                downResponsibilities.append(.init(down: MenuBarListenOnlyInterferenceSource.envelope(event), gesture: gesture))
            }
            downResponsibilities[downResponsibilities.count - 1].downRoutes.append(route)
        } else if event.type == .leftMouseUp, !downResponsibilities.isEmpty {
            downResponsibilities[downResponsibilities.count - 1].phase = .upAttempted
            downResponsibilities[downResponsibilities.count - 1].upRoutes.append(route)
        }
    }
    func release(_ event: CGEvent, gesture: UUID) {
        guard !postingDisabled, needsRelease else { return }
        // Retain responsibility only. No permission query, tap registration,
        // event post, fallback route or claim that the button was released.
        operationStop.request(.possibleDown); input.abandonReceipt()
        downResponsibilities[downResponsibilities.count - 1].phase = .retainedForExplicitRecovery
        try? evidence?.append("possible-down-retained", downResponsibilities.last!)
    }
}
