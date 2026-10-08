// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarInputAttributionTests: XCTestCase {
    private typealias A = MenuBarInputAttribution
    private func envelope(pid: Int64 = 20, marker: Int64 = 100, timestamp: UInt64 = 200,
                          window: Int64 = 2, point: CGPoint = .init(x: 1480, y: 18)) -> A.Envelope {
        .init(type: CGEventType.leftMouseDown.rawValue, timestamp: timestamp, sourcePID: pid,
            sourceState: Int64(CGEventSourceStateID.privateState.rawValue), targetPID: 202,
            marker: marker, window: window, handlingWindow: 2, privateWindow: 2, number: 1,
            flags: CGEventFlags.maskCommand.rawValue, point: point)
    }
    func testExactPreRegisteredEmissionHasSingleUseReceipt() throws {
        var r = A.Registry(senderPID: 20); let gesture = UUID(), e = envelope()
        XCTAssertEqual(r.consume(e, now: 1000), .unknown)
        try r.register(e, gesture: gesture, now: 1000)
        XCTAssertEqual(r.consume(e, now: 1020), .ownGesture(gesture))
        XCTAssertEqual(r.consume(e, now: 1021), .unknown)
    }
    func testMarkerOnlyPIDOnlyAndShapeChangesDoNotAttributeAnEvent() throws {
        let expected = envelope()
        for candidate in [envelope(pid: 21), envelope(marker: 101), envelope(timestamp: 201),
                          envelope(window: 3), envelope(point: .init(x: 1481, y: 18))] {
            var r = A.Registry(senderPID: 20)
            try r.register(expected, gesture: UUID(), now: 1000)
            XCTAssertEqual(r.consume(candidate, now: 1020), .unknown)
            XCTAssertNotNil(r.pending)
        }
    }
    func testStaleFutureAndDuplicateRegistrationsCannotClaimOwnGesture() throws {
        for time: UInt64 in [999, 1101] {
            var r = A.Registry(senderPID: 20)
            try r.register(envelope(), gesture: UUID(), now: 1000)
            XCTAssertEqual(r.consume(envelope(), now: time), .unknown)
            XCTAssertThrowsError(try r.register(envelope(), gesture: UUID(), now: time))
            r.abandon(); XCTAssertNil(r.pending)
        }
        var r = A.Registry(senderPID: 20)
        XCTAssertThrowsError(try r.register(envelope(pid: 21), gesture: UUID(), now: 1000))
        XCTAssertThrowsError(try r.register(envelope(marker: 0), gesture: UUID(), now: 1000))
        XCTAssertThrowsError(try r.register(envelope(window: 3), gesture: UUID(), now: 1000))
    }
    func testListenOnlySourceIsDisconnectedUntilExplicitStart() {
        let source = MenuBarListenOnlyInterferenceSource()
        XCTAssertFalse(source.created); XCTAssertEqual(source.observedEventCount, 0)
        XCTAssertThrowsError(try source.start())
        if case .unavailable(.notConnected) = source.read() { } else { XCTFail("Default listener must stay disconnected") }
        XCTAssertFalse(source.created); XCTAssertEqual(source.observedEventCount, 0)
    }
    func testInitialQuietRequiresWarmupAndRecentActivityAbsenceWithoutInferringKeyState() {
        typealias S = MenuBarListenOnlyInterferenceSource
        XCTAssertTrue(S.initialQuiet(now: 1250, startedAt: 1000, age: 0.25))
        XCTAssertFalse(S.initialQuiet(now: 1249, startedAt: 1000, age: 1))
        XCTAssertFalse(S.initialQuiet(now: 1250, startedAt: 1000, age: 0.249))
        XCTAssertFalse(S.initialQuiet(now: 999, startedAt: 1000, age: 1))
        XCTAssertFalse(S.initialQuiet(now: 1250, startedAt: 1000, age: .nan))
        XCTAssertFalse(S.initialQuiet(now: 1250, startedAt: 1000, age: .infinity))
        XCTAssertFalse(S.initialQuiet(now: 1250, startedAt: 1000, age: -1))
    }
    func testUnlistedPhysicalActivityStillInvalidatesAfterItHasBecomeQuietAgain() {
        typealias S = MenuBarListenOnlyInterferenceSource
        XCTAssertFalse(S.physicalActivityChanged(previous: nil, now: 2, age: 1))
        XCTAssertFalse(S.physicalActivityChanged(previous: 1, now: 2, age: 1))
        XCTAssertFalse(S.physicalActivityChanged(previous: 1, now: 2, age: 0.999))
        XCTAssertTrue(S.initialQuiet(now: 2000, startedAt: 1000, age: 0.3))
        XCTAssertTrue(S.physicalActivityChanged(previous: 1, now: 2, age: 0.3))
    }
    func testNormalActivityDuringReadIsUnavailableButDoesNotClaimListenerLossOrIdle() {
        typealias S = MenuBarListenOnlyInterferenceSource
        XCTAssertTrue(S.ReadCause.activityDuringRead.monitoringHealthy)
        XCTAssertTrue(S.ReadCause.warmupOrRecentActivity.monitoringHealthy)
        XCTAssertEqual(S.refusal(for: .activityDuringRead), .notConnected)
        XCTAssertEqual(S.refusal(for: .warmupOrRecentActivity), .notConnected)
        var gate = MenuBarMoveInterference.Gate()
        XCTAssertThrowsError(try gate.begin(.unavailable(S.refusal(for: .activityDuringRead)), now: 1000))
        XCTAssertNil(gate.lease)
    }
    func testActualPortLossTimeoutPermissionAndBadClockRemainUnhealthyAndRefused() {
        typealias S = MenuBarListenOnlyInterferenceSource
        for cause in [S.ReadCause.invalidPort, .disabledPort, .permissionMissing, .callbackTimeout,
                      .callbackDisabledByUserInput, .queueOverflow, .invalidActivityAge, .wrongThread] {
            XCTAssertFalse(cause.monitoringHealthy)
            XCTAssertEqual(S.refusal(for: cause), .sourceLost)
        }
        let source = S()
        XCTAssertEqual(source.diagnostics().readCause, .notStarted)
        XCTAssertFalse(source.diagnostics().monitoringHealthy)
    }

}
