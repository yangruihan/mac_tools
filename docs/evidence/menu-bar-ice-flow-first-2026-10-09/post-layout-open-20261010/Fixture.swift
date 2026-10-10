// Own status items for zero-input ordinary product-entry regression.
import AppKit

@MainActor final class IceProductTargetDirectoryFixture: NSObject, NSApplicationDelegate {
    let nonce: String, output: URL
    var items: [NSStatusItem] = [], timer: Timer?
    var windows:[String:NSWindow]=[:], nativeClicks:[String:Int]=[:], preparedWindows=0
    let deadline = ProcessInfo.processInfo.systemUptime + 1200
    init(_ nonce: String, _ output: URL) { self.nonce = nonce; self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for title in ["T", "N"] {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = title; item.button?.toolTip = "MacTools 产品入口自建 " + title
            item.button?.target=self; item.button?.action=#selector(openNative(_:)); item.button?.sendAction(on:.leftMouseUp)
            items.append(item)
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer!, forMode: .common)
    }
    @objc func openNative(_ sender:NSStatusBarButton) {
        let title=sender.title;guard title=="N" || title=="T" else{return}
        nativeClicks[title,default:0]+=1;showOwned(title)
    }
    func showOwned(_ title:String) {
        if windows[title]==nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:380,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title="自建 "+title+" · 整理后打开回归";window.isReleasedWhenClosed=false
            let text=NSTextField(labelWithString:"仅自建图标的普通窗口\n关闭窗口或切回验收窗口后，等待约15秒归位。")
            text.frame=NSRect(x:24,y:70,width:330,height:80);window.contentView?.addSubview(text);window.center();windows[title]=window
        }
        windows[title]?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func tick() {
        let prepare=output.appendingPathExtension("open-N")
        if FileManager.default.fileExists(atPath:prepare.path){try? FileManager.default.removeItem(at:prepare);preparedWindows+=1;showOwned("N")}

        let rows = items.enumerated().compactMap { index, item -> [String: Any]? in
            guard let number = item.button?.window?.windowNumber, number > 0 else { return nil }
            return ["title": index == 0 ? "T" : "N", "windowID": number]
        }
        if rows.count == 2, let bytes = try? JSONSerialization.data(withJSONObject: ["nonce": nonce, "pid": ProcessInfo.processInfo.processIdentifier, "atUnix": Date().timeIntervalSince1970, "items": rows,"nativeClicks":nativeClicks,"preparedWindows":preparedWindows,"ownerActive":NSApp.isActive,"ordinaryWindows":windows.map{["title":$0.key,"windowID":$0.value.windowNumber,"visible":$0.value.isVisible,"key":$0.value.isKeyWindow]}]) {
            try? bytes.write(to: output, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        }
        if FileManager.default.fileExists(atPath: output.appendingPathExtension("quit").path) || ProcessInfo.processInfo.systemUptime >= deadline {
            items.forEach { NSStatusBar.system.removeStatusItem($0) }; items = []; timer?.invalidate(); NSApp.terminate(nil)
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
