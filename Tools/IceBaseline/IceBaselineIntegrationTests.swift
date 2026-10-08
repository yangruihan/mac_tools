// Copyright (c) 2026 Ryan.AI. MIT. Integration replay and actual disposed-owner
// metadata checks. Sends/taps/cursor effects remain injected throughout.
import AppKit
import Darwin

@MainActor enum IceBaselineIntegrationTests {
    enum Failure:Error {case assertion(String),injected}
    static var checks=0
    static func require(_ value:Bool,_ name:String)throws {guard value else{throw Failure.assertion(name)};checks += 1}
    static func rejects(_ name:String,_ body:()async throws->Void)async throws {
        var failed=false;do{try await body()}catch{failed=true};try require(failed,name)
    }
    final class Input:MenuBarHiddenInterferenceSource {
        var sequence:UInt64=0,continuity=UUID(),epoch=UUID(),lost=false,buttons:Set<UInt16>=[]
        var events:[MenuBarMoveInterference.Event]=[]
        let clock:()->UInt64
        init(_ clock:@escaping()->UInt64){self.clock=clock}
        func read()->MenuBarMoveInterference.Availability {
            sequence += 1
            if lost{return .unavailable(.sourceLost)}
            return .available(.init(sequence:sequence,uptimeMilliseconds:clock(),continuity:continuity,
                externalEpoch:epoch,coverage:MenuBarMoveInterference.requiredCoverage,buttons:buttons,keys:[],modifiers:0))
        }
        func drainEvents()->[MenuBarMoveInterference.Event] {let result=events;events=[];return result}
        func external(){sequence += 1;events.append(.init(sequence:sequence,uptimeMilliseconds:clock(),continuity:continuity,attribution:.unknown))}
    }
    static func run()async throws {
        checks=0
        let deadlineScene=IceBaselineCandidateTests.Scene(FileManager.default.temporaryDirectory.appendingPathComponent("unused-deadline-\(UUID())"))
        try deadlineScene.adapter.constrainDeadline(40)
        try await rejects("operation deadline cannot widen"){try deadlineScene.adapter.constrainDeadline(41)}
        try await rejects("operation deadline cannot be past"){try deadlineScene.adapter.constrainDeadline(0)}
        try await rejects("operation deadline rejects nonfinite"){try deadlineScene.adapter.constrainDeadline(.nan)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ice-integration-tests-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:root)}
        try await any(root);try menu(root);try await menuEngine(root);try await recovery(root);try liveReader()
        print("Ice production integration checks: \(checks); ANY exact replay, menu leases, disposed-owner archive; native sends/taps/cursor = 0")
    }
    static func liveReader()throws {
        // Real native metadata reader on this signed, GUI-free own process.
        // No popup is opened. Absence must stay unknown and deny restore.
        let owner=try IceCandidateBinding.Process(MenuBarProcessSignature.read(getpid())),windows=try IceBaselineWindows()
        func scope()->(UInt32,UInt) {
            (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0,
             windows.activeSpace(windows.connection()))
        }
        let current=scope();try require(current.0>0 && current.1>0,"native reader actual display/Space available")
        let lease=IceBaselineMenuLease.live(owner:owner,nonce:UUID(),display:current.0,space:current.1,scope:scope)
        try lease.beginLive();try require(lease.nativeObservation,"native reader establishes its own provenance")
        try require(lease.refresh() == .unknown,"actual own no-popup observation remains unknown")
        var denied=false;do{try lease.requireClosed(nativeRequired:true)}catch{denied=true}
        try require(denied,"actual native no-popup cannot authorize restore")
    }
    static func any(_ root:URL)async throws {
        for mode in ["normal","external","lost","unmatched","annotated","busy"] {
            let s=IceBaselineCandidateTests.Scene(root.appendingPathComponent("any-\(mode)"),contract:.isolatedOwnedANYV1)
            let input=Input{UInt64(s.h.time*1000)},bridge=try IceBaselineANYBridge.replay(binding:s.binding,input:input,clock:{UInt64(s.h.time*1000)})
            try s.adapter.bindANY(bridge,offline:true)
            let update=s.h.onSend
            s.h.onSend={event,location in
                update?(event,location)
                guard location.logString=="session event tap",event.type != .null else{return}
                if mode=="unmatched" {return}
                if mode=="annotated" {event.flags.insert(.maskNonCoalesced)}
                do{try bridge.receivedReplay(event)}catch{s.adapter.fence.fail()}
                if mode=="external" {input.external()}
                if mode=="lost" {input.lost=true}
                if mode=="busy" {input.buttons=[0]}
            }
            let body:()async throws->Void={try s.attach();try await s.move();try await s.open();try await s.finish()}
            if mode=="normal" {
                try await s.adapter.run(body)
                try require(s.adapter.completed && s.h.routes.count==14,"ANY exact private-source packets through actual engine/transport replay")
                let record=s.adapter.durableReturned!
                try require(record.packetSource?.senderPID==456 && record.packetSource!.state != 1,"ANY persists actual allocated source state, no HID relabel")
                try require(record.gestures.flatMap{[$0.down,$0.up]}.allSatisfy{record.validSource($0)},"complete ANY packet context immutable")
            } else {
                try await rejects("ANY \(mode) rejects at input/receipt boundary"){try await s.adapter.run(body)}
                try require(!s.adapter.completed && s.h.routes.count==(mode=="external" || mode=="annotated" ? 2 : 3),"ANY \(mode) stops at its observation boundary without retry")
                try require((try s.store.inspect())?.needsRelease==true,"ANY \(mode) preserves reserved down responsibility")
                let count=s.h.routes.count
                try await rejects("ANY \(mode) stop cannot reset"){try s.adapter.check()}
                try require(s.h.routes.count==count,"ANY \(mode) no post after stop")
            }
        }
        let s=IceBaselineCandidateTests.Scene(root.appendingPathComponent("no-native-replay"),contract:.isolatedOwnedANYV1)
        let input=Input{1000},bridge=try IceBaselineANYBridge.replay(binding:s.binding,input:input,clock:{1000})
        try await rejects("replay cannot bind native authority"){try s.adapter.bindANY(bridge,offline:false)}
        try require(!FileManager.default.fileExists(atPath:s.store.directory.path),"native rejection before durable intent")
        let t=try bridge.packet(.leftMouseDown,move:true,point:.init(x:20000,y:20000),item:s.target,marker:40)
        try bridge.register(t)
        try await rejects("duplicate packet registration rejected"){try bridge.register(t)}
        let changed=t.copy()!;changed.timestamp += 1
        try await rejects("timestamp change cannot match receipt"){try bridge.receivedReplay(changed)}
        var r=IceCandidateRecord(binding:s.binding,generation:UUID(),contract:.isolatedOwnedANYV1)
        try await rejects("ANY prepared record requires source context"){try r.validate()}
        r.packetSource = .init(senderPID:456,state:1)
        try await rejects("HID context cannot authorize ANY"){try r.validate()}
    }
    static func menu(_ root:URL)throws {
        let s=IceBaselineCandidateTests.Scene(root.appendingPathComponent("menu")),owner=s.binding.fixture,nonce=s.binding.nonce
        var time=1.0
        func lease()->IceBaselineMenuLease {.init(owner:owner,nonce:nonce,display:1,space:1,clock:{time})}
        func sample(_ n:Int,_ windows:[IceBaselineMenuLease.Window]=[],healthy:Bool=true,space:UInt=1)->IceBaselineMenuLease.Sample {
            .init(sequence:n,atUptime:time,owner:owner,nonce:nonce,display:1,space:space,healthy:healthy,windows:windows)
        }
        let popup=IceBaselineMenuLease.Window(id:100,pid:owner.pid,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))
        let a=lease();try a.begin(sample(1));try require(a.observe(sample(2)) == .unknown,"absence without observed open never proves close")
        try require(a.observe(sample(3,[popup])) == .open,"owned popup detected")
        try require(a.observe(sample(4)) == .unknown,"first absence insufficient")
        time += 0.05;try require(a.observe(sample(5)) == .unknown,"short close interval rejected")
        time += 0.06;try require(a.observe(sample(6)) == .closed,"two spaced observations prove scoped close")
        try require(!(try a.confirmation()).nativeObservation,"replay provenance never native")
        var denied=false;do{try a.requireClosed(nativeRequired:true)}catch{denied=true};try require(denied,"replay closure cannot enter native restore")
        time += 0.26;denied=false;do{_ = try a.confirmation()}catch{denied=true};try require(denied,"stale closure rejected")
        for mode in ["uncertain","lost","space","reopened","foreign"] {
            let a=lease();try a.begin(sample(1));_ = a.observe(sample(2,[popup]))
            if mode=="uncertain"{a.actionUncertain()}
            if mode=="lost"{_ = a.observe(sample(3,healthy:false))}
            if mode=="space"{_ = a.observe(sample(3,space:2))}
            if mode=="foreign" {
                let b=lease();try b.begin(sample(1))
                try require(b.observe(sample(2,[.init(id:200,pid:999,level:popup.level)])) == .unknown,"foreign menu cannot satisfy owner lease")
                continue
            }
            _ = a.observe(sample(4));time += 0.12;_ = a.observe(sample(5))
            if mode=="reopened"{_ = a.observe(sample(6,[.init(id:101,pid:owner.pid,level:popup.level)]))}
            denied=false;do{_ = try a.confirmation()}catch{denied=true};try require(denied,"\(mode) cannot trigger restore")
        }
        // Replay the actual v3.5 own menu ID/PID/layer, not an invented native success.
        let repo=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let result=try JSONSerialization.jsonObject(with:Data(contentsOf:repo.appendingPathComponent("docs/evidence/menu-bar-ice-v3_5-normal-live-2026-10-07/session/result.json"))) as! [String:Any]
        let journal=result["candidateJournal"] as! [String:Any]
        let record=try JSONDecoder().decode(IceCandidateRecord.self,from:JSONSerialization.data(withJSONObject:journal["durableRecord"]!))
        let rows=result["menuOpenWindows"] as! [[String:Any]]
        let windows=rows.map{IceBaselineMenuLease.Window(id:($0["kCGWindowNumber"] as! NSNumber).uint32Value,pid:($0["kCGWindowOwnerPID"] as! NSNumber).int32Value,level:($0["kCGWindowLayer"] as! NSNumber).intValue)}
        let b=IceBaselineMenuLease(owner:record.binding.fixture,nonce:record.binding.nonce,display:record.binding.display,space:record.binding.space,clock:{time})
        func captured(_ n:Int,_ windows:[IceBaselineMenuLease.Window])->IceBaselineMenuLease.Sample {.init(sequence:n,atUptime:time,owner:record.binding.fixture,nonce:record.binding.nonce,display:record.binding.display,space:record.binding.space,healthy:true,windows:windows)}
        func ownerWindows(_ value:[String:Any])->[IceBaselineMenuLease.Window] {
            let observation=value["cgOnScreen"] as! [String:Any]
            return (observation["ownRows"] as! [[String:Any]]).map {row in
                func number(_ key:String)->NSNumber {(row[key] as! [String:Any])["value"] as! NSNumber}
                return .init(id:number("kCGWindowNumber").uint32Value,pid:number("kCGWindowOwnerPID").int32Value,level:number("kCGWindowLayer").intValue)
            }
        }
        try b.begin(captured(1,ownerWindows(result["before"] as! [String:Any])))
        try require(b.observe(captured(2,windows)) == .open,"captured actual menu 340904/PID71144 replay")
        try require(b.observe(captured(3,ownerWindows(result["menuClosedOwner"] as! [String:Any]))) == .open,"cached RPC closed owner still has popup and cannot prove close")
        let returned=result["returnedOwners"] as! [[String:Any]]
        _ = b.observe(captured(4,ownerWindows(returned[0])))
        time += (returned[1]["atUnix"] as! Double)-(returned[0]["atUnix"] as! Double)
        try require(b.observe(captured(5,ownerWindows(returned[1]))) == .closed && !(try b.confirmation()).nativeObservation,"actual captured two closed observations remain replay")
    }
    static func menuEngine(_ root:URL)async throws {
        for mode in ["normal","lost","reopened","uncertain"] {
            let s=IceBaselineCandidateTests.Scene(root.appendingPathComponent("menu-engine-\(mode)"))
            var sequence=0,open=false,healthy=true
            let lease=IceBaselineMenuLease(owner:s.binding.fixture,nonce:s.binding.nonce,display:1,space:1,clock:{s.h.time},reader:{
                sequence += 1
                return .init(sequence:sequence,atUptime:s.h.time,owner:s.binding.fixture,nonce:s.binding.nonce,display:1,space:1,healthy:healthy,
                    windows:open ? [.init(id:100,pid:123,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))] : [])
            })
            let body:()async throws->Void={
                try s.attach();try await s.move();try lease.beginLive();try s.adapter.bindMenuLease(lease)
                try await s.open();open=true;try require(lease.refresh() == .open,"engine \(mode) observed scoped menu")
                open=false;_ = lease.refresh();s.h.time += 0.12
                try require(lease.refresh() == .closed,"engine \(mode) fresh close before restore phase")
                if mode=="lost"{healthy=false}
                if mode=="reopened"{open=true}
                if mode=="uncertain"{lease.actionUncertain()}
                try await s.finish()
            }
            if mode=="normal" {
                try await s.adapter.run(body)
                try require(s.adapter.completed && s.h.routes.count==14,"fresh menu lease admits injected engine restore after 15s wait")
            }else{
                try await rejects("engine \(mode) menu refuses restore"){try await s.adapter.run(body)}
                try require(s.h.routes.count==8 && !s.adapter.possibleDown && (try s.store.inspect())?.phase == .stopped,"engine \(mode) stops before restore, retains paired responsibility")
            }
        }
    }
    static func recovery(_ root:URL)async throws {
        let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("docs/evidence/menu-bar-ice-v3_5-wait-cancel-live-2026-10-07/recovery-after-exit/ice-candidate-v1.json")
        let raw=try Data(contentsOf:path)
        func clone(_ name:String,_ fault:IceBaselineCandidateTests.Fault?=nil)throws->IceBaselineCandidateJournal {
            let dir=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let file=dir.appendingPathComponent("ice-candidate-v1.json");try raw.write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            return .init(directory:dir,fault:{try fault?.hit($0)})
        }
        let store=try clone("retire"),record=try store.inspect()!,e=JSONEncoder();e.outputFormatting=[.sortedKeys]
        let hash=IceBaselineCandidateJournal.hash(try e.encode(record))
        try require(IceBaselineRecovery.eligible(record) && record.gestures.count==2,"captured paired wait-cancel eligible for explicit disposal only")
        try await rejects("wrong expected digest cannot retire"){_ = try await IceBaselineRecovery.retire(store,nonce:record.binding.nonce,expectedHash:String(repeating:"0",count:64))}
        try require(try store.inspect()==record,"wrong digest preserves exact old record")
        let receipt=try await IceBaselineRecovery.retire(store,nonce:record.binding.nonce,expectedHash:hash)
        try require(receipt.first.disposed && receipt.second.disposed && receipt.nativePosts==0,"actual dead old own PIDs and absent window IDs observed twice")
        try require(!(receipt.nativeReturnProven || receipt.physicalReleaseProven) && (try store.inspect())==nil,"retirement claims disposal, not native restore/hardware release")
        let archive=store.directory.appendingPathComponent("retired-owned-\(record.transaction.uuidString).json")
        try require(try JSONDecoder().decode(IceCandidateRetirementReceipt.self,from:Data(contentsOf:archive))==receipt,"durable full record archive before journal removal")
        for point in [IceBaselineCandidateJournal.Point.archiveFileSynced,.archiveLinked,.archiveDirectorySynced] {
            let fault=IceBaselineCandidateTests.Fault(point),s=try clone("fault-\(point)",fault)
            try await rejects("archive fault \(point) uncertain result"){_ = try await IceBaselineRecovery.retire(s,nonce:record.binding.nonce,expectedHash:hash)}
            let fresh=IceBaselineCandidateJournal(directory:s.directory)
            try require(try fresh.inspect()==record,"\(point) retains original responsibility")
            _ = try await IceBaselineRecovery.retire(fresh,nonce:record.binding.nonce,expectedHash:hash)
            try require(try fresh.inspect()==nil,"explicit fresh proof resumes partial archive \(point)")
        }
        var uncertain=record;uncertain.gestures[1].status = .upReserved
        try require(!IceBaselineRecovery.eligible(uncertain),"unconfirmed down cannot retire despite extinct owner")
        try await rejects("unconfirmed down cannot receive disposal capability"){_ = try await IceBaselineRecovery.proveDisposed(uncertain)}
        let stale=try await IceBaselineRecovery.proveDisposed(record)
        try await rejects("stale disposal capability rejected before archive"){try stale.validate(record,now:stale.second.atUptime+0.501)}
        let scene=IceBaselineCandidateTests.Scene(root.appendingPathComponent("live-owner")),binding=scene.binding
        var live=IceCandidateRecord(binding:.init(nonce:binding.nonce,controller:.init(pid:getpid(),launch:binding.controller.launch,executable:binding.controller.executable,identifier:binding.controller.identifier,sha256:binding.controller.sha256),fixture:binding.fixture,display:binding.display,space:binding.space,area:binding.area.cg,layout:scene.layout),generation:UUID(),contract:.isolatedOwnedQuietV1)
        live.phase = .stopped;live.stopReason="test"
        try require(!IceBaselineRecovery.sample(live).controllerGone,"live PID blocks disposal")
        try await rejects("live owner cannot receive disposal capability"){_ = try await IceBaselineRecovery.proveDisposed(live)}
    }
}
