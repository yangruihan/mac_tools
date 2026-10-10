// Own status items for zero-input ordinary product-entry regression.
import AppKit

@MainActor final class IceProductTargetDirectoryFixture: NSObject, NSApplicationDelegate {
    let nonce: String, output: URL
    var items: [NSStatusItem] = [], timer: Timer?
    let deadline = ProcessInfo.processInfo.systemUptime + 1200
    init(_ nonce: String, _ output: URL) { self.nonce = nonce; self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for title in ["T", "N", "R"] {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName="persist_163bd897-c052-479e-b969-109bd2d1dbbb_"+title
            item.button?.title = title; item.button?.toolTip = "MacTools 产品入口自建 " + title
            let menu = NSMenu(title: title); menu.addItem(NSMenuItem(title: "自建入口目标", action: nil, keyEquivalent: "")); item.menu = menu
            items.append(item)
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func tick() {
        let rows = items.enumerated().compactMap { index, item -> [String: Any]? in
            guard let number = item.button?.window?.windowNumber, number > 0 else { return nil }
            return ["title": item.button?.title ?? "?", "windowID": number]
        }
        if rows.count == 3, let bytes = try? JSONSerialization.data(withJSONObject: ["nonce": nonce, "pid": ProcessInfo.processInfo.processIdentifier, "atUnix": Date().timeIntervalSince1970, "items": rows,"savedPositions":Dictionary(uniqueKeysWithValues:items.map{let name=$0.autosaveName!;return(name,UserDefaults.standard.object(forKey:"NSStatusItem Preferred Position "+name) ?? "missing")})]) {
            try? bytes.write(to: output, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        }
        if FileManager.default.fileExists(atPath: output.appendingPathExtension("quit").path) || ProcessInfo.processInfo.systemUptime >= deadline {
            timer?.invalidate(); _ = UserDefaults.standard.synchronize(); NSApp.terminate(nil)
        }
    }
}
@main struct IceProductTargetDirectoryFixtureMain {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3, UUID(uuidString: CommandLine.arguments[1]) != nil else { exit(1) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = IceProductTargetDirectoryFixture(CommandLine.arguments[1], URL(fileURLWithPath: CommandLine.arguments[2]))
        app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
    }
}
