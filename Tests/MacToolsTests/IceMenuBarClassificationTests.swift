// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CoreGraphics
@testable import MacTools

final class IceMenuBarClassificationTests: XCTestCase {
    private typealias C = IceMenuBarClassification
    private typealias M = MenuBarHiddenMoveModel
    private let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private func signature(apple: Bool = true, identifier: String = "com.apple.WindowServer") -> MenuBarProcessSignature.Proof {
        .init(pid: 385, launch: 500, executable: "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
            identifier: identifier, team: nil, sha256: String(repeating: "b", count: 64), appleAnchor: apple)
    }
    private func rows(carrierLayer: Int = 24) -> [C.PublicMember] {
        [.init(windowID: 1, pid: 202, frame: CGRect(x: -4341, y: 0, width: 29, height: 37), layer: 25, alpha: 1),
         .init(windowID: 2, pid: 29904, frame: CGRect(x: -1998, y: 0, width: 3472, height: 37), layer: 25, alpha: 1),
         .init(windowID: 3, pid: 385, frame: CGRect(x: 0, y: 0, width: 1728, height: 37), layer: carrierLayer, alpha: 1)]
    }
    private func directory(_ rows: [C.PublicMember]) -> IceMenuBarReadAdapter.Directory {
        .init(memberIDs: rows.map(\.windowID), members: rows.map { .init(windowID: $0.windowID, frame: $0.frame, spaces: [7]) },
              spaceBefore: 7, spaceAfter: 7, enumerationComplete: true)
    }
    func testAuthenticatedCarrierIsAccountedAndWideControlStaysAStatusItem() throws {
        let r = rows(), p = try C.partition(directory(r), before: r, after: r, display: display, signatures: [signature()])
        XCTAssertEqual(p.rawIDs, [1, 2, 3]); XCTAssertEqual(p.statusIDs, [1, 2])
        XCTAssertEqual(p.carriers.map(\.windowID), [3]); XCTAssertFalse(p.logicalOrderProven)
    }
    func testLiveAppleCarrierRoleDoesNotRequireOrInventItsKernelStartTime() throws {
        let r = rows(), old = signature()
        let live = MenuBarProcessSignature.Proof(pid: old.pid, launch: nil, executable: old.executable,
            identifier: old.identifier, team: old.team, sha256: old.sha256, appleAnchor: true)
        let p = try C.partition(directory(r), before: r, after: r, display: display, signatures: [live])
        XCTAssertEqual(p.carriers.count, 1); XCTAssertNil(p.carriers[0].signature.launch)
        let f = MenuBarHiddenMoveFixture()
        func sample(_ sequence: UInt64, _ time: UInt64) -> M.Snapshot {
            let base = f.sample(sequence, time)
            return .init(sequence: sequence, uptimeMilliseconds: time, scope: base.scope, owner: base.owner,
                items: base.items, membershipIDs: [1, 2, 3, 99], orderEvidence: .observedCoordinates,
                carriers: [.init(windowID: 99, signature: live, frame: p.carriers[0].frame, layer: 24, spaces: [7])])
        }
        let plan = try M.Plan.capture(sample(1, 1000), sample(2, 1100), now: 1100)
        let changed = M.Snapshot(sequence: 3, uptimeMilliseconds: 1200, scope: f.scope(continuity: UUID()),
            owner: plan.original.owner, items: plan.original.items, membershipIDs: plan.original.membershipIDs,
            orderEvidence: .observedCoordinates, carriers: plan.original.carriers)
        XCTAssertEqual(try M.inspectRecovery(M.Record.prepared(plan: plan), first: changed,
            second: .init(sequence: 4, uptimeMilliseconds: 1300, scope: changed.scope, owner: changed.owner,
                items: changed.items, membershipIDs: changed.membershipIDs, orderEvidence: changed.orderEvidence, carriers: changed.carriers),
            now: 1300), .environmentChanged)
    }
    func testUnknownLayerUnverifiedAppleAndMissingMembersRejectInsteadOfFiltering() {
        for r in [rows(carrierLayer: 26), rows(carrierLayer: 0)] {
            XCTAssertThrowsError(try C.partition(directory(r), before: r, after: r, display: display, signatures: [signature()]))
        }
        let r = rows()
        for signatures in [[], [signature(apple: false)], [signature(identifier: "spoof.WindowServer")]] {
            XCTAssertThrowsError(try C.partition(directory(r), before: r, after: r, display: display, signatures: signatures))
        }
        XCTAssertThrowsError(try C.partition(directory(r), before: Array(r.dropLast()), after: Array(r.dropLast()), display: display, signatures: [signature()]))
    }
    func testCarrierRemainsInHiddenCaptureRecoveryAndCannotDisappear() throws {
        let f = MenuBarHiddenMoveFixture(), r = rows()
        let carrier = try XCTUnwrap(C.partition(directory(r), before: r, after: r, display: display, signatures: [signature()]).carriers.first)
        func sample(_ sequence: UInt64, _ time: UInt64, accounted: Bool = true) -> M.Snapshot {
            let base = f.sample(sequence, time)
            return .init(sequence: sequence, uptimeMilliseconds: time, scope: base.scope, owner: base.owner,
                items: base.items, membershipIDs: [1, 2, 3, 99], orderEvidence: .observedCoordinates,
                carriers: accounted ? [.init(windowID: 99, signature: carrier.signature, frame: carrier.frame,
                    layer: carrier.layer, spaces: carrier.spaces)] : nil)
        }
        let p = try M.Plan.capture(sample(1, 1000), sample(2, 1100), now: 1100)
        XCTAssertEqual(p.original.membershipIDs, [1, 2, 3, 99]); XCTAssertEqual(p.anchor.capturedOrder.count, 3)
        XCTAssertEqual(p.original.carriers?.count, 1)
        XCTAssertThrowsError(try M.Plan.capture(sample(1, 1000, accounted: false), sample(2, 1100, accounted: false), now: 1100))
        XCTAssertThrowsError(try p.verifyReturned(sample(3, 1200, accounted: false), sample(4, 1300, accounted: false), now: 1300))
    }
}
