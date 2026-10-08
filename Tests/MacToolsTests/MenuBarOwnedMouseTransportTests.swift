// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
import Darwin
@testable import MacTools

final class MenuBarOwnedMouseTransportTests: XCTestCase {
    private final class Channel: MenuBarOwnedEventChannel {
        let privateEventSource = CGEventSource(stateID: .privateState)!
        enum Fault: Error { case unknown }
        var packets: [MenuBarInputAttribution.Envelope] = [], releases: [MenuBarInputAttribution.Envelope] = []
        var rejectLease = false
        func authorize(_ lease: MenuBarMoveInterference.Lease?) throws { if rejectLease { throw Fault.unknown } }
        var failAt: Int?
        func emit(_ event: CGEvent, gesture: UUID) throws {
            packets.append(MenuBarListenOnlyInterferenceSource.envelope(event))
            if packets.count == failAt { throw Fault.unknown }
        }
        func release(_ event: CGEvent, gesture: UUID) { releases.append(MenuBarListenOnlyInterferenceSource.envelope(event)) }
    }
    private func pair(_ transport: MenuBarOwnedMouseTransport, policy: MenuBarOwnedMouseTransport.Policy) throws {
        try transport.pair(pid: 234, downWindow: 31, upWindow: 32, start: CGPoint(x: 20_000, y: 20_000),
            end: CGPoint(x: 1483, y: 18.5), command: true, gesture: UUID(), policy: policy)
    }
    func testDefaultDisabledSendsNothing() throws {
        let channel = Channel()
        let transport = MenuBarOwnedMouseTransport(channel: channel)
        XCTAssertThrowsError(try pair(transport, policy: .disabled)); XCTAssertTrue(channel.packets.isEmpty)
    }
    func testCreatedPacketsAreAcceptedByExactPrivateStateRegistryWithoutPosting() throws {
        let channel = Channel(), transport = MenuBarOwnedMouseTransport(channel: channel)
        try pair(transport, policy: .isolatedOwnedFixture)
        XCTAssertEqual(channel.packets.count, 2); XCTAssertTrue(channel.releases.isEmpty)
        for packet in channel.packets {
            var registry = MenuBarInputAttribution.Registry(senderPID: getpid(), privateSourceState: Int64(channel.privateEventSource.sourceStateID.rawValue))
            let gesture = UUID(); try registry.register(packet, gesture: gesture, now: 100)
            XCTAssertEqual(registry.consume(packet, now: 110), .ownGesture(gesture))
            XCTAssertEqual(registry.consume(packet, now: 111), .unknown)
        }
        XCTAssertEqual(channel.packets.map(\.type), [CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue])
        XCTAssertEqual(channel.packets.map(\.window), [31, 32])
        XCTAssertEqual(Set(channel.packets.map(\.number)).count, 1)
        XCTAssertEqual(Set(channel.packets.map(\.marker)).count, 2)
        XCTAssertEqual(channel.packets[0].flags, CGEventFlags.maskCommand.rawValue)
    }
    func testUnknownDownOrUpReceiptReleasesOriginalOwnedWindowOnceAndThrows() throws {
        for failAt in [1, 2] {
            let channel = Channel(); channel.failAt = failAt
            let transport = MenuBarOwnedMouseTransport(channel: channel)
            XCTAssertThrowsError(try pair(transport, policy: .isolatedOwnedFixture))
            XCTAssertEqual(channel.packets.count, failAt); XCTAssertEqual(channel.releases.count, 1)
            XCTAssertEqual(channel.releases[0].type, CGEventType.leftMouseUp.rawValue)
            XCTAssertEqual(channel.releases[0].targetPID, 234); XCTAssertEqual(channel.releases[0].window, 31)
            XCTAssertEqual(channel.releases[0].point, CGPoint(x: 20_000, y: 20_000)); XCTAssertFalse(transport.active)
            XCTAssertEqual(channel.releases[0].number, channel.packets[0].number)
            XCTAssertFalse(channel.packets.map(\.marker).contains(channel.releases[0].marker))
        }
    }
    func testInvalidPacketStopsBeforeAnyChannelCall() throws {
        let channel = Channel()
        let transport = MenuBarOwnedMouseTransport(channel: channel)
        XCTAssertThrowsError(try transport.pair(pid: 0, downWindow: 31, upWindow: 32, start: .zero, end: .zero,
            command: true, gesture: UUID(), policy: .isolatedOwnedFixture))
        XCTAssertTrue(channel.packets.isEmpty); XCTAssertTrue(channel.releases.isEmpty)
    }
    func testChangedLeaseRefusesBeforeDownAndDoesNotIssueCleanupUp() throws {
        let channel = Channel(); channel.rejectLease = true
        let transport = MenuBarOwnedMouseTransport(channel: channel)
        XCTAssertThrowsError(try pair(transport, policy: .isolatedOwnedFixture))
        XCTAssertTrue(channel.packets.isEmpty); XCTAssertTrue(channel.releases.isEmpty)
    }

