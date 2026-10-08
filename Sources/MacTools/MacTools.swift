import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    #if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
    let model = AppModel(defaults: CommandLine.arguments.contains("--ice-candidate-ui-smoke")
        ? UserDefaults(suiteName:"com.ryanai.mactools.ice-ui-smoke")! : .standard)
    #else
    let model = AppModel()
    #endif
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.toggleWindow = { [weak self] in self?.toggleWindow() }
        model.showToolbox = { [weak self] in guard let self else { return }; self.showWindow(model: self.model) }
        model.start()
        showWindow(model: model)
        #if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
        if CommandLine.arguments.contains("--ice-candidate-ui-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in
                guard let self else { exit(1) }
                let imageURL = URL(fileURLWithPath:"/tmp/mac-tools-ice-product-ui.png")
                var rendered = false
                if let content = self.window?.contentView,
                   let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds) {
                    content.cacheDisplay(in:content.bounds,to:bitmap)
                    if let bytes = bitmap.representation(using:.png,properties:[:]) {
                        do { try bytes.write(to:imageURL,options:.atomic); rendered = bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0 }
                        catch { rendered = false }
                    }
                }
                let valid = self.window?.isVisible == true && self.model.selectedPluginID == MenuBarOrganizerPlugin.id && rendered
                let value: [String:Any] = ["uiRenderPassed":valid,"windowTitle":self.window?.title ?? "", "imagePath":imageURL.path,
                    "selectedPlugin":self.model.selectedPluginID ?? "", "registeredPluginCount":self.model.plugins.plugins.count,
                    "semanticAXReadbackClaimed":false,"ownedSessionsStarted":0,"mousePosts":0,"permissionRequests":0]
                if let data = try? JSONSerialization.data(withJSONObject:value, options:[.sortedKeys]) { print(String(decoding:data,as:UTF8.self)) }
                if valid { NSApp.terminate(nil) } else { exit(1) }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func toggleWindow() {
        if let window, window.isVisible && !window.isMiniaturized && NSApp.isActive { model.plugins.toolboxWillClose(); window.orderOut(nil) }
        else { showWindow(model: model) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(model: model)
        return true
    }
    func windowWillClose(_ notification: Notification) { model.plugins.toolboxWillClose() }

    func showWindow(model: AppModel) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            #if ICE_MENU_BAR_CANDIDATE
            panel.title = "MacTools · Ice 候选"
            #else
            panel.title = "Mac 工具箱"
            #endif
            panel.contentMinSize = NSSize(width: 900, height: 640)
            panel.contentView = NSHostingView(rootView: ContentView(model: model))
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center()
            window = panel
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        #if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
        if CommandLine.arguments.contains("--ice-candidate-directory") {
            do {
                let directory = try MenuBarIceSelectedTarget.readDirectory()
                let value: [String:Any] = ["display":directory.display,"space":directory.space,
                    "rows":directory.rows.map { ["windowID":$0.id,"pid":$0.pid,"title":$0.title,
                        "frame":["x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height]] as [String:Any] },
                    "readOnly":true,"mousePosts":0,"permissionRequests":0,"ordinaryMovementEnabled":false]
                let data = try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])
                print(String(decoding:data,as:UTF8.self)); exit(0)
            } catch { fputs("Ice directory read failed: \(error)\n",stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--ice-candidate-preflight") {
            do {
                let proof = try MenuBarIceCandidateProductBridge.preflight()
                let data = try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self)); exit(0)
            } catch { fputs("Ice candidate preflight failed: \(error)\n", stderr); exit(1) }
        }
        #endif
        #if !ICE_MENU_BAR_CANDIDATE
        if !CommandLine.arguments.contains("--ice-candidate-ui-smoke") { MenuBarOrganizerPlugin.prepareMainStatusPosition() }
        #endif
    }

    var body: some Scene {
        MenuBarExtra("Mac 工具箱", systemImage: "slider.horizontal.3") { MenuContent(model: delegate.model, showWindow: { delegate.showWindow(model: delegate.model) }) }
    }
}
