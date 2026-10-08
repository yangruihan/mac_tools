// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarHiddenMoveModelTests: XCTestCase {
    private typealias M = MenuBarHiddenMoveModel
    private func capture(_ f: MenuBarHiddenMoveFixture, items: [M.Item]? = nil,
                         membership: [UInt32]? = nil, evidence: M.OrderEvidence? = nil) throws -> M.Plan {
        try .capture(f.sample(1, 1000, items: items, membership: membership, evidence: evidence),
                     f.sample(2, 1100, items: items, membership: membership, evidence: evidence), now: 1100)
    }
    func testHiddenNegativeCoordinatesAreRecordedWithBothNeighborIdentities() throws {
        let f = MenuBarHiddenMoveFixture(), p = try f.plan()
        XCTAssertFalse(M.backendEnabled); XCTAssertFalse(p.original.completeLogicalOrderProven)
        XCTAssertEqual(p.original.items[1].frame.minX, -4341)
        XCTAssertEqual(p.anchor.left?.windowID, 1); XCTAssertEqual(p.anchor.right?.windowID, 3)
        XCTAssertEqual(p.anchor.boundary, .interior)
        let record = try f.record()
        XCTAssertEqual(try JSONDecoder().decode(M.Record.self, from: JSONEncoder().encode(record)), record)
    }
    func testOwnerNonceItemInstanceAndProcessLaunchAreNotInterchangeable() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record()
        for owner in [f.owner(nonce: UUID()), f.owner(instance: UUID())] {
            XCTAssertEqual(try M.inspectRecovery(record, first: f.sample(3, 1200, owner: owner),
                second: f.sample(4, 1300, owner: owner), now: 1300), .identityChanged)
        }
        var items = f.original.items
        let old = items[1].identity
        let app = old.application!
        let recycled = MenuBarRecordedTarget(MenuBarStatusTarget(id: old.windowID, pid: old.pid, frame: .zero,
            onScreen: false, application: .init(bundleID: app.bundleID, bundlePath: app.bundlePath, launch: app.launch + 1)))
        items[1] = f.item(1, identity: recycled)
        XCTAssertEqual(try M.inspectRecovery(record, first: f.sample(3, 1200, items: items),
            second: f.sample(4, 1300, items: items), now: 1300), .identityChanged)
    }
    func testShownTargetUnknownVisibilityAndMalformedOnScreenCannotClaimHidden() throws {
        let f = MenuBarHiddenMoveFixture()
        var items = f.original.items; items[1] = f.item(1, listed: true, onScreen: .ordered, visibility: true)
        XCTAssertThrowsError(try capture(f, items: items))
        items = f.original.items; let t = items[1]
        items[1] = .init(identity: t.identity, frame: t.frame, listedOnScreen: false, onScreen: .missing,
            alpha: 1, spaces: [7], ownerOcclusionVisible: nil)
        XCTAssertThrowsError(try capture(f, items: items))
        items[1] = f.item(1, onScreen: .malformed)
        XCTAssertThrowsError(try capture(f, items: items))
    }
    func testMissingDuplicateAndOverlappingPeersRejectWithoutFilteringHiddenItems() throws {
        let f = MenuBarHiddenMoveFixture()
        XCTAssertThrowsError(try capture(f, items: Array(f.original.items.dropFirst())))
        XCTAssertThrowsError(try capture(f, membership: [1, 2, 2, 3]))
        var items = f.original.items; items[0] = f.item(0, frame: CGRect(x: -4350, y: 0, width: 30, height: 37))
        XCTAssertThrowsError(try capture(f, items: items))
        XCTAssertThrowsError(try capture(f, evidence: .unknown))
    }
    func testMissingTargetCannotCaptureAnOtherwiseConsistentInventory() throws {
        let f = MenuBarHiddenMoveFixture(), peers = f.original.items.filter { $0.identity != f.original.owner.target }
        XCTAssertThrowsError(try capture(f, items: peers, membership: peers.map { $0.identity.windowID }))
        XCTAssertFalse(M.backendEnabled)
    }
    func testFreshStablePairAndFiniteGeometryAreRequiredBeforeCapturingResponsibility() throws {
        let f = MenuBarHiddenMoveFixture()
        XCTAssertThrowsError(try M.Plan.capture(f.sample(1, 1000), f.sample(2, 1099), now: 1099))
        XCTAssertThrowsError(try M.Plan.capture(f.sample(1, 1000), f.sample(2, 1600), now: 1600))
        XCTAssertThrowsError(try M.Plan.capture(f.sample(1, 1000), f.sample(2, 1100), now: 1351))
        XCTAssertThrowsError(try M.Plan.capture(f.sample(1, 1000), f.sample(2, 1100), now: 1099))
        var items = f.original.items; items[1] = f.item(1, frame: CGRect(x: CGFloat.nan, y: 0, width: 29, height: 37))
        XCTAssertThrowsError(try capture(f, items: items))
    }
    func testExactReturnedStateNeedsTwoNewSamplesAndCannotClearAfterEnvironmentLoss() throws {
        let f = MenuBarHiddenMoveFixture(), r = try f.record()
        let returned = try r.confirmedReturned(f.sample(3, 1200), f.sample(4, 1300), now: 1300)
        try returned.validateStructure()
        XCTAssertEqual(try M.inspectRecovery(r, first: f.sample(3, 1200), second: f.sample(4, 1300), now: 1300), .originalStateObserved)
        XCTAssertEqual(try M.inspectRecovery(r, first: f.sample(1, 1000), second: f.sample(2, 1100), now: 1300), .retained)
        XCTAssertEqual(try M.inspectRecovery(r, first: f.sample(3, 1200), second: f.sample(4, 1300), now: 1551), .retained)
        XCTAssertThrowsError(try r.confirmedReturned(f.sample(3, 1200), f.sample(4, 1300), now: 1551))
        XCTAssertThrowsError(try r.confirmedReturned(f.sample(3, 1200), f.sample(4, 1300), now: 1299))
        for scope in [f.scope(continuity: UUID()), f.scope(space: 8), f.scope(scale: 1)] {
            XCTAssertEqual(try M.inspectRecovery(r, first: f.sample(3, 1200, scope: scope),
                second: f.sample(4, 1300, scope: scope), now: 1300), .environmentChanged)
            XCTAssertThrowsError(try r.confirmedReturned(f.sample(3, 1200, scope: scope), f.sample(4, 1300, scope: scope), now: 1300))
        }
        var forged = r; forged.phase = .restored
        XCTAssertThrowsError(try forged.validateStructure())
    }
    func testChangedPeerGeometryOrAnchorCannotBeAcknowledgedAsRestored() throws {
        let f = MenuBarHiddenMoveFixture(), r = try f.record()
        var items = f.original.items; items[0] = f.item(0, frame: CGRect(x: -4372, y: 0, width: 30, height: 37))
        XCTAssertThrowsError(try r.confirmedReturned(f.sample(3, 1200, items: items), f.sample(4, 1300, items: items), now: 1300))
        let p = r.plan
        let changed = M.Plan(first: p.first, original: p.original, anchor: .init(left: p.anchor.right, right: p.anchor.left,
            boundary: .interior, capturedOrder: p.anchor.capturedOrder, evidence: p.anchor.evidence))
        XCTAssertThrowsError(try changed.validateStructure())
        let forgedPair = M.Plan(first: f.sample(1, 1000, items: items), original: p.original, anchor: p.anchor)
        XCTAssertThrowsError(try forgedPair.validateStructure())
    }
}
