#!/bin/sh
# Native view-layout regression probe; no windows shown, no hardware writes.
set -eu
SOURCE=${1:-Sources/MacTools/MacTools.swift}
TMP=$(mktemp -d)
python3 - "$SOURCE" "$TMP/Source.swift" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(s.replace('@main\nstruct MacToolsApp', 'struct MacToolsApp'))
PY
cat > "$TMP/Probe.swift" <<'SWIFT'
import SwiftUI
import AppKit

@main
struct Probe {
    static func main() {
        _ = NSApplication.shared
        if ProcessInfo.processInfo.environment["UI_DARK"] == "1" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let suite = "MacToolsLayoutCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try! JSONEncoder().encode(Preset(key: "")), forKey: "windowShortcut")
        let store = Store(defaults: defaults)
        store.presets = (0..<8).map { Preset(name: "布局测试 \($0 + 1)", audio: $0 >= 4, value: 15) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        for size in [NSSize(width: 980, height: 740), NSSize(width: 900, height: 640)] {
            window.setContentSize(size)
            window.contentView!.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            window.contentView!.layoutSubtreeIfNeeded()
            func scrolls(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
            }
            let lists = scrolls(window.contentView!).filter { $0.frame.width > 400 }
            guard let list = lists.max(by: { $0.frame.height < $1.frame.height }) else { fatalError("No preset scroll view") }
            print("window=\(Int(size.width))x\(Int(size.height)); list=\(Int(list.frame.width))x\(Int(list.frame.height)); height-share=\(Int(100 * list.frame.height / size.height))%")
            if ProcessInfo.processInfo.environment["EXPECT_MODERN"] == "1" {
                precondition(list.frame.height >= 350, "Preset viewport too small")
                precondition(list.frame.height / size.height >= 0.58, "Too much fixed chrome")
            }
        }
        print("hardware-writes=0; live-user-defaults=untouched")
    }
}
SWIFT
swiftc -target "$(uname -m)-apple-macosx13.0" -parse-as-library "$TMP/Source.swift" "$TMP/Probe.swift" -o "$TMP/check"
"$TMP/check"
