import Foundation

/// Boundary between a future public listener and the pure transaction.
/// No event tap, TCC query/request, input event or runtime wiring exists here.
enum MenuBarMoveInterference {
    enum Unavailable: Equatable { case notConnected, permissionRequired, sourceLost }
    enum Coverage: Hashable { case buttons, modifiers, keyboard, attribution }
    static let requiredCoverage: Set<Coverage> = [.buttons, .modifiers, .keyboard, .attribution]
    struct Snapshot: Equatable {
        let sequence: UInt64
        let uptimeMilliseconds: UInt64
        let continuity: UUID
        let externalEpoch: UUID
        let coverage: Set<Coverage>
        var buttons: Set<UInt16>
        var keys: Set<UInt16>
        var modifiers: UInt64
        var idle: Bool { buttons.isEmpty && keys.isEmpty && modifiers == 0 }
    }
    enum Availability { case unavailable(Unavailable), available(Snapshot) }
    enum Attribution: Equatable {
        // This classification must be established by a future trusted adapter;
        // a public event source marker alone does not establish attribution.
        case ownGesture(UUID), userOrOther, unknown
    }
    struct Event {
        let sequence: UInt64
        let uptimeMilliseconds: UInt64
        let continuity: UUID
        let attribution: Attribution
    }
    enum Failure: Error, Equatable {
        case unavailable(Unavailable), incomplete, notIdle, stale, continuityLost
        case interference, unexpectedOwnGesture, busy, notArmed
    }
    struct Lease: Equatable {
        let gesture: UUID
        let continuity: UUID
        let externalEpoch: UUID
        let interferenceEpoch: UUID
    }
    struct Gate {
        enum State: Equatable { case idle, armed, blocked(Failure) }
        private(set) var state: State = .idle
        private(set) var lease: Lease?
        private var lastSequence: UInt64 = 0
        private var lastUptime: UInt64 = 0
        mutating func begin(_ availability: Availability, now: UInt64) throws -> Lease {
            guard state == .idle else { throw Failure.busy }
            let sample = try Self.sample(availability, now: now)
            guard sample.idle else { throw Failure.notIdle }
            let lease = Lease(gesture: UUID(), continuity: sample.continuity,
                              externalEpoch: sample.externalEpoch, interferenceEpoch: UUID())
            self.lease = lease; lastSequence = sample.sequence; lastUptime = sample.uptimeMilliseconds
            state = .armed; return lease
        }
        /// Ordered events share a sequence/time source with snapshots.
        mutating func observe(_ event: Event, now: UInt64) throws {
            try armed()
            do {
                try advance(sequence: event.sequence, uptime: event.uptimeMilliseconds, continuity: event.continuity, now: now)
                switch event.attribution {
                case .ownGesture(let token):
                    guard token == lease?.gesture else { throw Failure.unexpectedOwnGesture }
                case .userOrOther, .unknown: throw Failure.interference
                }
            } catch { block(error); throw error }
        }
        /// Required at action boundaries; even own gestures must be idle here.
        mutating func verifyBoundary(_ availability: Availability, now: UInt64) throws -> Lease {
            try armed()
            do {
                let sample = try Self.sample(availability, now: now)
                try advance(sequence: sample.sequence, uptime: sample.uptimeMilliseconds, continuity: sample.continuity, now: now)
                guard sample.externalEpoch == lease?.externalEpoch else { throw Failure.interference }
                guard sample.idle else { throw Failure.notIdle }
                return lease!
            } catch { block(error); throw error }
        }
        mutating func sourceUnavailable(_ reason: Unavailable) {
            if state == .armed { state = .blocked(.unavailable(reason)) }
        }
        /// Explicit end of the monitoring lease. It never clears recovery logs.
        mutating func finish() { state = .idle; lease = nil; lastSequence = 0; lastUptime = 0 }
        private func armed() throws {
            if case .blocked(let reason) = state { throw reason }
            guard state == .armed, lease != nil else { throw Failure.notArmed }
        }
        private mutating func advance(sequence: UInt64, uptime: UInt64, continuity: UUID, now: UInt64) throws {
            guard continuity == lease?.continuity else { throw Failure.continuityLost }
            guard sequence > lastSequence, uptime >= lastUptime, uptime <= now, now - uptime <= 250 else { throw Failure.stale }
            lastSequence = sequence; lastUptime = uptime
        }
        private mutating func block(_ error: Error) { state = .blocked((error as? Failure) ?? .interference) }
        private static func sample(_ availability: Availability, now: UInt64) throws -> Snapshot {
            switch availability {
            case .unavailable(let reason): throw Failure.unavailable(reason)
            case .available(let sample):
                guard sample.coverage.isSuperset(of: requiredCoverage) else { throw Failure.incomplete }
                guard sample.sequence > 0, sample.uptimeMilliseconds <= now,
                      now - sample.uptimeMilliseconds <= 250 else { throw Failure.stale }
                return sample
            }
        }
    }
}
protocol MenuBarMoveInterferenceSource {
    /// Must report unavailability, never manufacture an idle snapshot.
    func read() -> MenuBarMoveInterference.Availability
}
struct MenuBarMoveDisconnectedInterferenceSource: MenuBarMoveInterferenceSource {
    func read() -> MenuBarMoveInterference.Availability { .unavailable(.notConnected) }
}
