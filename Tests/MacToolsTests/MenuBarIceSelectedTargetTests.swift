import XCTest
import AppKit
@testable import MacTools

final class MenuBarIceSelectedTargetTests: XCTestCase {
    private func proof(pid: Int32 = 10, launch: Double = 1, sha: String = String(repeating:"a",count:64)) -> MenuBarProcessSignature.Proof {
        .init(pid:pid,launch:launch,executable:"/Applications/Test.app/Contents/MacOS/Test",identifier:"test.owner",
              team:nil,sha256:sha,appleAnchor:false)
    }
    private let row = MenuBarIceSelectedTarget.Row(id:100,pid:10,title:"App",frame:CGRect(x:-1000,y:0,width:30,height:24))
    private func directory(_ rows: [MenuBarIceSelectedTarget.Row], space: UInt64 = 2) -> MenuBarIceSelectedTarget.Directory {
        .init(display:1,space:space,rows:rows)
    }
    private func target() throws -> MenuBarIceSelectedTarget { try .init(row:row,directory:directory([row]),owner:proof()) }
    private func sample(_ n: Int, _ t: Double, popup: Bool = false, owner: MenuBarProcessSignature.Proof? = nil,
                        space: UInt64 = 2, healthy: Bool = true) -> MenuBarIceManualMenuClose.Sample {
        .init(sequence:n,uptime:t,owner:owner ?? proof(),display:1,space:space,healthy:healthy,
              windows:popup ? [.init(id:200,pid:10,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))] : [])
    }
    func testExactBindingAllowsMovementButRejectsRestartPIDAndSignatureChange() throws {
        let target = try target()
        let moved = MenuBarIceSelectedTarget.Row(id:100,pid:10,title:"App",frame:CGRect(x:900,y:0,width:30,height:24))
        XCTAssertEqual(try target.validate(directory:directory([moved]),owner:proof()).frame,moved.frame)
        for changed in [proof(pid:11),proof(launch:2),proof(sha:String(repeating:"b",count:64))] {
            XCTAssertThrowsError(try target.validate(directory:directory([row]),owner:changed))
        }
        let bytes = try JSONEncoder().encode(target)
        XCTAssertEqual(try JSONDecoder().decode(MenuBarIceSelectedTarget.self,from:bytes),target)
    }
    func testNoSiblingRematchingDuplicateWindowOrSpaceChange() throws {
        let target = try target()
        let sibling = MenuBarIceSelectedTarget.Row(id:101,pid:10,title:"App",frame:row.frame)
        XCTAssertThrowsError(try target.validate(directory:directory([sibling]),owner:proof()))
        XCTAssertThrowsError(try target.validate(directory:directory([row,row]),owner:proof()))
        XCTAssertThrowsError(try target.validate(directory:directory([row],space:3),owner:proof()))
        XCTAssertThrowsError(try MenuBarIceSelectedTarget(row:row,directory:directory([row,row]),owner:proof()))
    }
    func testNeverSeenMenuCannotAuthorizeReturnAndOneAbsentSampleIsUnknown() throws {
        var lease = MenuBarIceManualMenuClose(target:try target())
        try lease.begin(sample(1,1),now:1)
        XCTAssertEqual(lease.observe(sample(2,1.1),now:1.1),.unknown)
        XCTAssertThrowsError(try lease.requireClosed(now:1.1))
        XCTAssertEqual(lease.observe(sample(3,1.2,popup:true),now:1.2),.open)
        XCTAssertEqual(lease.observe(sample(4,1.3),now:1.3),.unknown)
        XCTAssertThrowsError(try lease.requireClosed(now:1.3))
        XCTAssertEqual(lease.observe(sample(5,1.41),now:1.41),.closed)
        XCTAssertNoThrow(try lease.requireClosed(now:1.41))
        XCTAssertThrowsError(try lease.requireClosed(now:1.7))
    }
    func testReopeningResetsCloseConfirmation() throws {
        var lease = MenuBarIceManualMenuClose(target:try target())
        try lease.begin(sample(1,1),now:1)
        _ = lease.observe(sample(2,1.1,popup:true),now:1.1)
        _ = lease.observe(sample(3,1.2),now:1.2)
        _ = lease.observe(sample(4,1.4),now:1.4)
        XCTAssertEqual(lease.observe(sample(5,1.5,popup:true),now:1.5),.open)
        XCTAssertThrowsError(try lease.requireClosed(now:1.5))
        XCTAssertEqual(lease.observe(sample(6,1.6),now:1.6),.unknown)
    }
    func testUnknownOwnerOrScopeAndUnhealthyObservationPermanentlyStop() throws {
        for bad in [sample(2,1.1,owner:proof(launch:2)),sample(2,1.1,space:3),sample(2,1.1,healthy:false),sample(1,1.1),sample(2,0.5)] {
            var lease = MenuBarIceManualMenuClose(target:try target())
            try lease.begin(sample(1,1),now:1)
            XCTAssertEqual(lease.observe(bad,now:1.1),.stopped)
            XCTAssertEqual(lease.observe(sample(3,1.2,popup:true),now:1.2),.stopped)
            XCTAssertThrowsError(try lease.requireClosed(now:1.2))
        }
    }
    func testExistingPopupAndCancellationCannotBeRearmed() throws {
        var lease = MenuBarIceManualMenuClose(target:try target())
        XCTAssertThrowsError(try lease.begin(sample(1,1,popup:true),now:1))
        XCTAssertThrowsError(try lease.begin(sample(2,1.1),now:1.1))
        var cancelled = MenuBarIceManualMenuClose(target:try target())
        try cancelled.begin(sample(1,1),now:1); cancelled.cancel()
        XCTAssertEqual(cancelled.observe(sample(2,1.1,popup:true),now:1.1),.stopped)
        XCTAssertThrowsError(try cancelled.requireClosed(now:1.1))
    }
    func testOtherOwnerPopupDoesNotProveSelectedMenuOpened() throws {
        var lease = MenuBarIceManualMenuClose(target:try target())
        try lease.begin(sample(1,1),now:1)
        let foreign = MenuBarIceManualMenuClose.Sample(sequence:2,uptime:1.1,owner:proof(),display:1,space:2,healthy:true,
                    windows:[.init(id:300,pid:11,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))])
        XCTAssertEqual(lease.observe(foreign,now:1.1),.unknown)
        XCTAssertEqual(lease.observe(sample(3,1.3),now:1.3),.unknown)
        XCTAssertThrowsError(try lease.requireClosed(now:1.3))
    }
}
