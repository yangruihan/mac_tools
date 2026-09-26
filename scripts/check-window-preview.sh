#!/bin/sh
# Captures only this test process's own fixture window. Never requests permission.
set -eu
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
for i, p in enumerate(sorted(Path('Sources/MacTools').rglob('*.swift'))):
    Path(sys.argv[1], f'Source{i}.swift').write_text(p.read_text().replace('@main\nstruct MacToolsApp', 'struct MacToolsApp'))
PY
cat > "$TMP/Probe.swift" <<'SWIFT'
import AppKit
import ScreenCaptureKit
import CryptoKit

@main
struct Probe {
    static func main() {
        guard #available(macOS 14.0, *) else { print("SKIP: macOS 14+ required"); exit(77) }
        guard CGPreflightScreenCaptureAccess() else { print("SKIP: screen recording not authorized; no permission requested"); exit(77) }
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        let source = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 320, height: 180), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        source.title = "MacTools Capture Fixture"; source.isReleasedWhenClosed = true
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180)); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor; source.contentView = view; source.orderFrontRegardless()
        let cover = NSWindow(contentRect: source.contentLayoutRect, styleMask: [.titled], backing: .buffered, defer: false)
        cover.setFrame(source.frame, display: false); cover.title = "Fixture Occluder"; cover.isReleasedWhenClosed = false; cover.orderFrontRegardless()
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.windowID == CGWindowID(source.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else { throw Failure.message("Own fixture missing") }
                let first = try await WindowPreviewPlugin.capture(window)
                view.layer?.backgroundColor = NSColor.systemBlue.cgColor
                try await Task.sleep(nanoseconds: 300_000_000)
                let second = try await WindowPreviewPlugin.capture(window)
                guard let a = first.dataProvider?.data, let b = second.dataProvider?.data else { throw Failure.message("No image data") }
                let hashA = SHA256.hash(data: a as Data), hashB = SHA256.hash(data: b as Data)
                guard hashA != hashB, first.width > 0, second.width > 0 else { throw Failure.message("Covered source did not update") }
                print("REAL CAPTURE: own window only; covered source updates; distinct frame hashes=true; size=\(second.width)x\(second.height)")
                source.miniaturize(nil)
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let minimizedRecords = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID) as? [[String: Any]] ?? []
                print("MINIMIZED: isMiniaturized=\(source.isMiniaturized); records=\(minimizedRecords.count); onScreen=\(String(describing: minimizedRecords.first?[kCGWindowIsOnscreen as String]))")
                let allCG = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                print("MINIMIZED: CG-allContainsTarget=\(allCG.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.windowID }))")
                let allWindows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                print("MINIMIZED: ScreenCaptureKit-allContainsTarget=\(allWindows.windows.contains(where: { $0.windowID == window.windowID }))")
                do {
                    _ = try await WindowPreviewPlugin.capture(window)
                    throw Failure.message("Minimized source was captured")
                } catch is PreviewPaused {
                    print("MINIMIZED: paused (not closed)")
                }
                source.deminiaturize(nil)
                source.orderFrontRegardless(); cover.orderFrontRegardless()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let restoredRecords = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID) as? [[String: Any]] ?? []
                print("RESTORED: isMiniaturized=\(source.isMiniaturized); records=\(restoredRecords.count); onScreen=\(String(describing: restoredRecords.first?[kCGWindowIsOnscreen as String]))")
                let resumed = try await WindowPreviewPlugin.capture(window)
                print("RESTORED: capture resumed; size=\(resumed.width)x\(resumed.height)")
                source.close()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let closedAllCG = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                print("CLOSED: CG-allContainsTarget=\(closedAllCG.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.windowID }))")
                do {
                    _ = try await WindowPreviewPlugin.capture(window)
                    throw Failure.message("Closed source was captured as live")
                } catch is PreviewPaused {
                    print("CLOSED RETAINED: system still lists window; paused, not falsely shown live; manual close remains available")
                } catch Failure.message(let message) where message.contains("源窗口已关闭") {
                    print("CLOSED REMOVED: source rejected and capture stopped")
                }
                cover.close(); exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)"); source.close(); cover.close(); exit(1)
            }
        }
        NSApp.run()
    }
}
SWIFT
swiftc -target "$(uname -m)-apple-macosx13.0" -parse-as-library "$TMP"/*.swift -o "$TMP/check"
"$TMP/check"
