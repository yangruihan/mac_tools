// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarOwnedFixtureMoveDriverTests: XCTestCase {
    typealias M = MenuBarHiddenMoveModel
    private final class Channel: MenuBarOwnedEventChannel {
        let privateEventSource = CGEventSource(stateID: .privateState)!
        var posts = 0
        func emit(_ event: CGEvent, gesture: UUID) throws { posts += 1 }
        func release(_ event: CGEvent, gesture: UUID) { posts += 1 }
    }
    private final class Observations: MenuBarOwnedFixtureObservations {
        let fixture = MenuBarHiddenMoveFixture()
        var now: UInt64 = 1300
        var unsafeButton = false, hitRejected = false, scopeChangesBetweenPairs = false, neighborDisappears = false
        var pairs = 0
        var destinationMissing = false
        var pairShowsVisible = true, targetMissing = false
        enum Failure: Error { case destinationMissing, hitRejected }
        func items(moved: Bool) -> [M.Item] {
            [fixture.item(0),
             fixture.item(1, frame: moved ? CGRect(x: 1454, y: 0, width: 29, height: 37) : nil,
                          listed: moved, onScreen: moved ? .ordered : .missing, visibility: moved),
             fixture.item(2, frame: CGRect(x: 1483, y: 0, width: 30, height: 37), listed: true, onScreen: .ordered)]
        }
        func plan() throws -> M.Plan {
            try M.Plan.capture(fixture.sample(1, 1000, items: items(moved: false)), fixture.sample(2, 1100, items: items(moved: false)), now: 1100)
        }
        func pair() throws -> (M.Snapshot, M.Snapshot) {
            pairs += 1
            let current = items(moved: pairShowsVisible).filter {
                (!targetMissing || $0.identity != fixture.original.owner.target) &&
                (!neighborDisappears || pairs < 2 || $0.identity != fixture.original.items[2].identity)
            }
            let scope = scopeChangesBetweenPairs && pairs >= 2 ? fixture.scope(space: 8) : nil
            return (fixture.sample(3, 1200, items: current, scope: scope), fixture.sample(4, 1300, items: current, scope: scope))
        }
        func admission(_ plan: M.Plan) throws -> MenuBarRecordedTarget {
            if destinationMissing { throw Failure.destinationMissing }
            return fixture.original.items[2].identity
        }
        func button(_ owner: M.Owner) throws -> CGRect {
            if hitRejected { throw Failure.hitRejected }
            return CGRect(x: 1454, y: unsafeButton ? 25 : 6.5, width: 29, height: 24)
        }
        func menu(_ owner: M.Owner, open: Bool) throws {}
        func cancelMenu(_ owner: M.Owner) throws {}
    }
    func testFullStatusWindowHeight37AndSafeButtonArea32AreDistinguished() throws {
        let observation = Observations(), channel = Channel()
        let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
        let plan = try observation.plan()
        XCTAssertEqual(plan.original.scope.rightSafe.height, 32)
        try driver.admit(plan); try driver.verifyVisible(plan)
        XCTAssertEqual(channel.posts, 0)
    }
    func testButtonOutsideSafeAreaStillRejectsWithoutEvents() throws {
        let observation = Observations(), channel = Channel(); observation.unsafeButton = true
        let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
        let plan = try observation.plan(); try driver.admit(plan)
        XCTAssertThrowsError(try driver.verifyVisible(plan)); XCTAssertEqual(channel.posts, 0)
    }
    func testRealModeStillRejectsMissingDestinationBeforeAnyPost() throws {
        let observation = Observations(), channel = Channel(); observation.destinationMissing = true
        let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
        XCTAssertThrowsError(try driver.admit(observation.plan()))
        XCTAssertEqual(channel.posts, 0)
    }
    func testTargetDisappearingAfterAdmissionCannotReachTheMouseChannel() throws {
        for missing in [false, true] {
            let observation = Observations(), channel = Channel(); observation.pairShowsVisible = false
            let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
            let plan = try observation.plan(); try driver.admit(plan)
            observation.targetMissing = missing
            let lease = MenuBarMoveInterference.Lease(gesture: UUID(), continuity: UUID(), externalEpoch: UUID(), interferenceEpoch: UUID())
            if missing { XCTAssertThrowsError(try driver.moveToVisible(plan, lease: lease)) }
            else { try driver.moveToVisible(plan, lease: lease) }
            XCTAssertEqual(channel.posts, missing ? 0 : 2) // In-memory channel, never a native sender.
        }
    }
    func testFreshGlobalHitFailureBetweenVisibleProofAndClickNeverPosts() throws {
        let observation = Observations(), channel = Channel()
        let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
        let plan = try observation.plan(); try driver.admit(plan); try driver.verifyVisible(plan)
        observation.hitRejected = true
        let lease = MenuBarMoveInterference.Lease(gesture: UUID(), continuity: UUID(), externalEpoch: UUID(), interferenceEpoch: UUID())
        XCTAssertThrowsError(try driver.openOwnedMenu(plan.original.owner, lease: lease)); XCTAssertEqual(channel.posts, 0)
    }
    func testRestoreCannotCrossScopeOrLoseOriginalRightNeighborBetweenPairs() throws {
        for changed in 0..<3 {
            let observation = Observations(), channel = Channel()
            observation.scopeChangesBetweenPairs = changed == 1; observation.neighborDisappears = changed == 2
            let driver = MenuBarOwnedFixtureMoveDriver(observations: observation, mouse: MenuBarOwnedMouseTransport(channel: channel))
            let plan = try observation.plan(); try driver.admit(plan)
            let lease = MenuBarMoveInterference.Lease(gesture: UUID(), continuity: UUID(), externalEpoch: UUID(), interferenceEpoch: UUID())
            if changed == 0 { try driver.restore(plan, lease: lease); XCTAssertEqual(channel.posts, 2) }
            else { XCTAssertThrowsError(try driver.restore(plan, lease: lease)); XCTAssertEqual(channel.posts, 0) }
        }
    }

}
