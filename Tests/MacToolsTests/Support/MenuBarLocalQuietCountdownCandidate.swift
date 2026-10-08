// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
@testable import MacTools

/// Executable DESIGN ONLY, in the test target. No native adapter, sender,
/// movement lease, window, event tap, or HID queries are implemented here.
/// Injected continuity is a premise under test, never evidence about the desktop.
struct MenuBarLocalQuietCountdownCandidate {
    typealias Receipt = MenuBarLocalStartReceipt
    enum State: Equatable { case ready, countdown, awaitingFreshQuiet, validatedNoMove, stopped(Failure) }
    enum Failure: Equatable {
        case identity, boundaryUnproven, activity, monitorLost, incomplete, ordering, clock, quiet, cancelled
    }
    enum Coverage: Hashable { case tap, keyboardAndRepeats, hidAnyInputCounter, publicButtons, gestureModifiers }
    static let requiredCoverage: Set<Coverage> = [.tap, .keyboardAndRepeats, .hidAnyInputCounter, .publicButtons, .gestureModifiers]
    struct Stamp {
        var sequence, uptime: UInt64
        var continuity, epoch: UUID
        var tapEvents: Int
        var hidAnyInputCount: UInt32?
        var healthy: Bool
        var coverage: Set<Coverage>
    }
    struct Boundary {
        enum CoverageFromExactUp { case unproven, continuousInInjectedTimeline }
        let atExactUp, atMatch: Stamp
        // A later HID sample alone cannot establish this. A native bridge must
        // separately prove the up-to-sample interval; no such bridge exists.
        let coverageFromExactUp: CoverageFromExactUp
    }
    struct QuietScan {
        let before, after: Stamp
        let hidIdleAgeSeconds: Double
        let publicButtonsReleased, gestureModifiersReleased: Bool
    }
    let session: UUID, ownPID: Int32, ownWindow: Int
    private(set) var state: State = .ready
    private(set) var exactPacket: Receipt.Packet?
    private(set) var exactProof: MenuBarLocalAcceptanceGate.StartProof?
    private(set) var deadline: UInt64?
    private(set) var validationCount = 0
    private var baseline: Stamp?
    private var previous: Stamp?
    private var previousNow: UInt64?

    init(session: UUID, ownPID: Int32, ownWindow: Int) {
        self.session = session; self.ownPID = ownPID; self.ownWindow = ownWindow
    }

    mutating func start(receipt: inout Receipt, appKit: Receipt.Packet, boundary: Boundary, now: UInt64) {
        guard state == .ready else { return } // No restart or deadline extension.
        guard ownPID > 0, ownWindow > 0, receipt.pid == ownPID, receipt.window == ownWindow else {
            stop(.identity); return
        }
        guard case .continuousInInjectedTimeline = boundary.coverageFromExactUp else {
            stop(.boundaryUnproven); return
        }
        let up = boundary.atExactUp, match = boundary.atMatch
        guard usable(up), usable(match) else { return }
        guard up.sequence > 0, match.sequence > up.sequence, up.uptime <= match.uptime,
              match.uptime <= now, now - up.uptime <= 250 else { stop(.ordering); return }
        guard unchanged(up, match) else { stop(.activity); return }
        let comparison = receipt.comparison(appKit, eventCount: match.tapEvents, now: now)
        guard comparison.tapEventCount == up.tapEvents, comparison.tapObservedAt == up.uptime,
              let (proof, virtual) = receipt.claim(appKit, eventCount: match.tapEvents, now: now, session: session),
              !virtual else { stop(.identity); return }
        let end = now.addingReportingOverflow(3000)
        guard !end.overflow else { stop(.clock); return }
        exactPacket = appKit; exactProof = proof // Keep the whole packet, including signed number/source/flags/point.
        baseline = up; previous = match; previousNow = now; deadline = end.partialValue
        state = .countdown
        // Deliberately NO HID-time == click-time predicate. Click identity is
        // established above; new HID activity is independently monitored.
    }

    mutating func poll(_ sample: Stamp, now: UInt64) {
        guard state == .countdown || state == .awaitingFreshQuiet else { return }
        guard advance(sample, now: now), let deadline else { return }
        if now >= deadline { state = .awaitingFreshQuiet } // Timer expiry is not success.
    }

    mutating func complete(_ scan: QuietScan, now: UInt64) {
        guard state == .awaitingFreshQuiet, let deadline else { return }
        // Both sides must be a NEW scan begun after the fixed countdown.
        guard scan.before.uptime >= deadline, scan.after.uptime >= scan.before.uptime,
              scan.after.uptime <= now, now - scan.before.uptime <= 250 else { stop(.ordering); return }
        guard advance(scan.before, now: now), advance(scan.after, now: now) else { return }
        guard scan.hidIdleAgeSeconds.isFinite, scan.hidIdleAgeSeconds >= 0.25,
              scan.publicButtonsReleased, scan.gestureModifiersReleased else { stop(.quiet); return }
        validationCount += 1; state = .validatedNoMove
    }

    mutating func activity() { stop(.activity) } // Every later event, including another own up, is terminal.
    mutating func unavailable() { stop(.monitorLost) }
    mutating func cancel() { stop(.cancelled) }

    private mutating func advance(_ sample: Stamp, now: UInt64) -> Bool {
        guard usable(sample), let baseline, let previous, let previousNow else { return false }
        guard now >= previousNow, now - previousNow <= 500 else { stop(.clock); return false }
        guard sample.sequence > previous.sequence, sample.uptime >= previous.uptime,
              sample.uptime <= now, now - sample.uptime <= 250 else { stop(.ordering); return false }
        guard unchanged(baseline, sample) else { stop(.activity); return false }
        self.previous = sample; self.previousNow = now
        return true
    }
    private mutating func usable(_ sample: Stamp) -> Bool {
        guard sample.healthy else { stop(.monitorLost); return false }
        guard sample.coverage.isSuperset(of: Self.requiredCoverage), sample.hidAnyInputCount != nil,
              sample.tapEvents >= 0 else { stop(.incomplete); return false }
        return true
    }
    private func unchanged(_ lhs: Stamp, _ rhs: Stamp) -> Bool {
        lhs.continuity == rhs.continuity && lhs.epoch == rhs.epoch &&
        lhs.tapEvents == rhs.tapEvents && lhs.hidAnyInputCount == rhs.hidAnyInputCount
    }
    private mutating func stop(_ reason: Failure) {
        if case .stopped = state { return } // Later quiet, a reconnect, or cancel cannot erase the first failure.
        state = .stopped(reason)
    }
}
