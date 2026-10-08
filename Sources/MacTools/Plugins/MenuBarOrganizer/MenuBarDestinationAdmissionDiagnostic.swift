// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import CoreGraphics

/// Diagnostic only. The native sampler retains its original admission predicate.
enum MenuBarDestinationAdmissionDiagnostic {
    struct Geometry: Codable, Equatable {
        let x: Double, y: Double, width: Double, height: Double
        init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    }
    struct AXFact: Codable {
        let frame: Geometry, centerInsideStatus: Bool, fullyInsideRightSafe: Bool
    }
    struct Row: Codable {
        let windowID: UInt32, pid: Int32, applicationPath: String?
        let frame: Geometry, onScreenField: String
        let formalPathMatches: Bool, listedOnScreen: Bool, widthLessThan64: Bool, axQueried: Bool
        let expectedAX: [AXFact], jointAXMatch: Bool, diagnosticQualified: Bool
        var selectedByNativePredicate: Bool = false
        var failedField: String {
            if !formalPathMatches { return "applicationPath" }
            if !listedOnScreen { return "listedOnScreen" }
            if !widthLessThan64 { return "widthLessThan64" }
            if !axQueried { return "AXNotEvaluated" }
            if expectedAX.isEmpty { return "expectedAXDescriptionOrCompleteGeometry" }
            if !expectedAX.contains(where: \.centerInsideStatus) { return "AXCenterInsideStatus" }
            if !expectedAX.contains(where: \.fullyInsideRightSafe) { return "AXFullyInsideRightSafe" }
            if !jointAXMatch { return "sameAXElementMustSatisfyBoth" }
            return "none"
        }
    }
    struct Report: Codable {
        let atUnix: Double, activeSpace: UInt64, rightSafe: Geometry
        let targetWindowID: UInt32, targetPID: Int32, targetFrame: Geometry?
        let rows: [Row], selectedWindowID: UInt32?
    }
    static func row(windowID: UInt32, pid: Int32, path: String?, frame: CGRect, listed: Bool,
                    onScreenField: String, rightSafe: CGRect, expectedAXFrames: [CGRect]?) -> Row {
        let facts = (expectedAXFrames ?? []).map { r in
            AXFact(frame: .init(r), centerInsideStatus: frame.contains(CGPoint(x: r.midX, y: r.midY)), fullyInsideRightSafe: rightSafe.contains(r))
        }
        let pathMatches = path == "/Applications/MacTools.app", width = frame.width < 64
        let joint = facts.contains { $0.centerInsideStatus && $0.fullyInsideRightSafe }
        return .init(windowID: windowID, pid: pid, applicationPath: path, frame: .init(frame), onScreenField: onScreenField,
            formalPathMatches: pathMatches, listedOnScreen: listed, widthLessThan64: width, axQueried: expectedAXFrames != nil,
            expectedAX: facts, jointAXMatch: joint, diagnosticQualified: pathMatches && listed && width && joint)
    }
}
