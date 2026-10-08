// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import ApplicationServices
@testable import MacTools

final class MenuBarLocalUIReadbackTests: XCTestCase {
    typealias R = MenuBarLocalUIReadback
    final class Harness {
        let element = AXUIElementCreateApplication(123)
        var owner: pid_t = 123, error = AXError.success
        var values: [String: CFTypeRef] = [:], rows: [[String: Any]]? = []
        var queries = 0
        func reader() -> R {
            R(pid: 123, reads: .init(owner: { _ in (.success, self.owner) }, timeout: { _, _ in .success },
                attribute: { _, key in self.queries += 1; return (self.error, self.values[key]) }, windows: { self.rows }))
        }
        func frame(width: Double = 100) {
            var p = CGPoint(x: 584, y: 204), s = CGSize(width: width, height: 368)
            values[kAXPositionAttribute] = AXValueCreate(.cgPoint, &p)
            values[kAXSizeAttribute] = AXValueCreate(.cgSize, &s)
        }
        func window() {
            rows = [[kCGWindowNumber as String: UInt32(7), kCGWindowOwnerPID as String: Int32(123),
                kCGWindowLayer as String: 0, kCGWindowBounds as String: CGRect(x: 584, y: 204, width: 560, height: 368).dictionaryRepresentation]]
        }
    }
    func failure(_ check: String, _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? R.Failure)?.check, check, file: file, line: line)
        }
    }
    func testAXCannotCompleteIsReportedWithOriginalErrorAndNeverRetried() {
        let h = Harness(); h.error = .cannotComplete; let r = h.reader()
        failure("initial.app.AXWindows") { _ = try r.attribute(h.element, kAXWindowsAttribute, label: "app", required: true) }
        XCTAssertEqual(h.queries, 1)
        XCTAssertEqual(r.trace.last?["AXError"] as? Int32, AXError.cannotComplete.rawValue)
        XCTAssertNotNil(r.trace.last?["durationNs"])
    }
    func testOwnerMismatchDoesNotReadForeignElement() {
        let h = Harness(); h.owner = 999; let r = h.reader()
        failure("initial.app.AXWindows") { _ = try r.attribute(h.element, kAXWindowsAttribute, label: "app", required: true) }
        XCTAssertEqual(h.queries, 0); XCTAssertEqual(r.trace.last?["ownerPID"] as? Int32, 999)
    }
    func testAXFrameDistinguishesMissingWrongTypeAndWrongValueKind() {
        let h = Harness(); h.frame(); h.values.removeValue(forKey: kAXPositionAttribute)
        failure("initial.window.AXPosition") { _ = try h.reader().frame(h.element, label: "window") }
        h.values[kAXPositionAttribute] = "wrong" as CFString
        failure("initial.window.positionType") { _ = try h.reader().frame(h.element, label: "window") }
        h.values[kAXPositionAttribute] = h.values[kAXSizeAttribute]
        failure("initial.window.positionDecode") { _ = try h.reader().frame(h.element, label: "window") }
    }
    func testAXFrameRejectsZeroNegativeAndNonfiniteSizes() {
        for width in [0.0, -1, .infinity, .nan] {
            let h = Harness(); h.frame(width: width)
            failure("initial.button.finitePositiveFrame") { _ = try h.reader().frame(h.element, label: "button") }
        }
    }
    func testCGListMissingWindowWrongOwnerAndLayerAreSeparate() {
        let h = Harness(); h.rows = nil
        failure("initial.cg.onScreenList") { _ = try h.reader().cgWindow(7) }
        h.rows = []
        failure("initial.cg.windowID") { _ = try h.reader().cgWindow(7) }
        h.window(); h.rows![0][kCGWindowOwnerPID as String] = Int32(999)
        failure("initial.cg.ownerPID") { _ = try h.reader().cgWindow(7) }
        h.window(); h.rows![0][kCGWindowLayer as String] = 1
        failure("initial.cg.layer") { _ = try h.reader().cgWindow(7) }
    }
    func testCGBoundsMissingAndMalformedAreSeparate() {
        let h = Harness(); h.window(); h.rows![0].removeValue(forKey: kCGWindowBounds as String)
        failure("initial.cg.boundsDictionary") { _ = try h.reader().cgWindow(7) }
        h.rows![0][kCGWindowBounds as String] = ["wrong": 1]
        failure("initial.cg.boundsDecode") { _ = try h.reader().cgWindow(7) }
    }
    func testSecondCheckUsesFreshDataAndLabelsThePhase() throws {
        let h = Harness(); h.frame(); h.window(); let r = h.reader()
        XCTAssertEqual(try r.cgWindow(7), CGRect(x: 584, y: 204, width: 560, height: 368))
        XCTAssertEqual(try r.frame(h.element, label: "button"), CGRect(x: 584, y: 204, width: 100, height: 368))
        r.phase = "beforePost"; h.rows = []
        failure("beforePost.cg.windowID") { _ = try r.cgWindow(7) }
        XCTAssertFalse(r.trace.last?["passed"] as! Bool)
    }
}
