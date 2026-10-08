import XCTest
@testable import MacTools

final class MenuBarMoveInterferenceTests: XCTestCase {
    private typealias I = MenuBarMoveInterference
    private struct SimulatedSource: MenuBarMoveInterferenceSource {
        var value: I.Availability
        func read() -> I.Availability { value }
    }
    private let continuity = UUID(), externalEpoch = UUID()
    private func sample(_ sequence: UInt64 = 1, _ time: UInt64 = 1000, continuity: UUID? = nil,
                        epoch: UUID? = nil, coverage: Set<I.Coverage> = I.requiredCoverage) -> I.Snapshot {
        I.Snapshot(sequence: sequence, uptimeMilliseconds: time, continuity: continuity ?? self.continuity,
                   externalEpoch: epoch ?? externalEpoch, coverage: coverage, buttons: [], keys: [], modifiers: 0)
    }
    private func expect(_ failure: I.Failure, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? I.Failure, failure, file: file, line: line) }
    }
    func testDisconnectedAndPermissionRequiredAreUnavailableWithoutRequestingAccess() {
        let disconnected = MenuBarMoveDisconnectedInterferenceSource()
        var gate = I.Gate()
        expect(.unavailable(.notConnected)) { _ = try gate.begin(disconnected.read(), now: 1000) }
        let denied = SimulatedSource(value: .unavailable(.permissionRequired))
        expect(.unavailable(.permissionRequired)) { _ = try gate.begin(denied.read(), now: 1000) }
        XCTAssertNil(gate.lease); XCTAssertEqual(gate.state, .idle)
    }
    func testEachMissingCoverageCannotBeTreatedAsNoUserInput() {
        for missing in I.requiredCoverage {
            var gate = I.Gate()
            let coverage = I.requiredCoverage.subtracting([missing])
            expect(.incomplete) { _ = try gate.begin(.available(sample(coverage: coverage)), now: 1000) }
            XCTAssertNil(gate.lease)
        }
    }
    func testHeldButtonKeyOrModifierRefusesBaselineAndActionBoundary() throws {
        for index in 0...2 {
            var busy = sample()
            if index == 0 { busy.buttons = [0] }
            if index == 1 { busy.keys = [12] }
            if index == 2 { busy.modifiers = 1 }
            var initial = I.Gate()
            expect(.notIdle) { _ = try initial.begin(.available(busy), now: 1000) }
            var armed = I.Gate(); let lease = try armed.begin(.available(sample()), now: 1000)
            busy = I.Snapshot(sequence: 2, uptimeMilliseconds: 1100, continuity: busy.continuity,
                externalEpoch: busy.externalEpoch, coverage: busy.coverage, buttons: busy.buttons, keys: busy.keys, modifiers: busy.modifiers)
            expect(.notIdle) { _ = try armed.verifyBoundary(.available(busy), now: 1100) }
            XCTAssertEqual(armed.lease, lease); XCTAssertEqual(armed.state, .blocked(.notIdle))
        }
    }
    func testOwnAttributedGestureAllowsOnlyFreshIdleBoundary() throws {
        var gate = I.Gate(); let lease = try gate.begin(.available(sample()), now: 1000)
        try gate.observe(I.Event(sequence: 2, uptimeMilliseconds: 1050, continuity: continuity, attribution: .ownGesture(lease.gesture)), now: 1050)
        XCTAssertEqual(try gate.verifyBoundary(.available(sample(3, 1100)), now: 1100), lease)
        expect(.busy) { _ = try gate.begin(.available(sample(4, 1150)), now: 1150) }
        gate.finish(); XCTAssertNil(gate.lease)
    }
    func testUserOrAmbiguousInputBlocksPermanentlyEvenIfNextSnapshotIsIdle() throws {
        for attribution in [I.Attribution.userOrOther, .unknown, .ownGesture(UUID())] {
            var gate = I.Gate(); let lease = try gate.begin(.available(sample()), now: 1000)
            let failure: I.Failure = attribution == .userOrOther || attribution == .unknown ? .interference : .unexpectedOwnGesture
            expect(failure) { try gate.observe(I.Event(sequence: 2, uptimeMilliseconds: 1100, continuity: continuity, attribution: attribution), now: 1100) }
            expect(failure) { _ = try gate.verifyBoundary(.available(sample(3, 1200)), now: 1200) }
            gate.sourceUnavailable(.sourceLost)
            XCTAssertEqual(gate.state, .blocked(failure)) // Preserve the first intervention reason.
            XCTAssertEqual(gate.lease, lease)
        }
    }
    func testExternalEpochChangeDetectsConcurrentActionEvenWhenNoEventWasDelivered() throws {
        var gate = I.Gate(); _ = try gate.begin(.available(sample()), now: 1000)
        expect(.interference) { _ = try gate.verifyBoundary(.available(sample(2, 1100, epoch: UUID())), now: 1100) }
        XCTAssertEqual(gate.state, .blocked(.interference))
    }
    func testLossOfCapabilityOrContinuityCannotResumeWithOldLease() throws {
        var gate = I.Gate(); let lease = try gate.begin(.available(sample()), now: 1000)
        expect(.continuityLost) { _ = try gate.verifyBoundary(.available(sample(2, 1100, continuity: UUID())), now: 1100) }
        expect(.continuityLost) { _ = try gate.verifyBoundary(.available(sample(3, 1200)), now: 1200) }
        XCTAssertEqual(gate.lease, lease)
        var lost = I.Gate(); _ = try lost.begin(.available(sample()), now: 1000)
        lost.sourceUnavailable(.sourceLost)
        expect(.unavailable(.sourceLost)) { _ = try lost.verifyBoundary(.available(sample(2, 1100)), now: 1100) }
        var revoked = I.Gate(); _ = try revoked.begin(.available(sample()), now: 1000)
        expect(.unavailable(.permissionRequired)) { _ = try revoked.verifyBoundary(.unavailable(.permissionRequired), now: 1100) }
    }
    func testStaleRepeatedFutureAndBackwardsTimeSamplesBlockInsteadOfPassing() throws {
        for invalid in [sample(1, 1100), sample(2, 999), sample(2, 1201), sample(2, 1100)] {
            var gate = I.Gate(); _ = try gate.begin(.available(sample()), now: 1000)
            let now: UInt64 = invalid.uptimeMilliseconds == 1100 && invalid.sequence == 2 ? 1400 : 1200
            expect(.stale) { _ = try gate.verifyBoundary(.available(invalid), now: now) }
            XCTAssertEqual(gate.state, .blocked(.stale))
        }
    }
    func testInterferenceFailureRetainsModelAndFileRecoveryResponsibility() throws {
        let f = try MenuBarMoveAdapterFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("move-input-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = MenuBarTemporaryMoveJournal(directory: directory)
        _ = try journal.persist(f.record, replacing: nil, boundTo: f.owner)
        var model = MenuBarTemporaryMoveModel.Machine(pending: f.record)
        var gate = I.Gate(); _ = try gate.begin(.available(sample()), now: 1000)
        expect(.interference) { try gate.observe(I.Event(sequence: 2, uptimeMilliseconds: 1100, continuity: continuity, attribution: .userOrOther), now: 1100) }
        model.invalidate(.interference)
        gate.finish() // Ending the input lease has no journal-clear side effect.
        XCTAssertEqual(model.pending, f.record); XCTAssertEqual(model.state, .needsRecovery)
        XCTAssertEqual(try journal.inspect(), f.record)
        XCTAssertFalse(MenuBarTemporaryMoveModel.backendEnabled)
    }
}
