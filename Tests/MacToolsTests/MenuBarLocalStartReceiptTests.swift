// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarLocalStartReceiptTests: XCTestCase {
    func event() -> CGEvent {
        let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: .init(x: 123, y: 234), mouseButton: .left)!
        e.timestamp = 12345; e.setIntegerValueField(.mouseEventNumber, value: 123); return e
    }
    func testExactEqualityAndSingleUseReceipt() {
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123); let p = MenuBarLocalStartReceipt.Packet(event()), id = UUID()
        m.observed(p, eventCount: 5, now: 1000)
        let first = m.claim(p, eventCount: 5, now: 1010, session: id)
        XCTAssertEqual(first?.0.window, 7); XCTAssertEqual(first?.0.targetPID, 123); XCTAssertEqual(first?.1, false)
        XCTAssertNil(m.claim(p, eventCount: 5, now: 1011, session: id))
    }
    func testAnotherEventAfterClickAndStaleReceiptAreNeverIgnored() {
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123); let p = MenuBarLocalStartReceipt.Packet(event())
        m.observed(p, eventCount: 5, now: 1000)
        XCTAssertNil(m.claim(p, eventCount: 6, now: 1010, session: UUID()))
        XCTAssertNil(m.claim(p, eventCount: 5, now: 1251, session: UUID()))
    }
    func testNearTimeCoordinatesAndPIDAreInsufficient() {
        let e = event(), p = MenuBarLocalStartReceipt.Packet(e)
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123); m.observed(p, eventCount: 5, now: 1000)
        for field in [CGEventField.mouseEventNumber, .eventSourceUnixProcessID, .eventSourceStateID] {
            let different = e.copy()!; different.setIntegerValueField(field, value: different.getIntegerValueField(field) + 1)
            XCTAssertNil(m.claim(.init(different), eventCount: 5, now: 1010, session: UUID()))
        }
        let near = e.copy()!; near.timestamp += 1
        XCTAssertNil(m.claim(.init(near), eventCount: 5, now: 1010, session: UUID()))
    }
    func testVirtualReceiptIsExplicitAndNotRealTapEvidence() {
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123); let p = MenuBarLocalStartReceipt.Packet(event())
        m.observed(p, eventCount: 5, now: 1000, virtual: true)
        XCTAssertEqual(m.claim(p, eventCount: 5, now: 1010, session: UUID())?.1, true)
    }
    func testNativeNoPostChannelRejectsEveryRouteBeforeAnyWitnessOrTap() {
        let input = MenuBarListenOnlyInterferenceSource(), channel = MenuBarSessionOwnedEventChannel(input: MenuBarListenOnlyInterferenceSource(), postingDisabled: true)
        XCTAssertThrowsError(try channel.authorize(nil))
        XCTAssertThrowsError(try channel.emit(event(), gesture: UUID()))
        channel.release(event(), gesture: UUID())
        XCTAssertEqual(channel.sessionPosts, 0); XCTAssertEqual(channel.pidPosts, 0)
        XCTAssertEqual(channel.emergencyReleases, 0); XCTAssertFalse(channel.needsRelease)
        input.stop()
    }
    func testLocalStageUsesAnnotatedTapAndRealStageStaysSession() {
        typealias Policy = MenuBarListenOnlyInterferenceSource.Policy
        XCTAssertNil(Policy.disabled.location)
        XCTAssertEqual(Policy.isolatedListenOnly.location, .cgSessionEventTap)
        XCTAssertEqual(Policy.isolatedLocalAcceptance.location, .cgAnnotatedSessionEventTap)
    }
    func testPreAnnotationWindowMissingIsDiagnosedAndNeverMaterializesForeignPacket() throws {
        let packet = MenuBarLocalStartReceipt.Packet(event())
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123), packetReads = 0
        func materialize() -> MenuBarLocalStartReceipt.Packet { packetReads += 1; return packet }
        // Stage-input simulation, not invented field values from the old live run.
        m.observeMouseUp(type: CGEventType.leftMouseUp.rawValue, pointerWindow: 0, handlingWindow: 0,
            packet: materialize(), eventCount: 1, now: 1000)
        m.observeMouseUp(type: CGEventType.leftMouseUp.rawValue, pointerWindow: 99, handlingWindow: 100,
            packet: materialize(), eventCount: 2, now: 1010)
        m.observeMouseUp(type: CGEventType.keyDown.rawValue, pointerWindow: 7, handlingWindow: 7,
            packet: materialize(), eventCount: 3, now: 1020)
        XCTAssertEqual(packetReads, 0)
        XCTAssertEqual(m.capture.leftUpCallbacks, 2)
        XCTAssertEqual(m.capture.missingWindowCallbacks, 1)
        XCTAssertEqual(m.capture.otherWindowCallbacks, 1)
        XCTAssertFalse(m.matchFacts(packet, eventCount: 3, now: 1020)["tapCandidatePresent"]!)
        XCTAssertNil(m.claim(packet, eventCount: 3, now: 1020, session: UUID()))
        let encoded = String(decoding: try JSONEncoder().encode(m.capture), as: UTF8.self)
        XCTAssertFalse(encoded.contains("99")); XCTAssertFalse(encoded.contains("100,"))
    }
    func testAnnotatedOwnWindowStillRequiresFullExactPacket() {
        let e = event(), packet = MenuBarLocalStartReceipt.Packet(e)
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123)
        m.observeMouseUp(type: e.type.rawValue, pointerWindow: 0, handlingWindow: 7,
            packet: packet, eventCount: 1, now: 1000)
        XCTAssertEqual(m.capture.ownWindowCallbacks, 1)
        XCTAssertEqual(m.capture.lastPointerRelation, "missing")
        XCTAssertEqual(m.capture.lastHandlingRelation, "own")
        let moved = e.copy()!; moved.location.x += 0.5
        let modified = e.copy()!; modified.flags = .maskShift
        XCTAssertNil(m.claim(.init(moved), eventCount: 1, now: 1010, session: UUID()))
        XCTAssertNil(m.claim(.init(modified), eventCount: 1, now: 1010, session: UUID()))
        XCTAssertNotNil(m.claim(packet, eventCount: 1, now: 1010, session: UUID()))
    }
    func testAppKitBeforeTapCanMatchOnlyTheSameEventWithinFixedDeadline() {
        let packet = MenuBarLocalStartReceipt.Packet(event())
        let attempt = MenuBarLocalStartReceipt.Attempt(packet: packet, startedAt: 1000)
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123)
        XCTAssertNil(m.claim(attempt.packet, eventCount: 1, now: 1000, session: UUID()))
        XCTAssertTrue(attempt.canAwait(now: 1000, candidatePresent: false))
        m.observeMouseUp(type: packet.type, pointerWindow: 7, handlingWindow: 7,
            packet: packet, eventCount: 2, now: 1100)
        XCTAssertTrue(attempt.withinDeadline(now: 1101))
        XCTAssertNotNil(m.claim(attempt.packet, eventCount: 2, now: 1101, session: UUID()))
        XCTAssertFalse(attempt.canAwait(now: 1250, candidatePresent: false))
        XCTAssertFalse(attempt.withinDeadline(now: 1251))
        XCTAssertFalse(attempt.withinDeadline(now: 999))
    }
    func testWaitingNeverAcceptsAnotherRecentEventOrLaterActivity() {
        let e = event(), original = MenuBarLocalStartReceipt.Packet(e)
        let attempt = MenuBarLocalStartReceipt.Attempt(packet: original, startedAt: 1000)
        var m = MenuBarLocalStartReceipt(window: 7, pid: 123)
        e.timestamp += 1
        m.observeMouseUp(type: e.type.rawValue, pointerWindow: 7, handlingWindow: 7,
            packet: .init(e), eventCount: 5, now: 1100)
        XCTAssertNil(m.claim(attempt.packet, eventCount: 5, now: 1101, session: UUID()))
        XCTAssertFalse(attempt.canAwait(now: 1101, candidatePresent: true))
        m.observeMouseUp(type: original.type, pointerWindow: 7, handlingWindow: 7,
            packet: original, eventCount: 6, now: 1110)
        XCTAssertNil(m.claim(attempt.packet, eventCount: 7, now: 1111, session: UUID()))
    }

    func testSignedAndZeroNumbersStillNeedTheExactOwnedPacket() {
        for number in [Int64(-32768), -20895, -1, 0, 1, 32767] {
            let e = event(); e.setIntegerValueField(.mouseEventNumber, value: number)
            let packet = MenuBarLocalStartReceipt.Packet(e)
            XCTAssertEqual(packet.number, number)
            var m = MenuBarLocalStartReceipt(window: 7, pid: 123)
            XCTAssertNil(m.claim(packet, eventCount: 1, now: 1000, session: UUID()))
            m.observeMouseUp(type: e.type.rawValue, pointerWindow: 99, handlingWindow: 99,
                packet: packet, eventCount: 1, now: 1000)
            XCTAssertNil(m.claim(packet, eventCount: 1, now: 1000, session: UUID()))
            m.observeMouseUp(type: e.type.rawValue, pointerWindow: 7, handlingWindow: 7,
                packet: packet, eventCount: 2, now: 1001)
            let differentNumber = e.copy()!; differentNumber.setIntegerValueField(.mouseEventNumber, value: number + 1)
            let differentSource = e.copy()!; differentSource.setIntegerValueField(.eventSourceUnixProcessID, value: packet.sourcePID + 1)
            XCTAssertNil(m.claim(.init(differentNumber), eventCount: 2, now: 1010, session: UUID()))
            XCTAssertNil(m.claim(.init(differentSource), eventCount: 2, now: 1010, session: UUID()))
            XCTAssertNil(m.claim(packet, eventCount: 3, now: 1010, session: UUID()))
            let proof = m.claim(packet, eventCount: 2, now: 1010, session: UUID())
            XCTAssertEqual(proof?.0.eventNumber, Int(number))
            XCTAssertNil(m.claim(packet, eventCount: 2, now: 1011, session: UUID()))
        }
    }
    func testRecordedNegativePacketReplayStillRejectsTheOlderHIDClock() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("docs/evidence/menu-bar-local-annotated-synthetic-2026-10-05/result.json")
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let traces = try XCTUnwrap(record["startReceiptTraces"] as? [[String: Any]])
        let trace = try XCTUnwrap(traces.last), comparison = try XCTUnwrap(trace["comparison"] as? [String: Any])
        let tap = try JSONDecoder().decode(MenuBarLocalStartReceipt.Packet.self, from: JSONSerialization.data(withJSONObject: comparison["tapPacket"]!))
        let appKit = try JSONDecoder().decode(MenuBarLocalStartReceipt.Packet.self, from: JSONSerialization.data(withJSONObject: comparison["appKitPacket"]!))
        let window = try XCTUnwrap(trace["configuredWindow"] as? Int), pid = try XCTUnwrap(record["controllerPID"] as? Int32)
        let observedAt = try XCTUnwrap(comparison["tapObservedAt"] as? UInt64), claimAt = try XCTUnwrap(comparison["claimObservedAt"] as? UInt64)
        let eventCount = try XCTUnwrap(comparison["tapEventCount"] as? Int), current = try XCTUnwrap(comparison["currentEventCount"] as? Int)
        var receipt = MenuBarLocalStartReceipt(window: window, pid: pid)
        receipt.observeMouseUp(type: tap.type, pointerWindow: Int64(window), handlingWindow: Int64(window),
            packet: tap, eventCount: eventCount, now: observedAt)
        XCTAssertEqual(appKit, tap); XCTAssertEqual(appKit.number, -20895)
        XCTAssertNotNil(receipt.claim(appKit, eventCount: current, now: claimAt, session: UUID()))
        let entry = try XCTUnwrap(record["startEntry"] as? [String: Any]), up = try XCTUnwrap(entry["timestampSeconds"] as? Double)
        let delta = try XCTUnwrap(trace["publicActivityDeltaMilliseconds"] as? Double)
        let activity = MenuBarLocalStartReceipt.ActivityComparison(hidActivity: up + delta / 1000, upTimestamp: up)
        XCTAssertEqual(activity.relation, .earlierHIDActivity)
        XCTAssertFalse(activity.matchesExactUp) // Fixing signedness never waives the next guard.
        XCTAssertNil(receipt.claim(appKit, eventCount: current, now: claimAt + 1, session: UUID()))
    }
    func testOlderAndLaterHardwareActivityRemainDifferentStrictRefusals() {
        typealias A = MenuBarLocalStartReceipt.ActivityComparison
        let earlier = A(hidActivity: 10 - 0.041923, upTimestamp: 10)
        XCTAssertEqual(earlier.relation, .earlierHIDActivity); XCTAssertFalse(earlier.matchesExactUp)
        let later = A(hidActivity: 10.005, upTimestamp: 10)
        XCTAssertEqual(later.relation, .laterHIDActivity); XCTAssertFalse(later.matchesExactUp)
        XCTAssertTrue(A(hidActivity: 10, upTimestamp: 10).matchesExactUp)
        XCTAssertFalse(A(hidActivity: nil, upTimestamp: 10).matchesExactUp)
        XCTAssertFalse(A(hidActivity: .nan, upTimestamp: 10).matchesExactUp)
        XCTAssertFalse(A(hidActivity: 10, upTimestamp: .infinity).matchesExactUp)
        // Subsequent hardware activity invalidates the epoch even after quiet returns.
        XCTAssertTrue(MenuBarListenOnlyInterferenceSource.physicalActivityChanged(previous: 10, now: 11, age: 0.99))
    }

}
