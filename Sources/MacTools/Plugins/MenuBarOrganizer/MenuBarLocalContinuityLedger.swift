// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// Input evidence only, with a fixed purpose; no move lease or sender.
/// Request policies prove a later quiet window without rewriting input history.
/// The ledger proves continuity only; the broker separately fixes the authority
/// of the native real worker, sender-free diagnostic, or isolated test.
struct MenuBarLocalContinuityLedger {
    typealias R = MenuBarLocalStartReceipt
    enum Purpose { case noMove, realStart }
    enum StartPolicy: String, Codable {
        case preUpContinuity, requestQuietDiagnostic, requestQuietReal
        var usesRequestQuiet: Bool { self != .preUpContinuity }
    }
    enum State: Equatable {
        case ready, awaitingReceipt, awaitingRequestReceipt, requestMatched, warmingRequest, awaitingRequestQuiet
        case countdown, awaitingFreshQuiet, validatedNoMove, validatedRealInput, stopped(Cause)
    }
    enum Cause: String, Error, Codable, CaseIterable {
        case identity, noExactStartReceipt, missingPreUpAnchor, boundaryGap, hidChangedAcrossStart, hidActivityUnproven
        case laterInput, monitorLost, invalidSample, clock, overflow, notQuiet, cancelled, virtualUnsupported
        case missingReceiptPredecessor, unprovenReceiptActivity
    }
    struct Sample: Codable {
        let began, ended: UInt64
        let counterBefore, counterAfter: UInt32?
        let age: Double?
        let buttons, modifiers: UInt64
        let healthyBefore, healthyAfter: Bool
        // Exact bracket of the age API, inside the whole counter/health read.
        // Older recordings have no bracket and retain their original bound.
        var ageReadBegan: UInt64? = nil
        var ageReadEnded: UInt64? = nil
        var valid: Bool {
            guard began <= ended, ended - began <= 250_000_000, counterBefore != nil, counterAfter != nil,
                  let age, age.isFinite, age >= 0 else { return false }
            if ageReadBegan != nil || ageReadEnded != nil {
                guard let a = ageReadBegan, let b = ageReadEnded,
                      began <= a, a <= b, b <= ended else { return false }
            }
            return healthyBefore && healthyAfter
        }
        var quiet: Bool { valid && (age ?? 0) >= 0.25 && buttons == 0 && modifiers == 0 }
        func activityNoLaterThan(_ bound: UInt64) -> Bool {
            guard valid, let age else { return false }
            // Age was read INSIDE its recorded bracket (whole sample for legacy
            // records). Use the conservative upper
            // bound on the latest HID activity, never a +/- tolerance or equality
            // with the click. Ambiguous query timing refuses rather than rebases.
            let upper = Double(ageReadEnded ?? ended) - age * 1_000_000_000
            return upper.isFinite && upper >= 0 && upper <= Double(bound)
        }
    }
    struct Node: Codable {
        enum Kind: String, Codable { case sample, ownUp, activity, loss }
        let sequence, observedAt, epoch: UInt64
        let kind: Kind, tapCount: Int
        let sample: Sample?
        let packet: R.Packet? // Own-window up only; foreign coordinates/keys are never stored.
        var activity: Activity? = nil
    }
    /// Public event type/time only. This never attributes an unknown event to
    /// the click, and contains no foreign coordinates or keyboard contents.
    struct Activity: Codable, Equatable {
        let type: UInt32, timestamp: UInt64
    }
    struct ReceiptHistory: Codable, Equatable {
        let version: Int
        let predecessorSequence, predecessorBegan, predecessorEnded: UInt64
        let physicalUpTimestamp, upSequence, upObservedAt, guardSequence, retainedFromSequence: UInt64
        let upTapCount: Int
        let unqualifiedActivitySequences: [UInt64]
        let activityTimesComplete: Bool
    }
    struct Proof: Codable {
        let continuity, session, receipt: UUID
        let anchorSequence, upSequence, matchSequence, matchedAt, deadline, hidActivityUpperBound: UInt64
        let window: Int, pid: Int32, hidCounter: UInt32
        let packet: R.Packet
        var requestBoundary: RequestBoundary? = nil
    }
    /// A candidate observation boundary, NOT a proof or operation permission.
    /// It deliberately makes no claim about HID ownership before guardSequence.
    /// Once captured, its counter/activity bound can never be moved forward.
    struct RequestBoundary: Codable, Equatable {
        let receipt: UUID
        let upSequence, guardSequence, matchSequence, matchedAt, hidActivityUpperBound: UInt64
        let hidCounter: UInt32
        let packet: R.Packet
        var warmupStartedAt: UInt64? = nil
        var quietDeadline: UInt64? = nil
        var receiptHistory: ReceiptHistory? = nil // Historical proofs lack this protocol.
    }
    struct FirstFailure: Codable, Equatable {
        let cause: Cause, sourceFile: String, operation: String, line: UInt, previousState: String
        let lastSequence: UInt64, lastObservedAt: UInt64?, attemptedObservationAt: UInt64?
    }
    /// Retires only the waiting prefix outside every admissible pre-up anchor.
    /// The retained suffix keeps its original sequence, counters and events.
    struct StartHistoryBoundary: Codable, Equatable {
        let earliestRequiredAt: UInt64
        let retiredNodeCount: Int
        let retiredThroughSequence, retainedFromSequence: UInt64?
    }
    private(set) var state: State = .ready
    private(set) var nodes: [Node] = []
    private(set) var proof: Proof?
    private(set) var requestBoundary: RequestBoundary?
    private(set) var firstFailure: FirstFailure?
    private(set) var startHistoryBoundary: StartHistoryBoundary?
    private(set) var matchedStartCount = 0, validationCount = 0, tapCount = 0
    private(set) var epoch: UInt64 = 0
    private(set) var finalSampleSequence: UInt64?
    let continuity = UUID()
    let session: UUID, pid: Int32
    let purpose: Purpose
    let startPolicy: StartPolicy
    private(set) var window = 0
    private var sequence: UInt64 = 0, lastObserved: UInt64?
    private var attemptedObservationAt: UInt64?
    private var lastCounter: UInt32?
    private var receipt: R?
    private var pending: R.Attempt?
    private var pendingAt: UInt64?
    static let maximumGap: UInt64 = 500_000_000
    init(session: UUID, pid: Int32, purpose: Purpose = .noMove, startPolicy: StartPolicy = .preUpContinuity) {
        self.session = session; self.pid = pid; self.purpose = purpose; self.startPolicy = startPolicy
        if startPolicy.usesRequestQuiet && purpose != .realStart { fail(.identity) }
    }

