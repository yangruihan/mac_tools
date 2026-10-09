// Copyright (c) 2026 Ryan.AI. MIT. State and cancellation counterexamples; no live inputs.
import AppKit
@MainActor enum IceInterfaceChecks {
    enum Failure:Error {case assertion(String)}
    static var assertions=0,scenarios=0
    static func check(_ ok:Bool,_ text:String)throws {assertions+=1;guard ok else{throw Failure.assertion(text)}}
    static func run()async throws->(Int,Int) {
        assertions=0;scenarios=0
        let b=try IceSelectedOfflineChecks.binding()
        typealias W=IceSelectedInterfaceLease.Window
        for name in ["hidden","defocused","popupClosed","custom102","noInterface","foreign","multiple","rebuilt","ownerChanged","levelChanged","unhealthy","spaceChanged","stale","reactivated"] {
            scenarios+=1;var now=100.0,seq=0
            let lease=IceSelectedInterfaceLease(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,clock:{now})
            let status=W(id:1,pid:b.owner.pid,level:25,onScreen:true)
            func sample(_ windows:[W],active:Bool=true,healthy:Bool=true,space:UInt?=nil)->IceSelectedInterfaceLease.Sample {
                seq+=1;return .init(sequence:seq,at:now,owner:b.owner,nonce:b.nonce,display:b.display,space:space ?? b.space,healthy:healthy,ownerActive:active,windows:[status]+windows)
            }
            try lease.begin(sample([]));now+=0.1
            let level=name=="popupClosed" ? 101 : name=="custom102" ? 102 : 0
            let window=W(id:100,pid:b.owner.pid,level:level,onScreen:true)
            if name=="noInterface" || name=="foreign" {
                let state=lease.observe(sample(name=="foreign" ? [W(id:100,pid:99,level:0,onScreen:true)] : []))
                try check(state == .unknown,"missing/foreign interface stays unknown")
                var refused=false;do{try lease.requireInactive()}catch{refused=true};try check(refused,"unknown cannot admit restoration");continue
            }
            if name=="multiple" {
                try check(lease.observe(sample([window,W(id:101,pid:b.owner.pid,level:0,onScreen:true)])) == .active,"Ice follows first new owner window")
                now+=0.1;try check(lease.observe(sample([])) == .unknown,"one inactive sample waits")
                now+=0.11;try check(lease.observe(sample([])) == .inactive,"first tracked window disappearance admits inactivity");continue
            }
            try check(lease.observe(sample([window])) == .active,"actual tracked interface active")
            now+=0.1
            if name=="rebuilt" {
                try check(lease.observe(sample([W(id:101,pid:b.owner.pid,level:level,onScreen:true)])) == .unknown,"Ice keeps original tracked ID, first disappearance sample waits")
                now+=0.11;try check(lease.observe(sample([])) == .inactive,"missing original tracked window becomes inactive like Ice");continue
            }
            if ["ownerChanged","levelChanged","unhealthy","spaceChanged","stale"].contains(name) {
                let windows=name=="rebuilt" ? [W(id:101,pid:b.owner.pid,level:level,onScreen:true)] : name=="ownerChanged" ? [W(id:100,pid:99,level:level,onScreen:true)] : name=="levelChanged" ? [W(id:100,pid:b.owner.pid,level:42,onScreen:true)] : [window]
                let s=sample(windows,healthy:name != "unhealthy",space:name=="spaceChanged" ? 9 : nil)
                if name=="stale" {now+=0.3}
                try check(lease.observe(s) == .unknown,"invalid/rebuilt interface rejected")
                now+=0.1;try check(lease.observe(sample([])) == .unknown,"invalidity remains sticky");continue
            }
            let inactiveWindows=name=="defocused" ? [window] : [W(id:100,pid:b.owner.pid,level:level,onScreen:false)]
            try check(lease.observe(sample(inactiveWindows,active:name != "defocused")) == .unknown,"one inactive sample insufficient")
            now+=0.11;try check(lease.observe(sample(inactiveWindows,active:name != "defocused")) == .inactive,"two stable samples admit interface inactive")
            let proof=try lease.confirmation()
            try check(proof.kind == (level==101 ? .standardPopup : .ordinaryWindow) && !proof.nativeObservation,"typed proof separates popup and ordinary; replay not native")
            try check(lease.diagnostics()["menuClosedClaimed"] as? Bool==false,"ordinary inactivity never claims menu closed")
            if name=="reactivated" {now+=0.1;try check(lease.observe(sample([window])) == .active,"reopening revokes inactive");var refused=false;do{try lease.requireInactive()}catch{refused=true};try check(refused,"reopening blocks return")}
        }
        for name in ["existingReactivated","stillBackground","ambiguousBackground","changedLevel","changedWindowOwner"] {
            scenarios+=1;var now=100.0,seq=0
            let lease=IceSelectedInterfaceLease(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,clock:{now})
            let original=W(id:200,pid:b.owner.pid,level:0,onScreen:true)
            let second=W(id:201,pid:b.owner.pid,level:0,onScreen:true)
            func sample(_ windows:[W],active:Bool)->IceSelectedInterfaceLease.Sample {
                seq+=1;return .init(sequence:seq,at:now,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:true,ownerActive:active,windows:windows)
            }
            let baseline=name=="ambiguousBackground" ? [original,second] : [original]
            try lease.begin(sample(baseline,active:false));now+=0.1
            try check(lease.observe(sample(baseline,active:false)) == .unknown,"background alone cannot authorize return")
            now+=0.1
            let current=name=="changedLevel" ? [W(id:200,pid:b.owner.pid,level:42,onScreen:true)] :
                name=="changedWindowOwner" ? [W(id:200,pid:99,level:0,onScreen:true)] : baseline
            let state=lease.observe(sample(current,active:name != "stillBackground"))
            if name=="existingReactivated" {
                try check(state == .active,"same exact background ordinary window observed reactivated")
                now+=0.1;try check(lease.observe(sample(current,active:false)) == .unknown,"one inactive sample still insufficient")
                now+=0.11;try check(lease.observe(sample(current,active:false)) == .inactive,"reactivated existing window defocus permits inactivity")
                let proof=try lease.confirmation()
                try check(proof.windowID==200 && !proof.nativeObservation,"exact existing ID; offline is not native proof")
            } else {
                try check(state == .unknown,"ambiguous/unactivated/reidentified baseline cannot attach")
                var refused=false;do{try lease.requireInactive()}catch{refused=true}
                try check(refused,"unobserved existing interface cannot authorize return")
            }
        }
        scenarios+=1
        var layoutBinding=b
        layoutBinding.layoutDestination=b.neighbor
        layoutBinding.layoutOnLeft=false
        try layoutBinding.validate()
        let layout=IceSelectedRecord(binding:layoutBinding,generation:UUID(),contract:.ordinaryIceLayoutV10)
        try layout.validate()
        try check(layout.schemaVersion==5,"layout uses a separate durable contract, not temporary return")
        var placed=layout;placed.revision=1;placed.phase = .moving
        try placed.validate()
        placed.revision+=1;placed.phase = .placed;placed.placementEvidenceSHA256=String(repeating:"a",count:64)
        try placed.validate()
        try check(placed.gestures.isEmpty && !placed.needsRelease,"already-at-destination no-op needs no input")
        var invalid=placed;invalid.placementEvidenceSHA256=nil
        var refused=false;do{try invalid.validate()}catch{refused=true}
        try check(refused,"layout terminal requires durable placement evidence")
        let oldContract=IceSelectedRecord(binding:layoutBinding,generation:UUID(),contract:.ordinaryIceInterfaceV9)
        refused=false;do{try oldContract.validate()}catch{refused=true}
        try check(refused,"temporary workflow refuses layout intent")
        let noIntent=IceSelectedRecord(binding:b,generation:UUID(),contract:.ordinaryIceLayoutV10)
        refused=false;do{try noIntent.validate()}catch{refused=true}
        try check(refused,"persistent layout refuses missing destination")
        scenarios+=1
        let generation=UUID(),payload=ShelfDragPayload(id:99,generation:generation)
        let data=try JSONEncoder().encode(payload)
        try check(ShelfDragPayload.decode(data,generation:generation,known:[99]) != nil,"own current panel drag accepted")
        try check(ShelfDragPayload.decode(data,generation:UUID(),known:[99]) == nil,"stale panel rejected")
        try check(ShelfDragPayload.decode(data,generation:generation,known:[100]) == nil,"foreign source rejected")
        try check(ShelfDragPayload.decode(Data(repeating:0,count:4096),generation:generation,known:[99]) == nil,"oversize payload rejected")
        for name in ["cancelObserved","cancelDelay","unknown","multiple","rebuild","reopenedDuringReturn","forgedReturn"] {try await workflow(name,b)}
        return(scenarios,assertions)
    }
    static func workflow(_ name:String,_ b:IceSelectedBinding)async throws {
        scenarios+=1
        let parent=FileManager.default.temporaryDirectory.appendingPathComponent("ice-interface-replay-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:parent)}
        let store=IceSelectedJournal(directory:parent.appendingPathComponent("journal")),server=IceSelectedOfflineChecks.Server(b)
        let coordinator=IceSelectedCoordinator(journal:store,binding:b,contract:.ordinaryIceInterfaceV9,deadline:190,clock:{server.time})
        let native=IceSelectedNative(windows:nil,pid:b.owner.pid,identity:{},offline:true,clock:{server.time},sleep:{try await server.pause($0)},waitReceiptDeadline:{try await server.awaitReceiptDeadline($0)},permission:{true},send:{try server.send($0,$1)},makeTap:{server.makeTap($0,$1,$2,$3)})
        let effects=IceSelectedOfflineChecks.Effects(native,server,coordinator)
        var seq=0,rebuild=false,cancelledAtPosts:Int?
        let lease=IceSelectedInterfaceLease(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,clock:{server.time},reader:{
            seq+=1;var windows:[IceSelectedInterfaceLease.Window]=[]
            if name != "unknown" {windows=[.init(id:rebuild ? 101 : 100,pid:b.owner.pid,level:0,onScreen:server.menu)]}
            if name=="multiple" && server.menu {windows.append(.init(id:101,pid:b.owner.pid,level:0,onScreen:true))}
            return .init(sequence:seq,at:server.time,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:true,ownerActive:true,windows:windows)
        })
        // Offline baseline is deliberately supplied; it cannot become native evidence.
        try lease.begin(.init(sequence:0,at:server.time,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:true,ownerActive:false,windows:[]))
        if name=="cancelDelay" {server.onPause={_ in if server.sends==8 && server.time>105 && cancelledAtPosts==nil {cancelledAtPosts=server.sends;coordinator.cancel()}}}
        if name=="reopenedDuringReturn" {server.onSend={if server.sends==9 {server.menu=true}}}
        var caught:Error?
        do {try await IceSelectedWorkflow.executeInterface(coordinator:coordinator,makeEffects:{(native,effects)},makeLease:{lease},verifyVisible:{},verifyReturned:{Data("forged offline return".utf8)},afterInterfaceObserved:{
            if name=="cancelObserved" {cancelledAtPosts=server.sends;coordinator.cancel()}
            else if name=="rebuild" {rebuild=true}
            else {server.menu=false}
        })}catch{caught=error}
        try check(caught != nil && !coordinator.completed,"negative workflow cannot complete/clear")
        try check(try store.inspect()?.phase == .stopped,"failure persists stopped responsibility")
        try check(!lease.nativeObservation,"offline window replay never native")
        if let cancelledAtPosts {try check(server.sends==cancelledAtPosts && server.sends==8,"cancel during observation/delay emits no later input")}
        else if ["forgedReturn","multiple","rebuild"].contains(name) {try check(server.sends==14,"all fake routes run before forged native return is rejected");try check(coordinator.retained?.gestures.allSatisfy{$0.status == .pairedTransportReturned}==true,"three paired modeled gestures retained")}
        else if name=="reopenedDuringReturn" {try check(server.sends==9,"fresh reactivation rejects return down after admitted null")}
        else {try check(server.sends==8,"unknown/multiple/rebuild cannot reach restore")}
    }
}
