import AppKit
import Foundation
import CoreGraphics
let pid: Int32 = 12446
let rows = (CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? [])
let owned = rows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
let windows: [[String:Any]] = owned.map { row in
    ["id":(row[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0,
     "level":(row[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1,
     "onScreen":row[kCGWindowIsOnscreen as String] as? Bool ?? false]
}
let value: [String:Any] = ["hostPID":pid,"ownerActive":NSRunningApplication(processIdentifier:pid)?.isActive ?? false,
"frontPID":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,"windows":windows,"atUnix":Date().timeIntervalSince1970,"nativePosts":0]
print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self))
