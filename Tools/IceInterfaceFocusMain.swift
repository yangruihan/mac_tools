// Copyright (c) 2026 Ryan.AI. MIT. A second owned app supplies real focus change, no input.
import AppKit
@main struct IceInterfaceFocusMain {
 @MainActor static func main(){
  guard CommandLine.arguments.count==3,UUID(uuidString:CommandLine.arguments[1]) != nil else{exit(2)}
  let file=URL(fileURLWithPath:CommandLine.arguments[2]);guard file.path.hasPrefix("/tmp/ice-interface-focus-") else{exit(2)}
  let app=NSApplication.shared;app.setActivationPolicy(.regular)
  let w=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:150),styleMask:[.titled],backing:.buffered,defer:false)
  w.title="MacTools 自建失焦验证窗口";w.center();app.finishLaunching();w.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
  let timer=Timer(timeInterval:0.1,repeats:true){_ in MainActor.assumeIsolated {
   let r:[String:Any]=["nonce":CommandLine.arguments[1],"pid":ProcessInfo.processInfo.processIdentifier,"active":app.isActive,"visible":w.isVisible,"atUnix":Date().timeIntervalSince1970,"nativePosts":0]
   try? JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]).write(to:file,options:.atomic)
  }};RunLoop.main.add(timer,forMode:.common)
  let end=Timer(timeInterval:8,repeats:false){_ in MainActor.assumeIsolated{app.terminate(nil)}};RunLoop.main.add(end,forMode:.common)
  withExtendedLifetime(w){app.run()}
 }
}
