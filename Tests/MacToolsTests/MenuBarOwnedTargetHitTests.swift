// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

/// AX handles are opaque memory tokens. Every read is injected; no desktop AX query.
final class MenuBarOwnedTargetHitTests: XCTestCase {
    typealias H = MenuBarOwnedTargetHit
    final class Fixture {
        let app = AXUIElementCreateApplication(123), extras = AXUIElementCreateApplication(124)
        let target = AXUIElementCreateApplication(125), other = AXUIElementCreateApplication(126)
        var frame = CGRect(x: 1400, y: 6.5, width: 29, height: 24)
        var role = kAXMenuBarItemRole, help = "MacTools 自建验收图标 T", pid: Int32 = 123
        var missing = false, duplicate = false, missingExtras = false, hit: AXUIElement?
        var onHit: (() -> Void)?, targetReads = 0, onOwner: (() -> Void)?
        var reads: H.Reads {
            .init(app: { _ in self.app }, attribute: { element, key in
                if CFEqual(element, self.app), key == kAXExtrasMenuBarAttribute { return self.missingExtras ? nil : self.extras }
                if CFEqual(element, self.extras), key == kAXChildrenAttribute {
                    return (self.missing ? [] : self.duplicate ? [self.target, self.other] : [self.target]) as CFArray
                }
                if key == kAXRoleAttribute { return self.role as CFString }
                if key == kAXHelpAttribute { return self.help as CFString }
                if key == kAXPositionAttribute { var p = self.frame.origin; return AXValueCreate(.cgPoint, &p) }
                if key == kAXSizeAttribute { var s = self.frame.size; return AXValueCreate(.cgSize, &s) }
                return nil
            }, owner: { element in
                if CFEqual(element, self.app) || CFEqual(element, self.extras) { return 123 }
                self.targetReads += 1; self.onOwner?(); return self.pid
            }, hit: { point in
                XCTAssertEqual(point, CGPoint(x: 1414.5, y: 18.5)); self.onHit?(); return self.hit ?? self.target
            }, same: { CFEqual($0, $1) })
        }
        func verify() throws -> H.Proof { try H.verify(pid: 123, window: 88, frame: frame, now: 1000, reads: reads) }
    }
    func testExactElementOwnerRoleHelpAndGeometryPassTogether() throws {
        let f = Fixture(), p = try f.verify()
        XCTAssertEqual(p.pid, 123); XCTAssertEqual(p.windowID, 88); XCTAssertEqual(p.frame, f.frame)
        XCTAssertEqual(f.targetReads, 3)
    }
    func testContainerForeignAndSameLookingOtherElementNeverPass() {
        for scenario in 0..<3 {
            let f = Fixture()
            if scenario == 0 { f.hit = f.extras; f.onHit = { f.role = kAXMenuBarRole } }
            if scenario == 1 { f.onHit = { f.pid = 999 } }
            if scenario == 2 { f.hit = f.other }
            XCTAssertThrowsError(try f.verify())
        }
    }
    func testMissingDuplicateOrIncorrectSemanticIdentityRefuses() {
        for scenario in 0..<5 {
            let f = Fixture()
            if scenario == 0 { f.missing = true }
            if scenario == 1 { f.duplicate = true }
            if scenario == 2 { f.missingExtras = true }
            if scenario == 3 { f.help = "MacTools 自建验收图标 N" }
            if scenario == 4 { f.role = kAXButtonRole }
            XCTAssertThrowsError(try f.verify())
        }
    }
    func testGeometryChangingAtHitOrFinalReadCannotPassOldFrame() {
        for atHit in [true, false] {
            let f = Fixture()
            if atHit { f.onHit = { f.frame.origin.x += 1 } }
            else { f.onOwner = { if f.targetReads == 3 { f.frame.origin.x += 1 } } }
            XCTAssertThrowsError(try f.verify())
        }
    }
    func testInvalidGeometryRejectedBeforeAnyRead() {
        let f = Fixture()
        for frame in [CGRect.zero, CGRect(x: CGFloat.infinity, y: 0, width: 29, height: 24)] {
            XCTAssertThrowsError(try H.verify(pid: 123, window: 88, frame: frame, now: 0, reads: f.reads))
        }
        XCTAssertEqual(f.targetReads, 0)
    }
}
