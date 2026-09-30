import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.toggleWindow = { [weak self] in self?.toggleWindow() }
        model.showToolbox = { [weak self] in guard let self else { return }; self.showWindow(model: self.model) }
        model.start()
        showWindow(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func toggleWindow() {
        if let window, window.isVisible && !window.isMiniaturized && NSApp.isActive { window.orderOut(nil) }
        else { showWindow(model: model) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(model: model)
        return true
    }

    func showWindow(model: AppModel) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Mac 工具箱"
            panel.contentMinSize = NSSize(width: 900, height: 640)
            panel.contentView = NSHostingView(rootView: ContentView(model: model))
            panel.isReleasedWhenClosed = false
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

    init() { MenuBarOrganizerPlugin.prepareMainStatusPosition() }

    var body: some Scene {
        MenuBarExtra("Mac 工具箱", systemImage: "slider.horizontal.3") { MenuContent(model: delegate.model, showWindow: { delegate.showWindow(model: delegate.model) }) }
    }
}