    mutating func configure(window: Int) {
        guard self.window == 0, window > 0, pid > 0, state == .ready else { fail(.identity); return }
        self.window = window; receipt = R(window: window, pid: pid)
    }
    mutating func sampled(_ sample: Sample) {
        guard !stopped else { return }
        guard sample.valid else {
            epoch += 1
            append(kind: .loss, now: sample.ended, sample: sample)
            fail(sample.healthyBefore && sample.healthyAfter ? .invalidSample : .monitorLost); return
        }
        let changed = sample.counterBefore != sample.counterAfter || lastCounter.map { $0 != sample.counterBefore } == true
        let activityBound = proof?.hidActivityUpperBound ?? requestBoundary?.hidActivityUpperBound
        let guardedCounter = proof?.hidCounter ?? requestBoundary?.hidCounter
        let ageUnproven = activityBound.map { !sample.activityNoLaterThan($0) } ?? false
        let held = guardedCounter != nil && (sample.buttons != 0 || sample.modifiers != 0)
        if changed || ageUnproven || held { epoch += 1 }
        lastCounter = sample.counterAfter
        append(kind: .sample, now: sample.ended, sample: sample)
        if let guardedCounter, sample.counterBefore != guardedCounter || sample.counterAfter != guardedCounter { fail(.laterInput) }
        if ageUnproven { fail(.hidActivityUnproven) }
        if held { fail(.laterInput) }
        if state == .countdown, let proof, sample.ended >= proof.deadline { state = .awaitingFreshQuiet }
        if state == .warmingRequest, let deadline = requestBoundary?.quietDeadline, sample.ended >= deadline {
            state = .awaitingRequestQuiet
        }
    }
    mutating func event(ownPacket: R.Packet?, at now: UInt64, activity: Activity? = nil) {
        guard !stopped else { return }
        let awaitingOther = state == .awaitingReceipt && (ownPacket == nil || ownPacket != pending?.packet)
        let repeatedUp = state == .awaitingReceipt && ownPacket != nil && nodes.contains { $0.kind == .ownUp && $0.packet == ownPacket }
        let requestWaiting = state == .awaitingRequestReceipt
        let requestUpSeen = requestWaiting && nodes.contains { $0.kind == .ownUp && $0.packet == pending?.packet }
        let unexpectedRequestUp = requestWaiting && ownPacket != nil && ownPacket != pending?.packet
        tapCount += 1; epoch += 1
        if let ownPacket {
            receipt?.observed(ownPacket, eventCount: tapCount, now: now / 1_000_000)
        }
        append(kind: ownPacket == nil ? .activity : .ownUp, now: now, packet: ownPacket, activity: ownPacket == nil ? activity : nil)
        if proof != nil || requestBoundary != nil || awaitingOther || repeatedUp || requestUpSeen || unexpectedRequestUp { fail(.laterInput) }
        // AppKit may deliver the up before the tap's preceding down/activity.
        // Accept only a recorded, strictly earlier event into UNQUALIFIED
        // request history. Later, missing or impossible times cannot be waived.
        if requestWaiting, ownPacket == nil, !requestUpSeen, let pending {
            guard let activity, activity.timestamp > 0, activity.timestamp <= now else { fail(.unprovenReceiptActivity); return }
            guard activity.timestamp < pending.packet.timestamp else { fail(.laterInput); return }
        }
    }
    mutating func begin(_ packet: R.Packet, at now: UInt64) {
        guard state == .ready else { return }
        guard window > 0, packet.type == 2, packet.timestamp > 0,
              packet.timestamp <= now, now - packet.timestamp <= 250_000_000 else { fail(.identity); return }
        // Keep the immutable up's entire 250ms history and every later
        // observation. Request matching uses a receipt predecessor; the legacy
        // no-move/preUp policy still requires a physical pre-up sample. In either
        // callback order. Never trim again once this attempt has begun. A dense
        // required interval still overflows; no proof counter or timer resets.
        let earliest = packet.timestamp > 250_000_000 ? packet.timestamp - 250_000_000 : 0
        let retired = nodes.prefix { $0.observedAt < earliest }
        let retiredCount = retired.count, retiredThrough = retired.last?.sequence
        nodes.removeFirst(retiredCount)
        startHistoryBoundary = .init(earliestRequiredAt: earliest, retiredNodeCount: retiredCount,
            retiredThroughSequence: retiredThrough, retainedFromSequence: nodes.first?.sequence)
        pending = .init(packet: packet, startedAt: now / 1_000_000); pendingAt = now
        state = startPolicy.usesRequestQuiet ? .awaitingRequestReceipt : .awaitingReceipt
    }
    mutating func claim(at now: UInt64) {
        guard [.awaitingReceipt, .awaitingRequestReceipt].contains(state), let pending, let pendingAt else { return }
        guard now >= pendingAt, now - pendingAt <= 250_000_000,
              pending.withinDeadline(now: now / 1_000_000) else { fail(.noExactStartReceipt); return }
        let comparison = receipt?.comparison(pending.packet, eventCount: tapCount, now: now / 1_000_000)
        guard let candidate = comparison?.tapPacket else { return } // Same immutable attempt can await delivery.
        guard candidate == pending.packet, comparison?.tapEventCount == tapCount,
              let up = nodes.last(where: { $0.kind == .ownUp && $0.packet == candidate }),
              up.tapCount == tapCount, candidate.timestamp <= up.observedAt,
              up.observedAt - candidate.timestamp <= 250_000_000 else { fail(.noExactStartReceipt); return }
        if startPolicy.usesRequestQuiet {
            // This is receipt ordering, NOT a claim about silence before the
            // physical up. The adapter records this exact predecessor after the
            // preceding callback; missing or delayed evidence still refuses.
            guard let index = nodes.firstIndex(where: { $0.sequence == up.sequence }), index > 0 else { fail(.missingReceiptPredecessor); return }
            let anchor = nodes[index - 1]
            guard anchor.kind == .sample, let sample = anchor.sample, sample.valid,
                  up.tapCount > 0, anchor.sequence + 1 == up.sequence, anchor.tapCount == up.tapCount - 1,
                  sample.ended == anchor.observedAt, sample.ended < up.observedAt,
                  up.observedAt - sample.ended <= 250_000_000 else { fail(.missingReceiptPredecessor); return }
            let span = nodes.filter { $0.sequence >= anchor.sequence }
            guard let last = span.last, last.kind == .sample, last.observedAt <= now,
                  now - last.observedAt <= 250_000_000, covered(span),
                  span.filter({ $0.kind == .ownUp || $0.kind == .activity }).map(\.sequence) == [up.sequence]
            else { fail(.boundaryGap); return }
            claimRequest(candidate, up: up, anchor: anchor, span: span, at: now)
            return
        }
        guard let anchor = nodes.last(where: {
            $0.kind == .sample && $0.tapCount == up.tapCount - 1 && ($0.sample?.ended ?? UInt64.max) < candidate.timestamp
        }), let anchorSample = anchor.sample,
              candidate.timestamp - anchorSample.ended <= 250_000_000 else { fail(.missingPreUpAnchor); return }
        let span = nodes.filter { $0.sequence >= anchor.sequence }
        guard let last = span.last, last.kind == .sample, last.observedAt <= now,
              now - last.observedAt <= 250_000_000, covered(span),
              span.filter({ $0.kind == .ownUp || $0.kind == .activity }).map(\.sequence) == [up.sequence]
        else { fail(.boundaryGap); return }
        guard let count = anchorSample.counterAfter, span.allSatisfy({ node in
            guard let s = node.sample else { return true }
            return s.counterBefore == count && s.counterAfter == count
        }) else { fail(.hidChangedAcrossStart); return }
        guard span.allSatisfy({ $0.sample?.activityNoLaterThan(anchorSample.ended) ?? true }) else { fail(.hidActivityUnproven); return }
        guard last.sample?.buttons == 0, last.sample?.modifiers == 0 else { fail(.notQuiet); return }
        guard var consumer = receipt else { fail(.noExactStartReceipt); return }
        let claimedReceipt = consumer.claim(candidate, eventCount: tapCount, now: now / 1_000_000, session: session)
        receipt = consumer
        guard let (claimed, virtual) = claimedReceipt,
              !virtual else { fail(.noExactStartReceipt); return }
        let deadline = now.addingReportingOverflow(3_000_000_000)
        guard !deadline.overflow else { fail(.clock); return }
        proof = .init(continuity: continuity, session: session, receipt: claimed.receipt,
            anchorSequence: anchor.sequence, upSequence: up.sequence, matchSequence: last.sequence,
            matchedAt: now, deadline: deadline.partialValue, hidActivityUpperBound: anchorSample.ended,
            window: window, pid: pid, hidCounter: count, packet: candidate)
        nodes.removeAll { $0.sequence < anchor.sequence }
        self.pending = nil; self.pendingAt = nil; matchedStartCount = 1; state = .countdown
    }
    private mutating func claimRequest(_ candidate: R.Packet, up: Node, anchor: Node, span: [Node], at now: UInt64) {
        // The FIRST post-receipt sample is the candidate guard; never select a later
        // quiet sample to absorb intervening input. The preceding delta stays in
        // unqualified request history, without attributing it to the click.
        guard let origin = span.first(where: { $0.sequence > up.sequence }),
              origin.sequence == up.sequence + 1, origin.kind == .sample, let sample = origin.sample, sample.began >= up.observedAt,
              let count = sample.counterAfter, sample.counterBefore == count else { fail(.boundaryGap); return }
        let guarded = span.filter { $0.sequence >= origin.sequence }
        guard guarded.allSatisfy({ $0.sample?.counterBefore == count && $0.sample?.counterAfter == count })
        else { fail(.laterInput); return }
        guard guarded.allSatisfy({ $0.sample?.activityNoLaterThan(sample.ended) == true })
        else { fail(.hidActivityUnproven); return }
        guard guarded.allSatisfy({ $0.sample?.buttons == 0 && $0.sample?.modifiers == 0 })
        else { fail(.notQuiet); return }
        let activities = nodes.filter { $0.sequence < up.sequence && $0.kind == .activity }
        for node in activities {
            if let event = node.activity {
                guard event.timestamp > 0, event.timestamp <= node.observedAt else { fail(.unprovenReceiptActivity); return }
                guard event.timestamp < candidate.timestamp else { fail(.laterInput); return }
            }
        }
        guard var consumer = receipt,
              let (matched, virtual) = consumer.claim(candidate, eventCount: tapCount, now: now / 1_000_000, session: session),
              !virtual else { fail(.noExactStartReceipt); return }
        receipt = consumer
        requestBoundary = .init(receipt: matched.receipt, upSequence: up.sequence, guardSequence: origin.sequence,
            matchSequence: span.last!.sequence, matchedAt: now, hidActivityUpperBound: sample.ended,
            hidCounter: count, packet: candidate, receiptHistory: .init(version: 1,
                predecessorSequence: anchor.sequence, predecessorBegan: anchor.sample!.began, predecessorEnded: anchor.sample!.ended,
                physicalUpTimestamp: candidate.timestamp, upSequence: up.sequence, upObservedAt: up.observedAt,
                guardSequence: origin.sequence, retainedFromSequence: nodes.first!.sequence, upTapCount: up.tapCount,
                unqualifiedActivitySequences: activities.map(\.sequence), activityTimesComplete: activities.allSatisfy { $0.activity != nil }))
        // Retain ALL history kept by begin(), including unknown activity and
        // samples after physical up but before receipt. It is never erased or
        // promoted into a quiet proof. No additional prefix retirement here.
        pending = nil; pendingAt = nil; matchedStartCount = 1; state = .requestMatched
    }
    /// Only the broker calls this after acquiring its SAME live session fence
    /// and polling annotated again. This sets a deadline, never a new counter.
    mutating func startRequestWarmup(at now: UInt64) {
        guard state == .requestMatched, var request = requestBoundary,
              request.warmupStartedAt == nil, let last = nodes.last, last.kind == .sample,
              now >= last.observedAt, now - last.observedAt <= 250_000_000,
              now >= request.matchedAt, now - request.matchedAt <= 250_000_000 else { fail(.boundaryGap); return }
        let end = now.addingReportingOverflow(250_000_000)
        guard !end.overflow else { fail(.clock); return }
        request.warmupStartedAt = now; request.quietDeadline = end.partialValue
        requestBoundary = request; state = .warmingRequest
    }
    mutating func completeRequestQuiet(firstNewSequence: UInt64, at now: UInt64) {
        guard state == .awaitingRequestQuiet, let request = requestBoundary, let deadline = request.quietDeadline,
              let first = nodes.first(where: { $0.sequence == firstNewSequence }), let a = first.sample,
              let last = nodes.last, let b = last.sample else { return }
        let guarded = nodes.filter { $0.sequence >= request.guardSequence }
        guard first.sequence > request.matchSequence, last.sequence > first.sequence,
              a.began >= deadline, b.ended <= now, now - a.began <= 250_000_000,
              covered(guarded), guarded.allSatisfy({ $0.kind == .sample && $0.epoch == last.epoch })
        else { fail(.boundaryGap); return }
        guard a.quiet, b.quiet else { fail(.notQuiet); return }
        let end = now.addingReportingOverflow(3_000_000_000)
        guard !end.overflow else { fail(.clock); return }
        proof = .init(continuity: continuity, session: session, receipt: request.receipt,
            anchorSequence: request.guardSequence, upSequence: request.upSequence, matchSequence: last.sequence,
            matchedAt: now, deadline: end.partialValue, hidActivityUpperBound: request.hidActivityUpperBound,
            window: window, pid: pid, hidCounter: request.hidCounter, packet: request.packet, requestBoundary: request)
        state = .countdown // Still no Permit: fixed three seconds and final fresh samples remain mandatory.
    }
    mutating func complete(firstNewSequence: UInt64, at now: UInt64) {
        guard state == .awaitingFreshQuiet, let proof,
              let first = nodes.first(where: { $0.sequence == firstNewSequence }), let firstSample = first.sample,
              let last = nodes.last, let lastSample = last.sample else { return }
        guard first.sequence > proof.matchSequence, last.sequence > first.sequence,
              firstSample.began >= proof.deadline, lastSample.ended <= now,
              now - firstSample.began <= 250_000_000, covered(nodes),
              nodes.filter({ $0.sequence > proof.upSequence }).allSatisfy({ $0.kind == .sample }),
              nodes.filter({ $0.sequence > proof.upSequence }).allSatisfy({ $0.epoch == last.epoch })
        else { fail(.boundaryGap); return }
        guard firstSample.quiet, lastSample.quiet else { fail(.notQuiet); return }
        finalSampleSequence = last.sequence; validationCount = 1
        state = purpose == .noMove ? .validatedNoMove : .validatedRealInput
    }
    mutating func fail(_ cause: Cause, sourceFile: String = #fileID, operation: String = #function, line: UInt = #line) {
        guard !stopped else { return }
        firstFailure = .init(cause: cause, sourceFile: sourceFile, operation: operation, line: line, previousState: String(describing: state),
            lastSequence: sequence, lastObservedAt: lastObserved, attemptedObservationAt: attemptedObservationAt)
        state = .stopped(cause)
    }
    mutating func lost(at now: UInt64) {
        guard !stopped else { return }
        epoch += 1; append(kind: .loss, now: now); fail(.monitorLost)
    }
    var stopped: Bool { if case .stopped = state { return true }; return false }
    var pendingPacket: R.Packet? { pending?.packet }
    var lastSequence: UInt64 { sequence }
    var lastSample: Sample? { nodes.last?.sample }
    var requestReceiptHistoryValid: Bool {
        guard let request = requestBoundary else { return false }
        return Self.validReceiptHistory(request, nodes: nodes)
    }
    /// Evidence integrity only. Decoded records can never create a broker or
    /// its process-local Permit; native checks use this ledger's own nodes.
    static func validReceiptHistory(_ request: RequestBoundary, nodes: [Node]) -> Bool {
        guard let h = request.receiptHistory, h.version == 1,
              h.predecessorSequence < UInt64.max, h.upSequence < UInt64.max,
              let up = nodes.first(where: { $0.sequence == h.upSequence }), up.kind == .ownUp,
              up.packet == request.packet, h.physicalUpTimestamp == request.packet.timestamp,
              request.upSequence == h.upSequence, h.upObservedAt == up.observedAt, h.upTapCount == up.tapCount, up.tapCount > 0,
              request.packet.timestamp <= up.observedAt, up.observedAt - request.packet.timestamp <= 250_000_000,
              h.predecessorSequence + 1 == h.upSequence,
              let predecessor = nodes.first(where: { $0.sequence == h.predecessorSequence }), predecessor.kind == .sample,
              let a = predecessor.sample, a.valid, a.began == h.predecessorBegan, a.ended == h.predecessorEnded,
              predecessor.tapCount == up.tapCount - 1, a.ended == predecessor.observedAt,
              a.ended < up.observedAt, up.observedAt - a.ended <= 250_000_000,
              request.guardSequence == h.guardSequence, h.guardSequence == h.upSequence + 1,
              let guardNode = nodes.first(where: { $0.sequence == h.guardSequence }), guardNode.kind == .sample,
              let b = guardNode.sample, b.valid, b.began >= up.observedAt,
              guardNode.tapCount == up.tapCount, b.ended == guardNode.observedAt,
              b.ended == request.hidActivityUpperBound, b.counterBefore == request.hidCounter, b.counterAfter == request.hidCounter,
              b.activityNoLaterThan(b.ended), b.buttons == 0, b.modifiers == 0,
              let match = nodes.first(where: { $0.sequence == request.matchSequence }), match.kind == .sample,
              match.sequence >= guardNode.sequence, match.observedAt <= request.matchedAt,
              request.matchedAt - match.observedAt <= 250_000_000,
              h.retainedFromSequence == nodes.first?.sequence else { return false }
        let span = nodes.filter { $0.sequence >= h.predecessorSequence && $0.sequence <= match.sequence }
        guard !span.isEmpty else { return false }
        for (before, after) in zip(span, span.dropFirst()) {
            guard before.sequence < UInt64.max, after.sequence == before.sequence + 1,
                  after.observedAt >= before.observedAt, after.observedAt - before.observedAt <= maximumGap,
                  after.sample.map({ $0.valid && $0.began >= before.observedAt }) ?? (after.kind == .ownUp) else { return false }
        }
        guard span.filter({ $0.sequence >= h.guardSequence }).allSatisfy({ node in
            guard node.kind == .sample, let s = node.sample else { return false }
            return s.valid && s.counterBefore == request.hidCounter && s.counterAfter == request.hidCounter
                && s.activityNoLaterThan(request.hidActivityUpperBound) && s.buttons == 0 && s.modifiers == 0
        }) else { return false }
        let activities = nodes.filter { $0.sequence < up.sequence && $0.kind == .activity }
        return h.unqualifiedActivitySequences == activities.map(\.sequence)
            && h.activityTimesComplete == activities.allSatisfy { $0.activity != nil }
            && activities.allSatisfy { node in
                guard let a = node.activity else { return true } // Legacy/offline history remains explicitly unqualified.
                return a.timestamp > 0 && a.timestamp <= node.observedAt && a.timestamp < request.packet.timestamp
            }
    }
    var requestHistorySupportsNativeAuthority: Bool {
        requestReceiptHistoryValid && requestBoundary?.receiptHistory?.activityTimesComplete == true
    }
    func matchFacts(at now: UInt64) -> [String: Bool] {
        if requestBoundary != nil { return ["requestMatched": true, "quietWindowVerified": proof != nil] }
        guard let pending else { return ["bound": proof != nil] }
        return receipt?.matchFacts(pending.packet, eventCount: tapCount, now: now / 1_000_000) ?? [:]
    }
    func remainingSeconds(at now: UInt64) -> Int {
        guard let proof, proof.deadline > now else { return 0 }
        return Int((proof.deadline - now + 999_999_999) / 1_000_000_000)
    }
    private mutating func append(kind: Node.Kind, now: UInt64, sample: Sample? = nil, packet: R.Packet? = nil, activity: Activity? = nil) {
        attemptedObservationAt = now
        if let lastObserved {
            guard now >= lastObserved else { fail(.clock); return }
            if state != .ready && now - lastObserved > Self.maximumGap { fail(.boundaryGap); return }
        }
        sequence += 1; lastObserved = now
        nodes.append(.init(sequence: sequence, observedAt: now, epoch: epoch, kind: kind, tapCount: tapCount, sample: sample, packet: packet, activity: activity))
        if nodes.count > 512 {
            if state == .ready { nodes.removeFirst(nodes.count - 512) }
            else { fail(.overflow) }
        }
    }
    private func covered(_ span: [Node]) -> Bool {
        guard !span.isEmpty else { return false }
        for (before, after) in zip(span, span.dropFirst()) {
            guard after.sequence == before.sequence + 1, after.observedAt >= before.observedAt,
                  after.observedAt - before.observedAt <= Self.maximumGap else { return false }
            if let sample = after.sample, (!sample.valid || sample.began < before.observedAt) { return false }
        }
        return span.allSatisfy { $0.kind != .loss && ($0.sample?.valid ?? true) }
    }
}
