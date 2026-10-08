// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import ApplicationServices

/// Only the configured controller window's up may become a packet. Bounded
/// diagnostics can serialize that own packet; no keyboard contents or foreign
/// pointer coordinates are materialized or retained.
struct MenuBarLocalStartReceipt {
    struct Packet: Codable, Equatable {
        let type: UInt32, timestamp: UInt64, number: Int64, sourcePID: Int64, sourceState: Int64, flags: UInt64
        let point: CGPoint
        init(_ event: CGEvent) {
            type = event.type.rawValue; timestamp = event.timestamp
            number = event.getIntegerValueField(.mouseEventNumber)
            sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
            sourceState = event.getIntegerValueField(.eventSourceStateID)
            flags = event.flags.rawValue; point = event.location
        }
    }
    struct Candidate { let packet: Packet, eventCount: Int, observedAt: UInt64, virtual: Bool }
    struct CaptureDiagnostics: Codable {
        var leftUpCallbacks = 0, ownWindowCallbacks = 0, missingWindowCallbacks = 0, otherWindowCallbacks = 0
        var lastLeftUpAt: UInt64?, lastOwnUpAt: UInt64?
        var lastPointerRelation: String?, lastHandlingRelation: String?
    }
    struct Comparison: Codable {
        let tapPacket: Packet?, appKitPacket: Packet
        let tapEventCount: Int?, currentEventCount: Int
        let tapObservedAt: UInt64?, claimObservedAt: UInt64
    }
    struct ActivityComparison: Codable, Equatable {
        enum Relation: String, Codable { case unavailable, earlierHIDActivity, alignedWithUp, laterHIDActivity }
        let relation: Relation, deltaMilliseconds: Double?
        let queriedSourceState: Int32
        var matchesExactUp: Bool { relation == .alignedWithUp }
        init(hidActivity: Double?, upTimestamp: Double) {
            queriedSourceState = CGEventSourceStateID.hidSystemState.rawValue
            guard upTimestamp.isFinite, let hidActivity, hidActivity.isFinite,
                  ((hidActivity - upTimestamp) * 1000).isFinite else {
                relation = .unavailable; deltaMilliseconds = nil; return
            }
            let delta = hidActivity - upTimestamp
            deltaMilliseconds = delta * 1000
            // Diagnostic classification only: retain the original +/-2ms
            // admission predicate. Older hardware activity is not an exemption.
            relation = abs(delta) <= 0.002 ? .alignedWithUp : delta < 0 ? .earlierHIDActivity : .laterHIDActivity
        }
    }
    /// An immutable UI event may await its asynchronous tap delivery, at most
    /// 250ms from this attempt. A new event or later quiet cannot replace it.
    struct Attempt {
        let packet: Packet, startedAt: UInt64
        func canAwait(now: UInt64, candidatePresent: Bool) -> Bool {
            !candidatePresent && now >= startedAt && now - startedAt < 250
        }
        func withinDeadline(now: UInt64) -> Bool { now >= startedAt && now - startedAt <= 250 }
    }
    let window: Int, pid: Int32
    private var candidate: Candidate?
    private(set) var consumed = false
    private(set) var capture = CaptureDiagnostics()
    init(window: Int, pid: Int32) { self.window = window; self.pid = pid }
    mutating func observeMouseUp(type: UInt32, pointerWindow: Int64, handlingWindow: Int64,
                                packet: @autoclosure () -> Packet, eventCount: Int, now: UInt64) {
        guard type == CGEventType.leftMouseUp.rawValue else { return }
        capture.leftUpCallbacks += 1; capture.lastLeftUpAt = now
        capture.lastPointerRelation = pointerWindow == 0 ? "missing" : pointerWindow == Int64(window) ? "own" : "other"
        capture.lastHandlingRelation = handlingWindow == 0 ? "missing" : handlingWindow == Int64(window) ? "own" : "other"
        guard pointerWindow == Int64(window) || handlingWindow == Int64(window) else {
            if pointerWindow == 0 && handlingWindow == 0 { capture.missingWindowCallbacks += 1 }
            else { capture.otherWindowCallbacks += 1 }
            return // Do not materialize or retain foreign coordinates/source fields.
        }
        capture.ownWindowCallbacks += 1; capture.lastOwnUpAt = now
        observed(packet(), eventCount: eventCount, now: now)
    }
    func comparison(_ packet: Packet, eventCount: Int, now: UInt64) -> Comparison {
        .init(tapPacket: candidate?.packet, appKitPacket: packet, tapEventCount: candidate?.eventCount,
              currentEventCount: eventCount, tapObservedAt: candidate?.observedAt, claimObservedAt: now)
    }
    mutating func observed(_ packet: Packet, eventCount: Int, now: UInt64, virtual: Bool = false) {
        guard !consumed, packet.type == CGEventType.leftMouseUp.rawValue else { return }
        candidate = .init(packet: packet, eventCount: eventCount, observedAt: now, virtual: virtual)
    }
    func matchFacts(_ packet: Packet, eventCount: Int, now: UInt64) -> [String: Bool] {
        guard let candidate else { return ["tapCandidatePresent": false, "consumed": consumed] }
        let p = candidate.packet
        return ["tapCandidatePresent": true, "consumed": consumed, "virtual": candidate.virtual,
            "typeEqual": p.type == packet.type, "timestampEqual": p.timestamp == packet.timestamp,
            "numberEqual": p.number == packet.number, "sourcePIDEqual": p.sourcePID == packet.sourcePID,
            "sourceStateEqual": p.sourceState == packet.sourceState, "flagsEqual": p.flags == packet.flags,
            "pointEqual": p.point == packet.point, "noLaterTapEvent": candidate.eventCount == eventCount,
            "freshWithin250ms": now >= candidate.observedAt && now - candidate.observedAt <= 250]
    }
    mutating func claim(_ packet: Packet, eventCount: Int, now: UInt64, session: UUID) -> (MenuBarLocalAcceptanceGate.StartProof, Bool)? {
        guard !consumed, let candidate, candidate.packet == packet, candidate.eventCount == eventCount,
              now >= candidate.observedAt, now - candidate.observedAt <= 250,
              packet.timestamp > 0 else { return nil }
        // SDK: NXEventData.mouse.eventNum is SInt16; NSEvent exposes Int.
        // The number is an opaque signed value (zero included), not a positive
        // validity flag. Full packet equality above still compares it exactly.
        consumed = true; self.candidate = nil
        return (.init(session: session, receipt: UUID(), window: window, eventNumber: Int(packet.number),
            timestamp: packet.timestamp, targetPID: pid), candidate.virtual)
    }
}
