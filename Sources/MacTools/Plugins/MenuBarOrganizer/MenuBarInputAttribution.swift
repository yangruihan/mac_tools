// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import CoreGraphics

/// Correlates a live listener to exact, single-use emissions registered by the
/// same trusted sender before posting. A marker or PID alone never matches.
/// This is accidental-interference attribution, not a security boundary against
/// an adversarial process already running as the same user.
enum MenuBarInputAttribution {
    enum Origin: String, Codable { case registeredOwn, controllerUnregistered, knownToolUnregistered, hidStateReported, combinedStateReported, otherSourceReported }
    /// Reported source metadata is diagnostic only, never human-input proof or
    /// a reason to grant an own-event lease. No foreign PID is persisted.
    static func origin(sourcePID: Int64, state: Int64, selfPID: Int32, tools: Set<Int32>) -> Origin {
        if sourcePID == Int64(selfPID) { return .controllerUnregistered }
        if let pid = Int32(exactly: sourcePID), tools.contains(pid) { return .knownToolUnregistered }
        if state == Int64(CGEventSourceStateID.hidSystemState.rawValue) { return .hidStateReported }
        if state == Int64(CGEventSourceStateID.combinedSessionState.rawValue) { return .combinedStateReported }
        return .otherSourceReported
    }
    struct Envelope: Equatable, Codable {
        let type: UInt32
        let timestamp: UInt64
        let sourcePID: Int64
        let sourceState: Int64
        let targetPID: Int64
        let marker: Int64
        let window: Int64
        let handlingWindow: Int64
        let privateWindow: Int64
        let number: Int64
        let flags: UInt64
        let point: CGPoint
    }
    struct Expected {
        let envelope: Envelope
        let gesture: UUID
        let registeredAt: UInt64
    }
    struct Registry {
        let senderPID: Int32
        var privateSourceState: Int64 = Int64(CGEventSourceStateID.privateState.rawValue)
        private(set) var pending: Expected?
        enum Failure: Error { case busy, invalid }
        mutating func register(_ envelope: Envelope, gesture: UUID, now: UInt64) throws {
            guard pending == nil else { throw Failure.busy }
            guard senderPID > 0, envelope.sourcePID == Int64(senderPID),
                  envelope.sourceState == privateSourceState,
                  envelope.targetPID > 0, envelope.marker != 0, envelope.timestamp > 0,
                  Int16(exactly: envelope.number) != nil, envelope.window > 0,
                  envelope.window == envelope.handlingWindow, envelope.window == envelope.privateWindow,
                  envelope.point.x.isFinite, envelope.point.y.isFinite,
                  [CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue, CGEventType.leftMouseDragged.rawValue].contains(envelope.type)
            else { throw Failure.invalid }
            // Mouse event numbers are signed 16-bit values, including zero.
            // The complete packet and unique marker remain exact, one-use keys.
            pending = .init(envelope: envelope, gesture: gesture, registeredAt: now)
        }
        mutating func consume(_ envelope: Envelope, now: UInt64) -> MenuBarMoveInterference.Attribution {
            guard let expected = pending else { return .unknown }
            guard now >= expected.registeredAt, now - expected.registeredAt <= 100,
                  envelope == expected.envelope else { return .unknown }
            pending = nil
            return .ownGesture(expected.gesture)
        }
        mutating func abandon() { pending = nil }
    }
}
