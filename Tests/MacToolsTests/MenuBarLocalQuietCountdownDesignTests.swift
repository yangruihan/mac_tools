// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

/// Pure injected timelines only: no NSApplication, tap, HID query, or input post.
final class MenuBarLocalQuietCountdownDesignTests: XCTestCase {
    typealias C = MenuBarLocalQuietCountdownCandidate
    typealias R = MenuBarLocalStartReceipt
    let session = UUID(), continuity = UUID(), epoch = UUID()

    func packet(_ changes: [String: Any] = [:]) throws -> R.Packet {
        var fields: [String: Any] = ["type": 2, "timestamp": 1_000_000_000, "number": -20895,
            "sourcePID": 456, "sourceState": 1690226100, "flags": 0, "point": [864, 355]]
        fields.merge(changes) { _, replacement in replacement }
        return try JSONDecoder().decode(R.Packet.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func stamp(_ sequence: UInt64, _ uptime: UInt64, count: UInt32? = 100, taps: Int = 5) -> C.Stamp {
        .init(sequence: sequence, uptime: uptime, continuity: continuity, epoch: epoch, tapEvents: taps,
            hidAnyInputCount: count, healthy: true, coverage: C.requiredCoverage)
    }
    func fresh() -> C { .init(session: session, ownPID: 123, ownWindow: 7) }
    func receipt(_ p: R.Packet, virtual: Bool = false) -> R {
        var r = R(window: 7, pid: 123)
        r.observeMouseUp(type: p.type, pointerWindow: 7, handlingWindow: 7,
            packet: p, eventCount: 5, now: 1000)
        if virtual { r.observed(p, eventCount: 5, now: 1000, virtual: true) }
        return r
    }
    func boundary() -> C.Boundary {
        .init(atExactUp: stamp(1, 1000), atMatch: stamp(2, 1001), coverageFromExactUp: .continuousInInjectedTimeline)
    }
    func armed(_ p: R.Packet? = nil) throws -> C {
        var g = fresh(); let p = try p ?? packet(); var r = receipt(p)
        g.start(receipt: &r, appKit: p, boundary: boundary(), now: 1010)
        XCTAssertEqual(g.state, .countdown); XCTAssertTrue(r.consumed)
        return g
    }
    func finishCountdown(_ g: inout C) {
        for t in stride(from: UInt64(1100), through: 4000, by: 100) { g.poll(stamp(t, t), now: t) }
        g.poll(stamp(4010, 4010), now: 4010)
    }
    func quiet(age: Double = 3, buttons: Bool = true, modifiers: Bool = true) -> C.QuietScan {
        .init(before: stamp(4011, 4011), after: stamp(4012, 4012), hidIdleAgeSeconds: age,
            publicButtonsReleased: buttons, gestureModifiersReleased: modifiers)
    }
    func assertNoRecovery(_ g: inout C, file: StaticString = #filePath, line: UInt = #line) {
        let failure = g.state
        finishCountdown(&g); g.complete(quiet(), now: 4012)
        XCTAssertEqual(g.state, failure, file: file, line: line)
        XCTAssertEqual(g.validationCount, 0, file: file, line: line)
        guard case .stopped = g.state else { return XCTFail("failure must remain latched", file: file, line: line) }
    }

    func testSyntheticAndPhysicalTimelinesSeparateIdentityFromFinalHIDQuiet() throws {
        // These are simulations, not a claim that sourceState alone authenticates hardware.
        for source in [1, 1690226100] {
            let p = try packet(["sourceState": source]); var g = try armed(p)
            finishCountdown(&g)
            XCTAssertEqual(g.state, .awaitingFreshQuiet); XCTAssertEqual(g.validationCount, 0)
            // Synthetic timeline: HID last activity is 41.923ms BEFORE up.
            // Physical timeline: the up itself updates HID. Neither requires alignment here.
            let lastHID = source == 1 ? 1.0 : 1.0 - 0.041923
            g.complete(quiet(age: 4.012 - lastHID), now: 4012)
            XCTAssertEqual(g.state, .validatedNoMove); XCTAssertEqual(g.validationCount, 1)
            XCTAssertEqual(g.exactPacket, p); XCTAssertEqual(g.exactProof?.eventNumber, -20895)
            g.complete(quiet(), now: 4012); XCTAssertEqual(g.validationCount, 1)
        }
    }
    func testCountdownExpiryDoesNotAcceptOldQuietOrPermitDuplicateStartExtension() throws {
        var g = try armed(); let p = try packet(); var r = receipt(p)
        g.start(receipt: &r, appKit: p, boundary: boundary(), now: 2010)
        XCTAssertEqual(g.deadline, 4010)
        finishCountdown(&g)
        XCTAssertEqual(g.state, .awaitingFreshQuiet); XCTAssertEqual(g.validationCount, 0)
        let old = C.QuietScan(before: stamp(4011, 4008), after: stamp(4012, 4009), hidIdleAgeSeconds: 3,
            publicButtonsReleased: true, gestureModifiersReleased: true)
        g.complete(old, now: 4012)
        XCTAssertEqual(g.state, .stopped(.ordering)); assertNoRecovery(&g)
    }
    func testEveryIdentityFieldRemainsExactIncludingSignedAndZeroNumbers() throws {
        let original = try packet()
        let mutations: [[String: Any]] = [["number": 0], ["sourcePID": 457], ["sourceState": 1],
            ["timestamp": 1_000_000_001], ["flags": 1], ["point": [864.5, 355]], ["type": 1]]
        for mutation in mutations {
            var g = fresh(), r = receipt(original)
            g.start(receipt: &r, appKit: try packet(mutation), boundary: boundary(), now: 1010)
            XCTAssertEqual(g.state, .stopped(.identity)); XCTAssertFalse(r.consumed)
        }
        for number in [-32768, -1, 0, 32767] {
            let p = try packet(["number": number]); let g = try armed(p)
            XCTAssertEqual(g.exactPacket, p)
        }
    }
    func testMissingCandidateVirtualCandidateAndForeignWindowCannotArm() throws {
        let p = try packet()
        for r0 in [R(window: 7, pid: 123), receipt(p, virtual: true), R(window: 8, pid: 123), R(window: 7, pid: 999)] {
            var g = fresh(), r = r0
            g.start(receipt: &r, appKit: p, boundary: boundary(), now: 1010)
            XCTAssertEqual(g.state, .stopped(.identity))
        }
    }
    func testUpToMatchGapCannotBeRebaselinedAfterUnknownInput() throws {
        let p = try packet()
        let boundaries: [C.Boundary] = [
            .init(atExactUp: stamp(1, 1000), atMatch: stamp(2, 1001), coverageFromExactUp: .unproven),
            .init(atExactUp: stamp(1, 1000, count: nil), atMatch: stamp(2, 1001), coverageFromExactUp: .continuousInInjectedTimeline),
            .init(atExactUp: stamp(1, 1000), atMatch: stamp(2, 1001, count: 101), coverageFromExactUp: .continuousInInjectedTimeline),
            .init(atExactUp: stamp(1, 1000), atMatch: stamp(2, 1001, taps: 6), coverageFromExactUp: .continuousInInjectedTimeline)]
        for b in boundaries {
            var g = fresh(), r = receipt(p)
            g.start(receipt: &r, appKit: p, boundary: b, now: 1010)
            assertNoRecovery(&g)
        }
    }
    func testHIDOnlyInputOneMillisecondAfterMatchStopsDespiteLaterQuiet() throws {
        var g = try armed()
        // No annotated callback for this injected HID activity. Counter changes,
        // even within the old 2ms jitter tolerance; final quiet cannot erase it.
        g.poll(stamp(3, 1011, count: 101), now: 1011)
        XCTAssertEqual(g.state, .stopped(.activity)); assertNoRecovery(&g)
    }
    func testTapOnlyInputAndAutorepeatStopEvenWhenCounterDoesNotChange() throws {
        for changedEpoch in [false, true] {
            var g = try armed(), s = stamp(3, 1100, taps: changedEpoch ? 5 : 6)
            if changedEpoch { s.epoch = UUID() }
            g.poll(s, now: 1100)
            XCTAssertEqual(g.state, .stopped(.activity)); assertNoRecovery(&g)
        }
    }
    func testASecondIdenticalOwnClickStillCountsAsLaterInput() throws {
        var g = try armed()
        g.activity(); assertNoRecovery(&g)
        let p = try packet(); var r = receipt(p)
        g.start(receipt: &r, appKit: p, boundary: boundary(), now: 5010)
        XCTAssertEqual(g.state, .stopped(.activity)); XCTAssertEqual(g.deadline, 4010)
    }
    func testChangedCounterResetAndContinuityCannotBeAcceptedAsNewBaseline() throws {
        for count in [UInt32(99), UInt32.max, 0] {
            var g = try armed(); g.poll(stamp(3, 1100, count: count), now: 1100)
            XCTAssertEqual(g.state, .stopped(.activity)); assertNoRecovery(&g)
        }
        var g = try armed(), s = stamp(3, 1100); s.continuity = UUID()
        g.poll(s, now: 1100); assertNoRecovery(&g)
    }
    func testMissingCoverageUnhealthyOrAbsentCounterNeverMeansIdle() throws {
        for coverage in C.requiredCoverage {
            var g = try armed(), s = stamp(3, 1100); s.coverage.remove(coverage)
            g.poll(s, now: 1100); XCTAssertEqual(g.state, .stopped(.incomplete)); assertNoRecovery(&g)
        }
        var g = try armed(), s = stamp(3, 1100); s.healthy = false
        g.poll(s, now: 1100); XCTAssertEqual(g.state, .stopped(.monitorLost)); assertNoRecovery(&g)
        g = try armed(); g.poll(stamp(3, 1100, count: nil), now: 1100); assertNoRecovery(&g)
    }
    func testBackwardClockStallReplayedOrFutureSamplesAllRefuse() throws {
        let scenarios: [(C.Stamp, UInt64)] = [(stamp(3, 1000), 1009), (stamp(3, 1511), 1511),
            (stamp(2, 1100), 1100), (stamp(3, 1101), 1100), (stamp(3, 1001), 1252)]
        for (s, now) in scenarios {
            var g = try armed(); g.poll(s, now: now); assertNoRecovery(&g)
        }
    }
    func testInputDuringFinalSamplingPermanentlyInvalidatesOtherwiseQuietResult() throws {
        for tapOnly in [false, true] {
            var g = try armed(); finishCountdown(&g)
            let scan = C.QuietScan(before: stamp(4011, 4011),
                after: stamp(4012, 4012, count: tapOnly ? 100 : 101, taps: tapOnly ? 6 : 5),
                hidIdleAgeSeconds: 3, publicButtonsReleased: true, gestureModifiersReleased: true)
            g.complete(scan, now: 4012)
            XCTAssertEqual(g.state, .stopped(.activity)); assertNoRecovery(&g)
        }
    }
    func testNewQuietRequiresFiniteAgeAndReleasedPublicGestureState() throws {
        let bad = [quiet(age: .nan), quiet(age: .infinity), quiet(age: -1), quiet(age: 0.249),
            quiet(buttons: false), quiet(modifiers: false)]
        for scan in bad {
            var g = try armed(); finishCountdown(&g); g.complete(scan, now: 4012)
            XCTAssertEqual(g.state, .stopped(.quiet)); assertNoRecovery(&g)
        }
    }
    func testCancelAndListenerLossCannotResumeInEitherStage() throws {
        for atEnd in [false, true] {
            var g = try armed(); if atEnd { finishCountdown(&g) }
            g.cancel(); XCTAssertEqual(g.state, .stopped(.cancelled)); assertNoRecovery(&g)
            g = try armed(); if atEnd { finishCountdown(&g) }
            g.unavailable(); XCTAssertEqual(g.state, .stopped(.monitorLost)); assertNoRecovery(&g)
        }
    }
    func testHistoricalExactSyntheticReceiptCannotInventMissingBoundaryCounters() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("docs/evidence/menu-bar-local-annotated-synthetic-2026-10-05/result.json")
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let trace = try XCTUnwrap((record["startReceiptTraces"] as? [[String: Any]])?.last)
        let comparison = try XCTUnwrap(trace["comparison"] as? [String: Any])
        let appKit = try JSONDecoder().decode(R.Packet.self, from: JSONSerialization.data(withJSONObject: comparison["appKitPacket"]!))
        let tap = try JSONDecoder().decode(R.Packet.self, from: JSONSerialization.data(withJSONObject: comparison["tapPacket"]!))
        let pid = try XCTUnwrap(record["controllerPID"] as? Int32), window = try XCTUnwrap(trace["configuredWindow"] as? Int)
        let observed = try XCTUnwrap(comparison["tapObservedAt"] as? UInt64), claim = try XCTUnwrap(comparison["claimObservedAt"] as? UInt64)
        let taps = try XCTUnwrap(comparison["tapEventCount"] as? Int)
        XCTAssertEqual(appKit, tap); XCTAssertEqual(appKit.number, -20895)
        XCTAssertNil(trace["hidAnyInputCountAtExactUp"])
        var r = R(window: window, pid: pid)
        r.observeMouseUp(type: tap.type, pointerWindow: Int64(window), handlingWindow: Int64(window),
            packet: tap, eventCount: taps, now: observed)
        var g = C(session: session, ownPID: pid, ownWindow: window)
        g.start(receipt: &r, appKit: appKit, boundary: .init(
            atExactUp: stamp(1, observed, count: nil, taps: taps), atMatch: stamp(2, claim, count: nil, taps: taps),
            coverageFromExactUp: .unproven), now: claim)
        XCTAssertEqual(g.state, .stopped(.boundaryUnproven)); XCTAssertEqual(g.validationCount, 0)
        XCTAssertFalse(r.consumed) // Refused; old data is not upgraded into new evidence.
    }
}
