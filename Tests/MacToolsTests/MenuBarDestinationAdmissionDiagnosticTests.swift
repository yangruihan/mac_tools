// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarDestinationAdmissionDiagnosticTests: XCTestCase {
    let safe = CGRect(x: 956, y: 0, width: 772, height: 32)
    func row(path: String = "/Applications/MacTools.app", frame: CGRect = CGRect(x: 1474, y: 0, width: 38, height: 37),
             listed: Bool = true, axes: [CGRect]? = [CGRect(x: 1473, y: 6.5, width: 39.5, height: 24)]) -> MenuBarDestinationAdmissionDiagnostic.Row {
        MenuBarDestinationAdmissionDiagnostic.row(windowID: 314679, pid: 29904, path: path, frame: frame, listed: listed,
            onScreenField: listed ? "ordered" : "missing", rightSafe: safe, expectedAXFrames: axes)
    }
    func testCurrentCGAndAXDifferentWidthsAreQualifiedByExistingCenterRule() {
        let r = row(); XCTAssertTrue(r.diagnosticQualified); XCTAssertEqual(r.failedField, "none")
        XCTAssertTrue(r.expectedAX[0].centerInsideStatus); XCTAssertTrue(r.expectedAX[0].fullyInsideRightSafe)
        XCTAssertFalse(r.selectedByNativePredicate) // A diagnostic cannot grant actual admission.
    }
    func testVisibilityDropWithIdenticalIdentityAndGeometryRemainsRejected() {
        let r = row(listed: false, axes: nil)
        XCTAssertFalse(r.diagnosticQualified); XCTAssertEqual(r.failedField, "listedOnScreen"); XCTAssertFalse(r.axQueried)
    }
    func testIdentityWidthAndMissingAXAreDistinguishable() {
        XCTAssertEqual(row(path: "/tmp/Fake.app").failedField, "applicationPath")
        XCTAssertEqual(row(frame: CGRect(x: 0, y: 0, width: 3472, height: 37)).failedField, "widthLessThan64")
        XCTAssertEqual(row(axes: []).failedField, "expectedAXDescriptionOrCompleteGeometry")
    }
    func testWrongCenterAndUnsafeHeightAreSeparatelyRejected() {
        XCTAssertEqual(row(axes: [CGRect(x: 1300, y: 6.5, width: 39.5, height: 24)]).failedField, "AXCenterInsideStatus")
        XCTAssertEqual(row(axes: [CGRect(x: 1473, y: 10, width: 39.5, height: 24)]).failedField, "AXFullyInsideRightSafe")
    }
    func testTwoDifferentAXElementsCannotCombineIntoAFalseMatch() {
        let r = row(axes: [CGRect(x: 1473, y: 10, width: 39.5, height: 24), CGRect(x: 1300, y: 6.5, width: 39.5, height: 24)])
        XCTAssertFalse(r.diagnosticQualified); XCTAssertEqual(r.failedField, "sameAXElementMustSatisfyBoth")
    }
}
