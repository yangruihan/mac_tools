// Isolated copy: diagnostics directory allowlist changed; original file unchanged.
// Optional, bounded owner-side reads only. Compiling does not launch an app.
// No status/window setters, activation, AX actions, input or preference writes.
import AppKit
import CoreGraphics
import Darwin

@MainActor
final class NativeAcceptanceTargetsDiagnostic: NSObject {
    private let directory: URL
    private let nonce: String
    private let items: () -> [NSStatusItem]
    private let started = ContinuousClock.now
    private var instances: [ObjectIdentifier: UUID] = [:]
    private var timer: Timer?
    private var sequence = 0
    private var errorReported = false
    var extraState: (() -> [String: Any])?
    var beforeTick: (() -> Void)?
    var budgetReached: (() -> Void)?

    static func configured(items: @escaping () -> [NSStatusItem]) -> NativeAcceptanceTargetsDiagnostic? {
        let args = CommandLine.arguments
        guard args.count == 5, args[1] == "--diagnostic-directory", args[3] == "--diagnostic-nonce",
              (args[2] == "/tmp/mac-tools-native-owner-window-task7/owner-state" ||
               args[2].hasPrefix("/tmp/mac-tools-ice-interface-product-candidate-20261009/Worker/session-") && args[2].hasSuffix("/owner-state")),
              UUID(uuidString: args[4]) != nil else { return nil }
        return NativeAcceptanceTargetsDiagnostic(directory: URL(fileURLWithPath: args[2]), nonce: args[4], items: items)
    }
    private init(directory: URL, nonce: String, items: @escaping () -> [NSStatusItem]) {
        self.directory = directory; self.nonce = nonce; self.items = items
    }
    func start() {
        publish(phase: "didFinishLaunching")
        let tick = Timer(timeInterval: 0.1, target: self, selector: #selector(sampleTick), userInfo: nil, repeats: true)
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        publish(phase: "willTerminate")
    }
    @objc private func sampleTick() {
        guard sequence < 2002, started.duration(to: .now) < .seconds(200) else {
            budgetReached?(); timer?.invalidate(); timer = nil; return
        }
        beforeTick?()
        publish(phase: "timer")
    }
    private func number(_ n: Double) -> Any { n.isFinite ? n : ["nonfinite": String(describing: n)] }
    private func rect(_ r: CGRect) -> [String: Any] {
        ["x": number(r.minX), "y": number(r.minY), "width": number(r.width), "height": number(r.height)]
    }
    private func field(_ row: [String: Any], _ key: CFString) -> [String: Any] {
        guard let value = row[key as String] else { return ["present": false] }
        var out: [String: Any] = ["present": true, "swiftType": String(describing: type(of: value)),
                                   "cfTypeID": CFGetTypeID(value as CFTypeRef)]
        if let n = value as? NSNumber {
            out["objcType"] = String(cString: n.objCType)
            out["value"] = CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : number(n.doubleValue)
        } else if let d = value as? [String: Any] {
            out["value"] = d.mapValues { v in (v as? NSNumber).map { number($0.doubleValue) } ?? String(describing: v) }
        } else { out["value"] = String(describing: value) }
        return out
    }
    private func cg(_ option: CGWindowListOption, pid: Int32) -> [String: Any] {
        guard let rows = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] else {
            return ["available": false]
        }
        let keys: [CFString] = [kCGWindowNumber, kCGWindowOwnerPID, kCGWindowLayer, kCGWindowBounds,
                               kCGWindowAlpha, kCGWindowIsOnscreen]
        let own = rows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        return ["available": true, "ownRows": own.map { row in
            Dictionary(uniqueKeysWithValues: keys.map { ($0 as String, field(row, $0)) })
        }]
    }
    func model(_ item: NSStatusItem) -> [String: Any] {
        let identifier = ObjectIdentifier(item)
        if instances[identifier] == nil { instances[identifier] = UUID() }
        var out: [String: Any] = ["itemInstance": instances[identifier]!.uuidString,
            "itemKey": item.autosaveName ?? "", "itemVisible": item.isVisible, "itemLength": number(item.length)]
        guard let button = item.button else { out["buttonPresent"] = false; return out }
        out["buttonPresent"] = true; out["title"] = button.title
        out["buttonHidden"] = button.isHidden; out["buttonHiddenOrAncestor"] = button.isHiddenOrHasHiddenAncestor
        out["buttonBounds"] = rect(button.bounds)
        guard let window = button.window else { out["windowPresent"] = false; return out }
        out["windowPresent"] = true; out["windowNumber"] = window.windowNumber
        out["windowVisible"] = window.isVisible; out["windowOnActiveSpace"] = window.isOnActiveSpace
        out["windowOcclusionState"] = window.occlusionState.rawValue
        out["windowOcclusionVisible"] = window.occlusionState.contains(.visible)
        out["windowAlpha"] = number(window.alphaValue); out["windowLevel"] = window.level.rawValue
        out["windowFrameAppKit"] = rect(window.frame)
        let screenButton = window.convertToScreen(button.convert(button.bounds, to: nil))
        out["buttonScreenAppKit"] = rect(screenButton)
        if let screen = window.screen {
            out["screenFrameAppKit"] = rect(screen.frame)
            out["screenDisplayID"] = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? NSNull()
        }
        // Quartz global y uses the main display upper edge, not NSScreen.main
        // (which can follow keyboard focus). Preserve source coordinates too.
        if let primary = NSScreen.screens.first {
            out["buttonScreenQuartz"] = rect(CGRect(x: screenButton.minX,
                y: primary.frame.maxY - screenButton.maxY, width: screenButton.width, height: screenButton.height))
        }
        return out
    }
    private func publish(phase: String) {
        sequence += 1
        let pid = ProcessInfo.processInfo.processIdentifier
        var process = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, Int32(MemoryLayout<proc_bsdinfo>.size))
        let modelsBefore = items().map(model)
        let allBefore = cg(.optionAll, pid: pid)
        let onScreen = cg(.optionOnScreenOnly, pid: pid)
        let allAfter = cg(.optionAll, pid: pid)
        let modelsAfter = items().map(model)
        let dt = started.duration(to: .now).components
        var out: [String: Any] = ["schemaVersion": 1, "phase": phase, "sequence": sequence,
            "nonce": nonce, "pid": pid, "bundleID": Bundle.main.bundleIdentifier ?? "",
            "bundlePath": Bundle.main.bundleURL.resolvingSymlinksInPath().path,
            "atUnix": Date().timeIntervalSince1970, "atUTC": ISO8601DateFormatter().string(from: Date()),
            "elapsedMilliseconds": Double(dt.seconds) * 1000 + Double(dt.attoseconds) / 1e15,
            "mainThread": Thread.isMainThread, "modelsBefore": modelsBefore, "modelsAfter": modelsAfter,
            "cgAllBefore": allBefore, "cgOnScreen": onScreen, "cgAllAfter": allAfter,
            "ownActiveSpaceVisibleWindowNumbers": NSWindow.windowNumbers(options: []) ?? [],
            "ownAllSpacesVisibleWindowNumbers": NSWindow.windowNumbers(options: .allSpaces) ?? [],
            "frontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1]
        if let extraState { out["menuControl"] = extraState() }
        if size == MemoryLayout<proc_bsdinfo>.size, process.pbi_start_tvsec > 0 {
            out["kernelLaunch"] = Double(process.pbi_start_tvsec) + Double(process.pbi_start_tvusec) / 1_000_000
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
            let file = directory.appendingPathComponent(String(format: "%04d.json", sequence))
            try data.write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
        } catch {
            // Diagnostics must never terminate, show UI or alter the fixture.
            if !errorReported {
                errorReported = true
                fputs("owner-diagnostic.publish: \(error)\n", stderr)
            }
        }
    }
}