    func testSignedAndZeroNativePacketsRequireExactOneUseAttribution() throws {
        let source = CGEventSource(stateID: .privateState)!
        for number in [Int64(-32768), -20895, -1, 0, 1, 32767] {
            let event = try IceOwnedMouseEvent.make(type: .leftMouseUp, point: .init(x: 50, y: 20),
                pid: 234, window: 31, command: true, marker: 900, number: number, source: source)
            let expected = MenuBarListenOnlyInterferenceSource.envelope(event)
            XCTAssertEqual(expected.number, number)
            let gesture = UUID()
            var registry = MenuBarInputAttribution.Registry(senderPID: getpid(), privateSourceState: Int64(source.sourceStateID.rawValue))
            try registry.register(expected, gesture: gesture, now: 100)
            for field in [CGEventField.mouseEventNumber, .eventSourceUnixProcessID, .eventSourceStateID,
                          .eventTargetUnixProcessID, .mouseEventWindowUnderMousePointer,
                          .mouseEventWindowUnderMousePointerThatCanHandleThisEvent, CGEventField(rawValue: 0x33)!] {
                let changed = event.copy()!; changed.setIntegerValueField(field, value: changed.getIntegerValueField(field) + 1)
                XCTAssertEqual(registry.consume(MenuBarListenOnlyInterferenceSource.envelope(changed), now: 101), .unknown,
                    "field=\(field.rawValue), before=\(event.getIntegerValueField(field)), after=\(changed.getIntegerValueField(field))")
            }
            // This SDK preserves userData when modifying a copied event. Build
            // a genuinely different packet instead of assuming the setter worked.
            let otherMarker = try IceOwnedMouseEvent.make(type: .leftMouseUp, point: .init(x: 50, y: 20),
                pid: 234, window: 31, command: true, marker: 901, number: number, source: source)
            otherMarker.timestamp = expected.timestamp
            let otherEnvelope = MenuBarListenOnlyInterferenceSource.envelope(otherMarker)
            XCTAssertEqual(otherEnvelope.marker, 901)
            XCTAssertEqual(registry.consume(otherEnvelope, now: 101), .unknown)
            XCTAssertEqual(registry.consume(expected, now: 102), .ownGesture(gesture))
            XCTAssertEqual(registry.consume(expected, now: 103), .unknown)
        }
    }
    func testNativePairNumberWrapsWithoutReusingPerPacketMarkers() throws {
        for first in [Int16.max, -1] {
            let channel = Channel(), transport = MenuBarOwnedMouseTransport(channel: channel, firstEventNumber: first)
            try pair(transport, policy: .isolatedOwnedFixture); try pair(transport, policy: .isolatedOwnedFixture)
            XCTAssertEqual(channel.packets.map(\.number), [Int64(first), Int64(first), Int64(first &+ 1), Int64(first &+ 1)])
            XCTAssertEqual(Set(channel.packets.map(\.marker)).count, 4)
        }
    }
    func testPacketBuilderRejectsNumbersThatWouldSilentlyTruncate() {
        let source = CGEventSource(stateID: .privateState)!
        for number in [Int64(-32769), 32768, 65536, 700001] {
            XCTAssertThrowsError(try IceOwnedMouseEvent.make(type: .leftMouseUp, point: .zero, pid: 234,
                window: 31, command: true, marker: 900, number: number, source: source))
        }
    }

}
