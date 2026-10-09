import AppKit
@main struct Measure {
 @MainActor static func main() throws {
  let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
  let window=NSWindow(contentRect:NSRect(x:200,y:200,width:240,height:90),styleMask:[.titled],backing:.buffered,defer:false);window.title="MacTools 自建查询回归";window.isReleasedWhenClosed=false;window.orderFront(nil)
  defer {window.orderOut(nil);window.close()}
  CFRunLoopRunInMode(.defaultMode,0.15,false)
  let ids:[NSNumber]=[351689,354357,NSNumber(value:window.windowNumber)];let keys:[CFString]=[kCGWindowNumber,kCGWindowOwnerPID,kCGWindowLayer,kCGWindowIsOnscreen,kCGWindowBounds]
  var rawIDs=ids.map {UnsafeRawPointer(bitPattern:UInt($0.uint32Value))}
  let raw=rawIDs.withUnsafeMutableBufferPointer {CFArrayCreate(kCFAllocatorDefault,$0.baseAddress,$0.count,nil)!}
  var full:[Double]=[],targeted:[Double]=[];var equal=true
  for _ in 0..<20 {
   var start=ProcessInfo.processInfo.systemUptime
   guard let all=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else{exit(1)}
   
   let selected=all.filter {ids.contains(($0[kCGWindowNumber as String] as? NSNumber) ?? -1)};full.append((ProcessInfo.processInfo.systemUptime-start)*1000)
   start=ProcessInfo.processInfo.systemUptime
   guard let subset=CGWindowListCreateDescriptionFromArray(raw) as? [[String:Any]] else{exit(1)};targeted.append((ProcessInfo.processInfo.systemUptime-start)*1000)
   for id in ids {
    guard let a=selected.first(where:{$0[kCGWindowNumber as String] as? NSNumber==id}),let b=subset.first(where:{$0[kCGWindowNumber as String] as? NSNumber==id}) else{fputs("missing selected window \(id)\n",stderr);exit(1)}
    for key in keys { let same=(a[key as String]==nil && b[key as String]==nil) || ((a[key as String] as AnyObject?)?.isEqual(b[key as String]) ?? false); if !same {fputs("unequal \(id) key \(key) full=\(String(describing:a[key as String])) selected=\(String(describing:b[key as String]))\n",stderr)}; equal = equal && same }
   }
  }
  guard equal else{exit(1)}
  let result:[String:Any]=["samples":20,"metadataFieldsEqual":equal,"fields":keys,"allWindowQueryMS":full,"selectedWindowQueryMS":targeted,"fullMeanMS":full.reduce(0,+)/20,"targetedMeanMS":targeted.reduce(0,+)/20,"nativePosts":0,"permissionRequests":0]
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
