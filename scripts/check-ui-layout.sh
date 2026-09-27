#!/bin/sh
# Native view-layout regression probe; no windows shown, no hardware writes.
set -eu
SOURCE=${1:-Sources/MacTools}
TMP=$(mktemp -d)
python3 - "$SOURCE" "$TMP/Source.swift" <<'PY'
import pathlib, sys, os, re
source = pathlib.Path(sys.argv[1])
if source.is_file() and source.name == 'MacTools.swift' and (source.parent / 'AppModel.swift').exists():
    source = source.parent
files = sorted(source.rglob('*.swift')) if source.is_dir() else [source]
contents = [p.read_text() for p in files]
s = '\n'.join(contents)
custom = bool(re.search(r'\.(?:blue|orange|teal|white|black|gradient)\b', s))
print('custom-decorative-palette=' + str(custom), flush=True)
print('manual-appearance-selection=' + str('enum AppearanceMode:' in s), flush=True)
plugin_host = 'protocol ToolPlugin:' in s
print('plugin-host=' + str(plugin_host), flush=True)
print('window-preview-plugin=' + str('final class WindowPreviewPlugin:' in s), flush=True)
print('menu-bar-organizer-plugin=' + str('final class MenuBarOrganizerPlugin:' in s), flush=True)
print('preview-auto-resume=' + str('struct PreviewPaused:' in s and 'self.isPaused = true' in s), flush=True)
if os.environ.get('EXPECT_NATIVE') == '1':
    assert not custom and '.preferredColorScheme' not in s
    assert '.tint(' not in s and 'GroupBox {' in s
for i, content in enumerate(contents):
    (pathlib.Path(sys.argv[2]).parent / f'Source{i}.swift').write_text(content.replace('@main\nstruct MacToolsApp', 'struct MacToolsApp'))
if plugin_host: (pathlib.Path(sys.argv[2]).parent / 'plugin-host').touch()
PY
cat > "$TMP/Probe.swift" <<'SWIFT'
import SwiftUI
import AppKit

@main
struct Probe {
    static func main() {
        _ = NSApplication.shared
        let appearance: NSAppearance.Name = ProcessInfo.processInfo.environment["UI_DARK"] == "1" ? .darkAqua : .aqua
        NSApp.appearance = NSAppearance(named: appearance)
        let suite = "MacToolsLayoutCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try! JSONEncoder().encode(Preset(key: "")), forKey: "windowShortcut")
        let presets = (0..<8).map { Preset(name: "布局测试 \($0 + 1)", audio: $0 >= 4, value: 15) }
        #if PLUGIN_HOST
        defaults.set(try! JSONEncoder().encode(presets), forKey: "presets")
        let model = AppModel(defaults: defaults)
        model.start()
        defer { model.stop() }
        let root = ContentView(model: model)
        #else
        let store = Store(defaults: defaults)
        store.presets = presets
        let root = ContentView(store: store)
        #endif
        NSApp.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
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
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: name)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let actual = window.contentView!.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            precondition(actual == name, "View did not follow application appearance")
            var background: CGFloat = 0
            window.contentView!.effectiveAppearance.performAsCurrentDrawingAppearance {
                background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!.redComponent
            }
            print("appearance=\(name.rawValue); window-background-red=\(String(format: "%.3f", Double(background)))")
        }
        print("hardware-writes=0; live-user-defaults=untouched")
    }
}
SWIFT
FLAG=""
if [ -f "$TMP/plugin-host" ]; then FLAG="-DPLUGIN_HOST"; fi
swiftc $FLAG -target "$(uname -m)-apple-macosx13.0" -parse-as-library "$TMP"/Source*.swift "$TMP/Probe.swift" -o "$TMP/check"
"$TMP/check"
