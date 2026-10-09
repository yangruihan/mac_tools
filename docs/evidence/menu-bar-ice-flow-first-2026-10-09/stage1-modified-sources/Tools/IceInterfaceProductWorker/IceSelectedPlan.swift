// Copyright (c) 2026 Ryan.AI. MIT. Single-screen exact-window ordinary target plan.
import AppKit
import Security
import Darwin

/// Capture full signature/file hash at stage boundaries; hot route checks use
/// the actual guest's CodeDirectory digest, kernel launch/path and exact window
/// owner. No expensive whole-app hashing is inserted inside Ice's 50ms routes.
@MainActor final class IceSelectedRuntime {
    let processes: [IceSelectedBinding.Process]
    init(_ values: [IceSelectedBinding.Process]) throws {
        processes = Array(Dictionary(grouping:values,by:\.pid).values.compactMap { group in
            group.allSatisfy({$0 == group[0]}) ? group[0] : nil
        })
        guard processes.count == Set(values.map(\.pid)).count else { throw IceSelectedFailure.binding }
        try checkFullSignatures()
    }
    func check() throws {
        // Signatures are checked at phase boundaries; the hot route only rejects PID reuse/path changes.
        for p in processes {
            var bsd = proc_bsdinfo(), bytes = [CChar](repeating:0,count:Int(MAXPATHLEN)*4)
            guard proc_pidinfo(p.pid,PROC_PIDTBSDINFO,0,&bsd,Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  Double(bsd.pbi_start_tvsec)+Double(bsd.pbi_start_tvusec)/1_000_000 == p.launch,
                  bytes.withUnsafeMutableBytes({proc_pidpath(p.pid,$0.baseAddress,UInt32($0.count))}) > 0,
                  URL(fileURLWithPath:String(cString:bytes)).resolvingSymlinksInPath().path == p.executable else { throw IceSelectedFailure.binding }
        }
    }
    func checkFullSignatures() throws {
        for p in processes { guard try IceSelectedBinding.Process(MenuBarProcessSignature.read(p.pid)) == p else { throw IceSelectedFailure.binding } }
        try check()
    }
}

@MainActor final class IceSelectedPlan {
    let selected: MenuBarIceSelectedTarget, binding: IceSelectedBinding, runtime: IceSelectedRuntime
    let windows: IceBaselineWindows
    let originalPeers: [[String:Any]]
    let relative:IceSelectedLiveRelative?
    let relativeRuntime:IceSelectedRuntime?
    init(selected: MenuBarIceSelectedTarget, anchorID: UInt32, windows: IceBaselineWindows, quick:Bool = false, diagnostics: @escaping (String,[String:Any])->Void = {_,_ in}) throws {
        diagnostics("scope",["selected":try JSONSerialization.jsonObject(with:JSONEncoder().encode(selected)),"anchorID":anchorID,"screens":NSScreen.screens.map{["frame":NSStringFromRect($0.frame),"right":$0.auxiliaryTopRightArea.map(NSStringFromRect) as Any? ?? NSNull()]}])
        guard NSScreen.screens.count == 1, let screen = NSScreen.screens.first,
              let right = screen.auxiliaryTopRightArea,
              let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              display == selected.display, windows.activeSpace(windows.connection()) == UInt(selected.space) else { throw IceSelectedFailure.binding }
        _ = try selected.validate(directory:MenuBarIceSelectedTarget.readDirectory(),owner:MenuBarProcessSignature.read(selected.owner.pid))
        let own = try IceSelectedBinding.Process(MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier))
        let directory = try IceMenuBarReadAdapter.isolatedReadOnly().read()
        let publicRows = IceBaselineWindows.rows()
        diagnostics("directory",["members":directory.members.map{["id":$0.windowID,"frame":NSStringFromRect($0.frame),"spaces":$0.spaces]},"publicRows":publicRows])
        let byID = Dictionary(grouping:publicRows,by:{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0})
        func item(_ id: UInt32) throws -> IceSelectedBinding.Item {
            guard let rows = byID[id], rows.count == 1, let row = rows.first,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let member = directory.members.first(where:{$0.windowID == id}), member.spaces.contains(selected.space) else { throw IceSelectedFailure.binding }
            let process = try IceSelectedBinding.Process(MenuBarProcessSignature.read(pid))
            let frame = try windows.frame(.init(windowID:id,pid:pid,key:"selected"))
            guard frame == member.frame else { throw IceSelectedFailure.binding }
            return .init(id:id,process:process,frame:.init(frame))
        }
        let target = try item(selected.windowID), anchor = try item(anchorID)
        diagnostics("items",["target":try JSONSerialization.jsonObject(with:JSONEncoder().encode(target)),"anchor":try JSONSerialization.jsonObject(with:JSONEncoder().encode(anchor))])
        guard target.frame.cg == selected.originalFrame, anchor.process == own else { throw IceSelectedFailure.binding }
        let neighbors = directory.members.filter { $0.windowID != selected.windowID && $0.windowID != anchorID &&
            $0.spaces.contains(selected.space) && $0.frame.minY == target.frame.y && $0.frame.height == target.frame.height &&
            $0.frame.width > 8 && $0.frame.width < 150 &&
            ($0.frame.minX == target.frame.cg.maxX || $0.frame.maxX == target.frame.x) }
        // Prefer the exact adjacent right item; with one neighbor on each side
        // this is still one deterministic return edge, not enumeration order.
        let rightNeighbors = neighbors.filter{$0.frame.minX == target.frame.cg.maxX}
        let chosen = rightNeighbors.isEmpty ? neighbors.filter{$0.frame.maxX == target.frame.x} : rightNeighbors
        diagnostics("neighbors",["candidates":chosen.map{["id":$0.windowID,"frame":NSStringFromRect($0.frame)]},"returnOnLeft":!rightNeighbors.isEmpty])
        guard chosen.count == 1, let neighbor = chosen.first else { throw IceSelectedFailure.binding }
        let neighborItem = try item(neighbor.windowID)
        let area = CGRect(x:right.minX,y:anchor.frame.y,width:right.width,height:anchor.frame.height)
        binding = .init(nonce:selected.nonce,controller:own,owner:try .init(selected.owner),display:display,space:UInt(selected.space),area:.init(area),
                        target:target,neighbor:neighborItem,anchor:anchor,returnOnLeft:!rightNeighbors.isEmpty)
        diagnostics("binding",["binding":try JSONSerialization.jsonObject(with:JSONEncoder().encode(binding))])
        try binding.validate()
        self.selected = selected; self.windows = windows
        diagnostics("runtime",["next":"hotGuestCapture"])
        let liveRelative = quick ? nil : try IceSelectedLiveRelative(binding:binding,windows:windows,diagnostics:diagnostics)
        relative = liveRelative
        runtime = try IceSelectedRuntime([own,binding.owner,neighborItem.process])
        if let liveRelative {relativeRuntime = try IceSelectedRuntime([own,binding.owner,neighborItem.process]+liveRelative.protectedProcesses)} else {relativeRuntime = nil}
        originalPeers = Self.peerFacts(publicRows)
        diagnostics("runtime-check",["next":"fullSignaturesAndPublicWindowOwnership"])
        try runtime.checkFullSignatures();try verifyRuntime()
        diagnostics("complete",["verified":true])
    }
    private static func peerFacts(_ rows: [[String:Any]]) -> [[String:Any]] {
        rows.map { ["id":$0[kCGWindowNumber as String] ?? 0,"pid":$0[kCGWindowOwnerPID as String] ?? 0,
                    "bounds":$0[kCGWindowBounds as String] ?? [:]] }.sorted {
            ($0["id"] as! NSNumber).uint32Value < ($1["id"] as! NSNumber).uint32Value
        }
    }
    func verifyRuntime() throws { _ = try verifiedRuntimeScope() }
    func verifiedRuntimeScope() throws -> (UInt32,UInt) {
        try runtime.check()
        // This public C API takes raw CGWindowID values, not CFNumber objects.
        // Foundation bridging [UInt32] as CFArray produces an empty description.
        var rawIDs=[binding.target.id,binding.neighbor.id,binding.anchor.id].map {UnsafeRawPointer(bitPattern:UInt($0))}
        let ids=rawIDs.withUnsafeMutableBufferPointer {CFArrayCreate(kCFAllocatorDefault,$0.baseAddress,$0.count,nil)!}
        let display = NSScreen.screens.count == 1 ? (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 : 0
        let space = windows.activeSpace(windows.connection())
        guard display == binding.display, space == binding.space,
              let rows = CGWindowListCreateDescriptionFromArray(ids) as? [[String:Any]], rows.count == 3 else { throw IceSelectedFailure.binding }
        guard validateWindowOwnership(rows) else { throw IceSelectedFailure.binding }
        return (display,space)
    }
    func validateWindowOwnership(_ rows:[[String:Any]]) -> Bool {
        Self.windowOwnershipMatches(rows,items:[binding.target,binding.neighbor,binding.anchor])
    }
    static func windowOwnershipMatches(_ rows:[[String:Any]],items:[IceSelectedBinding.Item]) -> Bool {
        items.allSatisfy { item in
            rows.filter { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == item.id &&
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == item.process.pid &&
                ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.statusWindow)) }.count == 1
        }
    }
    func finalRuntimeScope() throws -> (UInt32,UInt) {
        // The immediately preceding occupancy query has rechecked all three
        // bound window owners. Recheck live guest signatures/launch/path and
        // current Space here without another window-description IPC.
        try runtime.check()
        let value=scope()
        guard value.0==binding.display,value.1==binding.space else { throw IceSelectedFailure.binding }
        return value
    }
    func scope() -> (UInt32,UInt) {
        let display = NSScreen.screens.count == 1 ? (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 : 0
        return (display,windows.activeSpace(windows.connection()))
    }
    func item(_ value: IceSelectedBinding.Item) -> IceBaselineItem { .init(windowID:value.id,pid:value.process.pid,key:"exact-window") }
    func verifyVisible() throws {
        try runtime.checkFullSignatures();try verifyRuntime()
        let frame = try windows.frame(item(binding.target))
        guard binding.area.cg.contains(frame), frame.width == binding.target.frame.width,
              frame.height == binding.target.frame.height,
              frame.maxX == (try windows.frame(item(binding.anchor))).minX else { throw IceBaselineError.geometry }
    }
    // Same positional completion as Ice's correct(item, destination): the
    // selected item is directly beside its original neighbor on the same side.
    // Full queue/absolute geometry are diagnostics in this quick contract.
    static func quickPosition(_ target:CGRect,_ neighbor:CGRect,onLeft:Bool)->Bool {
        target.minY == neighbor.minY && target.height == neighbor.height &&
        (onLeft ? target.maxX == neighbor.minX : target.minX == neighbor.maxX)
    }
    func quickReturnedSample() throws -> Data {
        try runtime.checkFullSignatures();try verifyRuntime()
        let target=try windows.frame(item(binding.target)),neighbor=try windows.frame(item(binding.neighbor))
        guard Self.quickPosition(target,neighbor,onLeft:binding.returnOnLeft) else {throw IceBaselineError.geometry}
        return try JSONSerialization.data(withJSONObject:["criterion":"iceNeighborEdgeV4","nonce":binding.nonce.uuidString,
            "targetID":binding.target.id,"targetPID":binding.owner.pid,"neighborID":binding.neighbor.id,
            "targetFrame":NSStringFromRect(target),"neighborFrame":NSStringFromRect(neighbor),"returnOnLeft":binding.returnOnLeft,
            "atUptime":ProcessInfo.processInfo.systemUptime,"fullQueueRequired":false,"relativeFullQueueVerified":false],options:[.sortedKeys])
    }
    func returnedSample() throws -> Data {
        try runtime.checkFullSignatures();try verifyRuntime()
        for i in [binding.target,binding.neighbor,binding.anchor] {
            guard try windows.frame(item(i)) == i.frame.cg else { throw IceBaselineError.geometry }
        }
        let peers = Self.peerFacts(IceBaselineWindows.rows())
        guard NSArray(array:peers).isEqual(to:originalPeers) else { throw IceBaselineError.geometry }
        return try JSONSerialization.data(withJSONObject:["nonce":binding.nonce.uuidString,"display":binding.display,"space":binding.space,
            "targetID":binding.target.id,"targetPID":binding.owner.pid,"peerFacts":peers,"atUptime":ProcessInfo.processInfo.systemUptime],options:[.sortedKeys])
    }
}
