import AppKit
import SwiftUI
import CoreGraphics

enum BoundaryScope {
    static let defaults=UserDefaults(suiteName:"boundary.e399d099-344b-4816-9980-f52e6d5c1fec")!
    static var fixturePID:Int32=0
    static var ids:Set<UInt32>=[]
    static var output=URL(fileURLWithPath:"/Users/yangruihan/Documents/MacTools边界验收/2026-10-10-first-slot-e399d099-344b-4816-9980-f52e6d5c1fec/state.json")
    static func record(_ value:[String:Any]) {
        var value=value;value["atUnix"]=Date().timeIntervalSince1970
        guard let data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else{return}
        let url=output.appendingPathExtension("events.jsonl")
        if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
        if let f=try? FileHandle(forWritingTo:url){try? f.seekToEnd();try? f.write(contentsOf:data+Data([10]));try? f.close()}
    }
}
struct BoundaryView:View {
    @ObservedObject var plugin:MenuBarOrganizerPlugin
    var body:some View {VStack(alignment:.leading,spacing:12){
        Text("仅自建 N / T / R · 重启持久性验收").font(.headline)
        Text(plugin.status).font(.caption)
        if plugin.isOrganizing {
            Button("打开自建图标面板"){plugin.openShelf()}
            Button("保存面板偏好与兼容值7"){plugin.setPresentationMode(.panel);plugin.setVisibleLimit(7)}
            Button("停用自建收纳"){plugin.turnOff()}
        } else {Button("启用自建收纳"){plugin.enable()}}
    }.padding(20).frame(width:420)}
}
@MainActor final class BoundaryDelegate:NSObject,NSApplicationDelegate {
    var plugin:MenuBarOrganizerPlugin!;var window:NSWindow!;var timer:Timer?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let context=PluginContext(settings:PluginSettings(id:MenuBarOrganizerPlugin.id,defaults:BoundaryScope.defaults),hotkeys:HotKeyService(),report:{_ in})
        plugin=MenuBarOrganizerPlugin(context:context);plugin.start();plugin.enable()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:460,height:230),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="菜单栏持久性验收 · 仅自建图标";window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:BoundaryView(plugin:plugin));window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        timer=Timer(timeInterval:0.2,repeats:true){[weak self] _ in MainActor.assumeIsolated{self?.tick()}};RunLoop.main.add(timer!,forMode:.common)
    }
    func tick() {
        if plugin.isCollapsed && !plugin.isCapturing {
            if plugin.icons.isEmpty && plugin.visibleIcons.isEmpty { if !window.isVisible { window.makeKeyAndOrderFront(nil) } }
            else { if window.isVisible { window.orderOut(nil) } }
        }
        var v=plugin.boundaryState();v["pid"]=Int(ProcessInfo.processInfo.processIdentifier);v["atUnix"]=Date().timeIntervalSince1970
        let rows=(CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []).filter{($0[kCGWindowLayer as String] as? Int)==Int(CGWindowLevelForKey(.statusWindow))}
        v["windows"]=rows
        v["savedSettings"]=["optedIn":BoundaryScope.defaults.data(forKey:"plugin.menu-bar-organizer.optedIn").map{String(decoding:$0,as:UTF8.self)} ?? "missing","presentationMode":BoundaryScope.defaults.data(forKey:"plugin.menu-bar-organizer.presentationMode").map{String(decoding:$0,as:UTF8.self)} ?? "missing","visibleLimit":BoundaryScope.defaults.data(forKey:"plugin.menu-bar-organizer.visibleLimit").map{String(decoding:$0,as:UTF8.self)} ?? "missing"]
        if let data=try? JSONSerialization.data(withJSONObject:v,options:[.sortedKeys]){try? data.write(to:BoundaryScope.output,options:.atomic)}
        if FileManager.default.fileExists(atPath:BoundaryScope.output.appendingPathExtension("quit").path){NSApp.terminate(nil)}
    }
    func applicationWillTerminate(_ notification:Notification){plugin.stop();timer?.invalidate()}
}
@main struct BoundaryMain {
    @MainActor static func main() {
        guard CommandLine.arguments.count==2,let data=try? Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),let config=try? JSONSerialization.jsonObject(with:data) as? [String:Any],config["nonce"] as? String=="e399d099-344b-4816-9980-f52e6d5c1fec",let fixture=config["pid"] as? Int,let items=config["items"] as? [[String:Any]],items.count==3 else{exit(2)}
        BoundaryScope.fixturePID=Int32(fixture);BoundaryScope.ids=Set(items.compactMap{($0["windowID"] as? NSNumber)?.uint32Value});guard BoundaryScope.ids.count==3 else{exit(2)}
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);let delegate=BoundaryDelegate();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}
    }
}
