// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import ApplicationServices
import Foundation

/// Public, read-only window checks for the isolated UI click helper. Each failed
/// native read retains its API error and exact field; none is retried or cached.
final class MenuBarLocalUIReadback {
    struct Failure: Error, CustomStringConvertible {
        let check: String, reason: String
        var description: String { "\(check):\(reason)" }
    }
    struct Reads {
        var owner: (AXUIElement) -> (AXError, pid_t)
        var timeout: (AXUIElement, Float) -> AXError
        var attribute: (AXUIElement, String) -> (AXError, CFTypeRef?)
        var windows: () -> [[String: Any]]?
        static var native: Self {
            .init(owner: { e in var pid: pid_t = 0; let error = AXUIElementGetPid(e, &pid); return (error, pid) },
                timeout: { AXUIElementSetMessagingTimeout($0, $1) }, attribute: { e, key in
                    var value: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(e, key as CFString, &value)
                    return (error, value)
                }, windows: { CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] })
        }
    }
    let pid: pid_t, reads: Reads
    var phase = "initial"
    private(set) var trace: [[String: Any]] = []
    init(pid: pid_t, reads: Reads = .native) { self.pid = pid; self.reads = reads }
    func check(_ name: String, _ passed: Bool, reason: String, facts: [String: Any] = [:]) throws {
        trace.append(facts.merging(["check": phase + "." + name, "passed": passed]) { _, new in new })
        if !passed { throw Failure(check: phase + "." + name, reason: reason) }
    }
    func attribute(_ e: AXUIElement, _ key: String, label: String, required: Bool = false) throws -> CFTypeRef? {
        let name = label + "." + key, began = DispatchTime.now().uptimeNanoseconds
        let (ownerError, owner) = reads.owner(e)
        guard ownerError == .success, owner == pid else {
            let facts: [String: Any] = ["AXError": ownerError.rawValue, "ownerPID": owner, "expectedPID": pid]
            if required { try check(name, false, reason: "owner", facts: facts) }
            else { trace.append(facts.merging(["check": phase + "." + name, "passed": false]) { _, new in new }) }
            return nil
        }
        let timeoutError = reads.timeout(e, 0.1)
        let (error, value) = reads.attribute(e, key)
        let facts: [String: Any] = ["AXError": error.rawValue, "timeoutSetupError": timeoutError.rawValue,
            "durationNs": DispatchTime.now().uptimeNanoseconds - began, "hasValue": value != nil,
            "valueTypeID": value.map(CFGetTypeID) ?? 0]
        let passed = error == .success && value != nil
        if required { try check(name, passed, reason: "AXError(\(error.rawValue))", facts: facts) }
        else { trace.append(facts.merging(["check": phase + "." + name, "passed": passed]) { _, new in new }) }
        return passed ? value : nil
    }
    func frame(_ e: AXUIElement, label: String) throws -> CGRect {
        let p = try attribute(e, kAXPositionAttribute, label: label, required: true)!
        let s = try attribute(e, kAXSizeAttribute, label: label, required: true)!
        try check(label + ".positionType", CFGetTypeID(p) == AXValueGetTypeID(), reason: "notAXValue")
        try check(label + ".sizeType", CFGetTypeID(s) == AXValueGetTypeID(), reason: "notAXValue")
        var point = CGPoint.zero, size = CGSize.zero
        try check(label + ".positionDecode", AXValueGetValue(p as! AXValue, .cgPoint, &point), reason: "notCGPoint")
        try check(label + ".sizeDecode", AXValueGetValue(s as! AXValue, .cgSize, &size), reason: "notCGSize")
        try check(label + ".finitePositiveFrame", point.x.isFinite && point.y.isFinite &&
            size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0, reason: "invalidFrame")
        return CGRect(origin: point, size: size)
    }
    func cgWindow(_ windowID: UInt32) throws -> CGRect {
        let rows = reads.windows()
        try check("cg.onScreenList", rows != nil, reason: "unavailable")
        let ownID = rows!.filter { $0[kCGWindowNumber as String] as? UInt32 == windowID }
        try check("cg.windowID", ownID.count == 1, reason: "expectedOne", facts: ["expectedWindowID": windowID, "count": ownID.count])
        let row = ownID[0]
        try check("cg.ownerPID", row[kCGWindowOwnerPID as String] as? Int32 == pid, reason: "ownerMismatch",
            facts: ["expectedPID": pid, "observedPID": row[kCGWindowOwnerPID as String] ?? NSNull()])
        try check("cg.layer", row[kCGWindowLayer as String] as? Int == 0, reason: "notNormalLayer",
            facts: ["observedLayer": row[kCGWindowLayer as String] ?? NSNull()])
        let b = row[kCGWindowBounds as String] as? NSDictionary
        try check("cg.boundsDictionary", b != nil, reason: "missingOrWrongType")
        let f = b.flatMap { CGRect(dictionaryRepresentation: $0) }
        try check("cg.boundsDecode", f != nil, reason: "invalidBounds")
        try check("cg.finitePositiveFrame", f!.minX.isFinite && f!.minY.isFinite && f!.width.isFinite &&
            f!.height.isFinite && f!.width > 0 && f!.height > 0, reason: "invalidFrame")
        return f!
    }
}
