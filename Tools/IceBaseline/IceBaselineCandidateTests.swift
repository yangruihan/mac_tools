// Copyright (c) 2026 Ryan.AI. MIT. Actual candidate adapter/engine/transport,
// real file durability; injected frame, clock, tap and send seams only.
import AppKit
import Darwin

@MainActor enum IceBaselineCandidateTests {
    enum Failure: Error { case assertion(String), injected }
    static var assertions = 0
    static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw Failure.assertion(name) }; assertions += 1
    }
    static func rejects(_ name: String, _ body: () async throws -> Void) async throws {
        var rejected = false
        do { try await body() } catch { rejected = true }
        try require(rejected, name)
    }
    final class Fault: @unchecked Sendable {
        let lock = NSLock(), entered = DispatchSemaphore(value:0), release = DispatchSemaphore(value:0)
        let point: IceBaselineCandidateJournal.Point, occurrence: Int, pause: Bool
        private var seen = 0, waiting = false
        init(_ point: IceBaselineCandidateJournal.Point, _ occurrence: Int = 1, pause: Bool = false) {
            self.point=point;self.occurrence=occurrence;self.pause=pause
        }
        var isWaiting: Bool { lock.lock();defer{lock.unlock()};return waiting }
        func hit(_ p: IceBaselineCandidateJournal.Point) throws {
            guard p == point else { return }
            lock.lock();seen += 1;let selected=seen == occurrence
            if selected && pause { waiting=true };lock.unlock()
            guard selected else { return }
            if pause { entered.signal();guard release.wait(timeout:.now()+5) == .success else { throw Failure.injected } }
            else { throw Failure.injected }
        }
    }
    @MainActor final class Scene: IceBaselineEffects {
        let h=IceBaselineOffline.TransportHarness(), layout:IceBaselineLayout, binding:IceCandidateBinding
        let store:IceBaselineCandidateJournal, adapter:IceBaselineCandidateCoordinator
        var frames:[UInt32:CGRect], warps=0,hides=0,shows=0
        var time:Double { h.time };var lastMouseMove:Double?;var mouseButtonDown=false
        lazy var engine=IceBaselineEngine(self)
        let target=IceBaselineItem(windowID:1,pid:123,key:"T"), anchor=IceBaselineItem(windowID:3,pid:123,key:"H"), neighbor=IceBaselineItem(windowID:2,pid:123,key:"N")
        init(_ directory:URL, contract:IceCandidateContract = .isolatedOwnedQuietV1, fault:Fault?=nil, nonce:UUID=UUID()) {
            func item(_ id:UInt32,_ key:String,_ x:Double,_ w:Double,_ visible:Bool)->IceBaselineLayout.Item {
                .init(id:id,instance:UUID().uuidString,key:key,frame:.init(x:x,y:0,width:w,height:30),visible:visible,screen:1)
            }
            layout = .init(target:item(1,"mactools_native_acceptance_T",-120,20,false),neighbor:item(2,"mactools_native_acceptance_N",-100,30,false),anchor:item(3,"ice_baseline_H_\(nonce.uuidString)",100,30,true),divider:item(4,"ice_baseline_D_\(nonce.uuidString)",-70,400,false),returnOnLeft:true)
            binding = .init(nonce:nonce,controller:.init(pid:456,launch:1,executable:"/tmp/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController",identifier:"com.ryanai.mactools",sha256:String(repeating:"a",count:64)),fixture:.init(pid:123,launch:1,executable:"/tmp/Ice Baseline Targets.app/Contents/MacOS/IceBaselineTargets",identifier:"com.ryanai.mactools.nativetargets",sha256:String(repeating:"b",count:64)),display:1,space:1,area:.init(x:50,y:0,width:200,height:30),layout:layout)
            store = .init(directory:directory,fault:{try fault?.hit($0)})
            let harness=h
            adapter = .init(journal:store,binding:binding,contract:contract,deadline:51,clock:{harness.time})
            frames=Dictionary(uniqueKeysWithValues:[layout.target,layout.neighbor,layout.anchor,layout.divider].map{($0.id,$0.frame)})
            h.deferredDelivery=true
            h.onSend = { [weak self] event,location in
                guard let self,location.logString == "PID 123" else { return }
                if event.type == .leftMouseDown { self.frames[1]!.origin.x += 1 }
                if event.type == .leftMouseUp,let f=self.frames[UInt32(event.getIntegerValueField(CGEventField(rawValue:0x33)!))] { self.frames[1]!.origin.x=f.minX-self.frames[1]!.width }
            }
        }
        func attach() throws { try h.transport.bindCandidate(adapter);try adapter.attach(engine) }
        func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent {try h.transport.makePacket(type,move:move,point:point,item:item,pid:pid,marker:marker)}
        func checkRuntime() throws { try h.transport.checkRuntime() }
        func frame(_ item:IceBaselineItem)throws->CGRect { frames[item.windowID]! }
        func pause(_ s:Double)async throws { try await h.transport.pause(s) }
        func cursor()throws->CGPoint { .init(x:1,y:2) }
        func hideCursor() { try? adapter.performAux("mock-hide"){hides += 1} }
        func showCursor() { shows += 1 }
        func warp(_ p:CGPoint) { try? adapter.performAux("mock-warp"){warps += 1} }
        func configureSuppression()throws { try h.transport.configureSuppression() }
        func beginGesture(down:CGEvent,up:CGEvent)async throws { try await h.transport.beginGesture(down:down,up:up) }
        func prepareRoutingTaps(check:()throws->Void)throws { try h.transport.prepareRoutingTaps(check:check) }
        func scromble(_ event:CGEvent,pid:Int32,check:@escaping()throws->Void)async throws { try await h.transport.scromble(event,pid:pid,check:check) }
        func postAndWait(_ event:CGEvent,check:@escaping()throws->Void)async throws { try await h.transport.postAndWait(event,check:check) }
        func note(_ p:String,_ d:[String:Any]) { h.transport.note(p,d) }
        func move()async throws { try await adapter.advance(.moving);try await engine.move(target,to:.left(anchor)) }
        func open()async throws { try await adapter.advance(.visible);try await adapter.advance(.opening);try await engine.click(target) }
        func finish()async throws {
            try await adapter.advance(.menuClosed);try await adapter.advance(.restoring)
            try await engine.rehide(target,to:.left(neighbor),interfaceOpen:{false})
            try require(frames[1] == layout.target.frame,"injected strict original frame")
            try await adapter.confirmReturned(evidence:Data("OFFLINE injected original frames and owners; no hardware proof".utf8))
        }
    }
    static func run() async throws {
        assertions=0
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ice-durable-tests-\(UUID())",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:root)}
        func scene(_ name:String,contract:IceCandidateContract = .isolatedOwnedQuietV1,fault:Fault?=nil)->Scene { Scene(root.appendingPathComponent(name),contract:contract,fault:fault) }
        let normal=scene("normal")
        do { try await normal.adapter.run { try normal.attach();try await normal.move();try await normal.open();try await normal.finish() } }
        catch {
            fputs("candidate normal failed: \(error); phase=\(normal.adapter.retained?.phase.rawValue ?? "nil") routes=\(normal.h.routes) gestures=\(String(describing:normal.adapter.retained?.gestures))\n",stderr)
            throw error
        }
        try require(normal.h.routes.count == 14 && normal.h.transport.posts == 14,"durable adapter actual shared engine and Native route order 14 injected sends")
        try require(normal.h.taps.allSatisfy{!$0.isEnabled} && normal.warps == 3 && normal.hides == normal.shows,"normal route taps and visibility balanced")
        try require(normal.adapter.completed && !normal.adapter.possibleDown && (try normal.store.inspect()) == nil,"returned proof committed then journal cleared")
        try require(normal.adapter.durableReturned?.gestures.count == 3 && normal.adapter.acknowledgments.map{$0["revision"] as! Int} == Array(0..<normal.adapter.acknowledgments.count),"audit preserves ordered durable ACKs and full returned binding after clearing")
        try require(normal.adapter.diagnostics()["pendingRecovery"] as? Bool == false && normal.adapter.diagnostics()["physicalReleaseProven"] as? Bool == false,"completed audit does not imply pending recovery or hardware release")
        for contract in [IceCandidateContract.disabled,.productionANY,.isolatedOwnedANYV1] {
            let s=scene(contract.rawValue,contract:contract)
            try await rejects("\(contract) rejected before journal and effects"){try await s.adapter.run{try s.attach();try await s.move()}}
            try require(!FileManager.default.fileExists(atPath:s.store.directory.path) && s.h.routes.isEmpty,"policy reject writes and sends zero")
        }
        let bad=scene("binding")
        let wrong=IceCandidateBinding(nonce:UUID(),controller:bad.binding.controller,fixture:bad.binding.fixture,display:1,space:1,area:bad.binding.area.cg,layout:bad.layout)
        let invalid=IceBaselineCandidateCoordinator(journal:bad.store,binding:wrong,contract:.isolatedOwnedQuietV1,deadline:51)
        try await rejects("nonce/key binding mismatch"){try await invalid.run{throw Failure.assertion("body must not run")}}
        try require(!FileManager.default.fileExists(atPath:bad.store.directory.path),"invalid binding never persists")
        for field in ["pid","window","flags","click","source","point"] {
            let s=scene("wrong-packet-\(field)")
            var deniedBeforeRegister=false
            try await rejects("changed original packet \(field) rejects before effects"){try await s.adapter.run {
                try s.attach();try await s.adapter.advance(.moving)
                let down=try IceBaselinePacket.make(.leftMouseDown,move:true,point:.init(x:20000,y:20000),item:s.target,pid:123,marker:90)
                let up=try IceBaselinePacket.make(.leftMouseUp,move:true,point:.init(x:100,y:15),item:s.anchor,pid:123,marker:91)
                switch field {
                case "pid":down.setIntegerValueField(.eventTargetUnixProcessID,value:999)
                case "window":down.setIntegerValueField(CGEventField(rawValue:0x33)!,value:99)
                case "flags":down.flags=[]
                case "click":down.setIntegerValueField(.mouseEventClickState,value:0)
                case "source":down.setIntegerValueField(.eventSourceStateID,value:0)
                default:down.location = .zero
                }
                do {try await s.adapter.beginGesture(down:down,up:up)}
                catch {deniedBeforeRegister=true;throw error}
            }}
            let saved=try s.store.inspect()
            try require(deniedBeforeRegister && saved?.gestures.isEmpty == true && s.h.routes.isEmpty && saved?.phase == .stopped,"packet mismatch rejected at registration, retains prepared responsibility without dispatch")
        }
        let prepared=scene("prepared-stop")
        try await rejects("cancel durable prepared"){try await prepared.adapter.run{prepared.adapter.cancel();try prepared.adapter.check()}}
        try require(prepared.h.routes.isEmpty && !prepared.adapter.possibleDown && (try prepared.store.inspect())?.phase == .stopped,"stop retained despite no native effect")
        let restart=Scene(prepared.store.directory)
        try await rejects("fresh nonce cannot overwrite unresolved prior transaction"){try await restart.adapter.run{try restart.attach();try await restart.move()}}
        try require(restart.h.routes.isEmpty && (try restart.store.inspect())?.binding.nonce == prepared.binding.nonce,"restart leaves exact old binding")
        try await rejects("stopped coordinator cannot reuse"){try await prepared.adapter.run{}}
        for boundary in 1...8 {
            let s=scene("cancel-route-\(boundary)")
            let update=s.h.onSend
            s.h.onSend={event,location in update?(event,location);if s.h.routes.count == boundary{s.adapter.cancel()}}
            try await rejects("cancel boundary \(boundary)"){try await s.adapter.run{try s.attach();try await s.move();try await s.open()}}
            try require(s.h.routes.count == boundary && s.h.transport.posts == boundary && s.h.taps.allSatisfy{!$0.isEnabled},"stop no forwarding or retry after boundary \(boundary)")
            try require(s.adapter.possibleDown && (try s.store.inspect())?.needsRelease == true,"route intent retained as unconfirmed at boundary \(boundary)")
            try require(!s.h.transport.events.contains{$0["phase"] as? String == "wake-up" || $0["phase"] as? String == "move-fallback"},"no fallback or wake on ambiguous route")
            let n=Scene(s.store.directory)
            try await rejects("new nonce blocked with possible down"){try await n.adapter.run{try n.attach();try await n.move()}}
            try require(n.h.routes.isEmpty,"restart cannot send an implicit up")
        }
        let mutable=scene("OS-packet-annotation")
        let update=mutable.h.onSend
        mutable.h.onSend={event,location in update?(event,location);event.flags.insert(.maskNonCoalesced);event.timestamp=123456}
        try await mutable.adapter.run{try mutable.attach();try await mutable.move();try await mutable.open();try await mutable.finish()}
        try require(mutable.h.routes.count == 14 && mutable.adapter.completed,"OS annotation of dispatch copy cannot mutate exact durable original")
        let wait=scene("wait-stop")
        try await rejects("cancel during 15-second wait"){try await wait.adapter.run{
            try wait.attach();try await wait.move();try await wait.open()
            wait.h.onPause={if wait.h.routes.count == 8{wait.adapter.cancel()}}
            try await wait.finish()
        }}
        try require(wait.h.routes.count == 8 && !wait.adapter.possibleDown && wait.warps == 2 && (try wait.store.inspect())?.phase == .stopped,"wait stop retains restoration responsibility, zero reverse post")
        for point in [IceBaselineCandidateJournal.Point.temporaryCreated,.fileSynced,.renamed,.directorySynced] {
            let s=scene("prepared-fault-\(point)",fault:Fault(point))
            try await rejects("prepared durability fault \(point)"){try await s.adapter.run{try s.attach();try await s.move()}}
            try require(s.h.routes.isEmpty && s.adapter.journalOutcomeUncertain,"prepared uncertainty sends zero")
            let disk=try IceBaselineCandidateJournal(directory:s.store.directory).inspect()
            try require((point == .renamed || point == .directorySynced) ? disk?.phase == .prepared : disk == nil,"restart inspects actual committed envelope \(point)")
            try await rejects("poisoned store refuses another write"){_ = try s.store.persist(IceCandidateRecord(binding:s.binding,generation:UUID(),contract:.isolatedOwnedQuietV1),replacing:disk)}
        }
        // Commit 1 prepared, 2 moving, 3 exact gesture, 4 reserve down routes.
        for point in [IceBaselineCandidateJournal.Point.fileSynced,.renamed,.directorySynced] {
            let s=scene("down-fault-\(point)",fault:Fault(point,4))
            try await rejects("down reservation fault \(point)"){try await s.adapter.run{try s.attach();try await s.move()}}
            try require(s.h.routes.isEmpty && s.adapter.possibleDown && s.adapter.journalOutcomeUncertain,"uncertain reservation is conservative possible down, actual sends zero")
            let saved=try IceBaselineCandidateJournal(directory:s.store.directory).inspect()
            try require(saved != nil && (point == .fileSynced ? saved?.needsRelease == false : saved?.needsRelease == true),"restart preserves committed registered/reserved distinction")
        }
        for parentCancellation in [false,true] {
            let gate=Fault(.renamed,4,pause:true),s=scene("paused-\(parentCancellation)",fault:gate)
            let task=Task{try await s.adapter.run{try s.attach();try await s.move()}}
            let until=ProcessInfo.processInfo.systemUptime+3
            while !gate.isWaiting && ProcessInfo.processInfo.systemUptime<until { await Task.yield() }
            guard gate.isWaiting else{gate.release.signal();task.cancel();throw Failure.assertion("I/O pause reached")}
            if parentCancellation{task.cancel()}else{s.adapter.cancel()}
            try require(s.adapter.fence.stop.snapshot.reason == .cancelled && s.h.routes.isEmpty,"stop remains available while fsync worker paused")
            gate.release.signal()
            try await rejects("paused worker returns without permitting effect"){try await task.value}
            try require(s.adapter.possibleDown && (try s.store.inspect())?.needsRelease == true && s.h.routes.isEmpty,"completed write acknowledged and retained after stop")
        }
        let slowGate=Fault(.renamed,4,pause:true),slow=scene("slow-durable-intent",fault:slowGate)
        let slowTask=Task{try await slow.adapter.run{try slow.attach();try await slow.move()}}
        let slowUntil=ProcessInfo.processInfo.systemUptime+3
        while !slowGate.isWaiting && ProcessInfo.processInfo.systemUptime<slowUntil { await Task.yield() }
        guard slowGate.isWaiting else{slowGate.release.signal();slowTask.cancel();throw Failure.assertion("slow intent pause reached")}
        slow.h.time += 0.6;slowGate.release.signal()
        try await rejects("slow intent must fail its own 500ms preparation bound"){try await slowTask.value}
        try require(slow.h.routes.isEmpty && slow.adapter.possibleDown && (try slow.store.inspect())?.phase == .stopped,"slow I/O does not spend or extend the 50ms route")
        for kind in ["permission","identity","timeout","deadline"] {
            let s=scene(kind)
            s.h.onTapCreated={
                if kind == "permission" {s.h.permissionAllowed=false}
                if kind == "identity" {s.h.identityError=IceBaselineError.identity}
                if kind == "deadline" {s.h.time=52}
            }
            if kind == "timeout" {s.h.drop=true}
            try await rejects("\(kind) fails durable candidate terminally"){try await s.adapter.run{try s.attach();try await s.move()}}
            try require(s.h.routes.count == (kind == "timeout" ? 1 : 0) && s.h.taps.allSatisfy{!$0.isEnabled},"\(kind) cannot fallback or wake")
            try require((try s.store.inspect())?.phase == .stopped,"\(kind) persists stop")
        }
        let cas=scene("CAS"),first=IceCandidateRecord(binding:cas.binding,generation:UUID(),contract:.isolatedOwnedQuietV1)
        _ = try cas.store.persist(first,replacing:nil)
        var moving=first;moving.revision=1;moving.phase = .moving
        _ = try cas.store.persist(moving,replacing:first)
        try await rejects("stale revision CAS"){_ = try cas.store.persist(moving,replacing:first)}
        var backwards=moving;backwards.revision+=1;backwards.phase = .prepared
        try await rejects("backwards phase rejected"){_ = try cas.store.persist(backwards,replacing:moving)}
        var unproven=moving;unproven.revision+=1;unproven.phase = .returned;unproven.returnedEvidenceSHA256=String(repeating:"a",count:64)
        try await rejects("returned without three paired gestures rejected"){_ = try cas.store.persist(unproven,replacing:moving)}
        try await rejects("clear of unresolved move denied"){try cas.store.clear(moving)}
        try require(try cas.store.inspect() == moving,"invalid updates preserve exact durable record")
        let corrupt=scene("corrupt");_ = try corrupt.store.persist(IceCandidateRecord(binding:corrupt.binding,generation:UUID(),contract:.isolatedOwnedQuietV1),replacing:nil)
        let filename=corrupt.store.directory.appendingPathComponent("ice-candidate-v1.json")
        try Data("truncated".utf8).write(to:filename)
        try await rejects("truncated record blocks restart"){_ = try IceBaselineCandidateJournal(directory:corrupt.store.directory).inspect()}
        let unsafe=scene("symlink");try FileManager.default.createDirectory(at:unsafe.store.directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try FileManager.default.createSymbolicLink(atPath:unsafe.store.directory.appendingPathComponent("ice-candidate-v1.json").path,withDestinationPath:filename.path)
        try await rejects("journal symlink refused"){_ = try unsafe.store.inspect()}
        let swap=scene("directory-swap");_ = try swap.store.persist(IceCandidateRecord(binding:swap.binding,generation:UUID(),contract:.isolatedOwnedQuietV1),replacing:nil)
        try FileManager.default.moveItem(at:swap.store.directory,to:root.appendingPathComponent("old-inode"))
        try FileManager.default.createDirectory(at:swap.store.directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try await rejects("directory inode changed refuses store reuse"){_ = try swap.store.inspect()}
        let remove=scene("clear-fault",fault:Fault(.removed))
        try await rejects("clear uncertain completion"){try await remove.adapter.run{try remove.attach();try await remove.move();try await remove.open();try await remove.finish()}}
        try require(remove.adapter.retained?.phase == .returned && !remove.adapter.possibleDown && remove.adapter.clearAdmitted && remove.adapter.journalOutcomeUncertain,"clear uncertainty retains durable returned proof without claiming hardware release")
        try require((try IceBaselineCandidateJournal(directory:remove.store.directory).inspect()) == nil,"restart sees actual unlink outcome, not invented pending down")
        print("Ice async durable candidate checks: \(assertions); actual OS sends/taps/windows = 0; injected Native sends normal=14")
    }
}
