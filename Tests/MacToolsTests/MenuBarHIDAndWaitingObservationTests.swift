// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import AppKit
import CryptoKit
@testable import MacTools

/// No window/tap/post. Recorded native samples stay immutable; new brackets
/// are injected only in explicit measurement tests, never into old evidence.
final class MenuBarHIDAndWaitingObservationTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    typealias S = MenuBarListenOnlyInterferenceSource
    typealias I = MenuBarMoveInterference
    func testAgeBracketStillUsesItsEndAndRejectsImpossibleOrIncompleteBrackets() {
        var s = L.Sample(began: 1_000, ended: 4_000, counterBefore: 100, counterAfter: 100,
            age: 0.0000005, buttons: 0, modifiers: 0, healthyBefore: true, healthyAfter: true)
        XCTAssertFalse(s.activityNoLaterThan(1_500)) // Legacy whole-read upper=3500.
        s.ageReadBegan = 1_400; s.ageReadEnded = 1_600
        XCTAssertTrue(s.activityNoLaterThan(1_500)) // Measured upper=1100, not optimistic began=900.
        XCTAssertFalse(s.activityNoLaterThan(1_000))
        for (a, b) in [(nil, Optional<UInt64>(1_600)), (Optional<UInt64>(1_400), nil),
                       (Optional<UInt64>(999), Optional<UInt64>(1_600)), (1_600, 1_400), (1_400, 4_001)] {
            s.ageReadBegan = a; s.ageReadEnded = b
            XCTAssertFalse(s.valid); XCTAssertFalse(s.activityNoLaterThan(10_000))
        }
    }
    func testAdapterRecordsAgeCallSeparatelyFromLaterReadWork() throws {
        var time: UInt64 = 1_040_000_000
        let reads = MenuBarLocalStartInput.Reads(now: { time }, counter: { 100 }, age: {
            let age = Double(time - 900_000_000) / 1e9; time += 10_000; return age
        }, buttons: { time += 2_300_000; return 0 }, modifiers: { 0 }, healthy: { true }, pump: {})
        let monitor = MenuBarLocalStartInput(session: UUID(), pid: 123, isolatedReads: reads)
        monitor.configureLocalStart(window: 7)
        let sample = try XCTUnwrap(monitor.ledger.lastSample)
        XCTAssertEqual(sample.ageReadBegan, sample.began)
        XCTAssertEqual(sample.ageReadEnded, sample.began + 10_000)
        XCTAssertEqual(sample.ended - sample.ageReadEnded!, 2_300_000)
        XCTAssertTrue(sample.valid)
        let e = monitor.evidence(), decoded = try JSONDecoder().decode(MenuBarLocalStartInput.Evidence.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(decoded.nodes.last?.sample?.ageReadEnded, sample.ageReadEnded)
    }
    func testLateHIDCannotHideInNarrowBracketOrAfterAgeCall() throws {
        for kind in ["duringAge", "afterAgeCounter", "laterUncountedAge", "laterTap"] {
            let h = try MenuBarRequestWarmupTests.Harness(startPolicy: .requestQuietReal)
            try h.request(); let q = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
            h.time += 100_000_000
            switch kind {
            case "duringAge": h.pumpHook = { h.hid = h.time }
            case "afterAgeCounter":
                // Existing read envelope still brackets counter/health. Even a
                // precise age read cannot make a changed count admissible.
                h.count += 1
            case "laterUncountedAge": h.hid = h.time // Count deliberately unchanged.
            default: h.broker.monitor.receive(.mouseMoved, event: h.event())
            }
            XCTAssertThrowsError(try h.broker.poll(), kind)
            XCTAssertEqual(h.broker.monitor.ledger.requestBoundary, q)
            h.staysStopped()
        }
    }
    func testRecordedAmbiguousQueryRemainsRefusedWithoutInventedBracket() throws {
        struct Result: Decodable { let localStartTerminal: MenuBarRealLocalAuthorization.Terminal }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("docs/evidence/menu-bar-history-repaired-live-2026-10-07")
        let data = try Data(contentsOf: folder.appendingPathComponent("session/result.json"))
        let manifest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: folder.appendingPathComponent("session-sha256.json")))
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), manifest["result.json"])
        let t = try JSONDecoder().decode(Result.self, from: data).localStartTerminal
        let up = try XCTUnwrap(t.capturedStart), raw = t.input.nodes
        let guardSample = try XCTUnwrap(raw.first { $0.sequence == 2391 }?.sample)
        let uncertain = try XCTUnwrap(raw.first { $0.sequence == 2393 }?.sample)
        XCTAssertNil(uncertain.ageReadEnded)
        XCTAssertEqual(uncertain.ended - uncertain.began, 2_315_292)
        XCTAssertEqual(Double(uncertain.ended) - uncertain.age! * 1e9 - Double(guardSample.ended), 74_708)
        XCTAssertFalse(uncertain.activityNoLaterThan(guardSample.ended))
        for first in [true, false] {
            var l = L(session: t.binding.nonce, pid: t.binding.controllerPID, purpose: .realStart, startPolicy: .requestQuietReal)
            l.configure(window: 327031)
            for n in raw {
                if first && n.sequence == 2390 { l.begin(up, at: up.timestamp) }
                if !first && n.sequence == 2392 { l.begin(up, at: n.sample!.began) }
                switch n.kind {
                case .sample: l.sampled(try XCTUnwrap(n.sample))
                case .ownUp: l.event(ownPacket: n.packet, at: n.observedAt)
                case .activity: l.event(ownPacket: nil, at: n.observedAt)
                case .loss: l.lost(at: n.observedAt)
                }
            }
            l.claim(at: try XCTUnwrap(raw.last).observedAt)
            XCTAssertEqual(l.state, .stopped(.hidActivityUnproven))
            XCTAssertEqual(l.matchedStartCount, 0); XCTAssertNil(l.proof)
        }
    }
    func event(_ sequence: UInt64, time: UInt64, continuity: UUID, own: Bool = false) -> I.Event {
        .init(sequence: sequence, uptimeMilliseconds: time, continuity: continuity,
            attribution: own ? .ownGesture(UUID()) : .unknown)
    }
    func testLongWaitingConsumesEveryBatchAndKeepsCumulativeIdentityUntilBegin() throws {
        var b = S.EventBuffer(); let continuity = UUID(); var epoch = UUID()
        XCTAssertTrue(b.beginWaiting(continuity: continuity, epoch: epoch, count: 0, at: 0))
        for batch in 0..<500 {
            epoch = UUID()
            for i in 1...100 {
                let sequence = UInt64(batch * 100 + i)
                XCTAssertTrue(b.append(event(sequence, time: sequence, continuity: continuity)))
            }
            XCTAssertTrue(b.consumeWaiting(continuity: continuity, epoch: epoch, count: (batch + 1) * 100, at: UInt64((batch + 1) * 100)))
            XCTAssertEqual(b.events.count, 0)
        }
        let record = try XCTUnwrap(b.waitingConsumption)
        XCTAssertEqual(record.consumedEventCount, 50_000); XCTAssertEqual(record.lastSourceEventCount, 50_000)
        XCTAssertEqual(record.continuity, continuity); XCTAssertEqual(record.lastEpoch, epoch)
        XCTAssertEqual(record.firstEventSequence, 1); XCTAssertEqual(record.lastEventSequence, 50_000)
        XCTAssertTrue(b.endWaiting(at: 50_000)); XCTAssertFalse(b.waiting)
        XCTAssertTrue(b.append(event(50_001, time: 50_001, continuity: continuity)))
        XCTAssertEqual(b.events.count, 1) // Late event must survive into proof/Gate.
        XCTAssertEqual(b.waitingConsumption?.lastSourceEventCount, 50_000)
    }
    func testTrueOverflowRemainsLostEvenAfterDrainAndDoesNotGrowUnbounded() {
        var b = S.EventBuffer(); let continuity = UUID(), epoch = UUID()
        XCTAssertTrue(b.beginWaiting(continuity: continuity, epoch: epoch, count: 0, at: 0))
        for i in 1...512 { XCTAssertTrue(b.append(event(UInt64(i), time: UInt64(i), continuity: continuity))) }
        XCTAssertFalse(b.append(event(513, time: 513, continuity: continuity)))
        for i in 514...2_000 { XCTAssertFalse(b.append(event(UInt64(i), time: UInt64(i), continuity: continuity))) }
        XCTAssertTrue(b.lost); XCTAssertTrue(b.capacityOverflow); XCTAssertEqual(b.events.count, 513)
        XCTAssertFalse(b.consumeWaiting(continuity: continuity, epoch: epoch, count: 2_000, at: 2_000))
        XCTAssertEqual(b.drain().count, 513)
        XCTAssertFalse(b.beginWaiting(continuity: continuity, epoch: epoch, count: 2_000, at: 2_000))
        XCTAssertFalse(b.endWaiting(at: 2_000)); XCTAssertTrue(b.lost)
    }
    func testProofQueueCapacityStillOverflowsAfterWaitingEnded() {
        var b = S.EventBuffer(); let continuity = UUID(), epoch = UUID()
        XCTAssertTrue(b.beginWaiting(continuity: continuity, epoch: epoch, count: 0, at: 0))
        XCTAssertTrue(b.endWaiting(at: 0))
        for i in 1...513 { _ = b.append(event(UInt64(i), time: UInt64(i), continuity: continuity)) }
        XCTAssertTrue(b.lost); XCTAssertEqual(b.events.count, 513)
        XCTAssertFalse(b.consumeWaiting(continuity: continuity, epoch: epoch, count: 513, at: 513))
    }
    func testSkippedWrongContinuityLateClockOwnOrCrossPhaseConsumptionCannotHeal() {
        for kind in ["skipped", "continuity", "future", "clock", "own", "duplicate", "crossPhase"] {
            var b = S.EventBuffer(); let continuity = UUID(), epoch = UUID()
            XCTAssertTrue(b.beginWaiting(continuity: continuity, epoch: epoch, count: 0, at: 10))
            if kind == "crossPhase" { XCTAssertTrue(b.endWaiting(at: 10)) }
            XCTAssertTrue(b.append(event(1, time: kind == "future" ? 21 : 11,
                continuity: kind == "continuity" ? UUID() : continuity, own: kind == "own")))
            if kind == "duplicate" { XCTAssertTrue(b.append(event(1, time: 11, continuity: continuity))) }
            XCTAssertFalse(b.consumeWaiting(continuity: continuity, epoch: epoch,
                count: kind == "skipped" ? 2 : kind == "duplicate" ? 2 : 1, at: kind == "clock" ? 9 : 20), kind)
            XCTAssertTrue(b.lost); XCTAssertFalse(b.capacityOverflow)
            XCTAssertFalse(b.endWaiting(at: 30)); XCTAssertFalse(b.beginWaiting(continuity: continuity, epoch: epoch, count: 2, at: 30))
        }
    }
    func testBrokerConsumesOnlyReadyHistoryAndEndsBeforeImmutableStartProof() throws {
        let fixture = MenuBarHiddenMoveFixture(); var time: UInt64 = 1_000_000_000
        var batches = 0, ends = 0, age = 1.0, count: UInt32 = 100
        let reads = MenuBarLocalStartInput.Reads(now: { time }, counter: { count }, age: { age },
            buttons: { 0 }, modifiers: { 0 }, healthy: { true }, pump: {})
        let binding = MenuBarDispatchWitness.Binding(nonce: fixture.original.owner.nonce, targetPID: fixture.original.owner.target.pid,
            controllerPID: 123, controllerLaunch: 10, controllerSHA256: String(repeating: "a", count: 64))
        let fence = S.StartFence(continuity: UUID(), epoch: UUID(), eventCount: 0)
        let broker = MenuBarRealLocalAuthorization(binding: binding, plan: try fixture.plan(), reads: reads, fence: { fence },
            expires: 60_000_000_000, startPolicy: .requestQuietReal,
            waiting: .init(poll: { batches += 1 }, end: { ends += 1 }))
        broker.monitor.configureLocalStart(window: 7)
        for _ in 0..<400 { time += 100_000_000; try broker.poll() }
        XCTAssertEqual(batches, 400)
        let e = MenuBarLocalNativeContinuityTests.Harness(configure: false).event(timestamp: time + 100_000_000)
        let down = MenuBarLocalNativeContinuityTests.Harness(configure: false).event(.leftMouseDown, timestamp: time)
        broker.monitor.receive(.leftMouseDown, event: down); time += 100_000_000
        age = 0.001; count += 1
        broker.monitor.receive(.leftMouseUp, event: e); broker.begin(e)
        XCTAssertEqual(ends, 1); let initialBatches = batches
        for _ in 0..<35 { time += 100_000_000; age += 0.1; try broker.poll() }
        XCTAssertEqual(batches, initialBatches); XCTAssertEqual(ends, 1)
        XCTAssertEqual(broker.monitor.state, .validatedRealInput)
        let permit = try broker.permit(); XCTAssertThrowsError(try permit.checkForRealAction(binding: binding))
    }
    func testWaitingLossStopsBrokerBeforePermitOrFenceAndCannotRestart() throws {
        let h = try MenuBarRequestWarmupTests.Harness()
        // Existing later-fence-loss test covers proof phase; injected waiting
        // failure below verifies that it cannot be treated as normal activity.
        let fixture = h.fixture
        enum Lost: Error { case queue }
        let broker = MenuBarRealLocalAuthorization(binding: h.broker.binding, plan: try fixture.plan(),
            reads: .init(now: { h.time }, counter: { h.count }, age: { 1 }, buttons: { 0 }, modifiers: { 0 }, healthy: { true }, pump: {}),
            fence: { XCTFail("no fence after waiting loss"); throw Lost.queue }, expires: 10_000_000_000,
            startPolicy: .requestQuietReal, waiting: .init(poll: { throw Lost.queue }, end: { throw Lost.queue }))
        broker.monitor.configureLocalStart(window: 7)
        XCTAssertThrowsError(try broker.poll()); XCTAssertEqual(broker.monitor.state, .stopped(.monitorLost))
        let failure = broker.monitor.ledger.firstFailure
        broker.begin(h.event()); XCTAssertThrowsError(try broker.permit())
        XCTAssertEqual(broker.monitor.ledger.firstFailure, failure)
    }
    func testWaitingTimerAlsoFiresWhileEventTrackingRunsWithoutAnyWindow() {
        var fired = false
        let timer = Timer(timeInterval: 0.005, repeats: false) { _ in fired = true }
        RunLoop.current.add(timer, forMode: .common)
        RunLoop.current.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        let deadline = Date().addingTimeInterval(0.1)
        while !fired && Date() < deadline { _ = RunLoop.current.run(mode: .eventTracking, before: deadline) }
        XCTAssertTrue(fired)
    }
}
