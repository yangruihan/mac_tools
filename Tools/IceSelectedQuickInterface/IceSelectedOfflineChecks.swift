// Copyright (c) 2026 Ryan.AI. MIT. Replay only: fake sender/taps/clock/cursor.
import AppKit

@MainActor enum IceSelectedOfflineChecks {
    enum Failure: Error { case assertion(String), injected }
    static var assertions = 0
    static func check(_ value: Bool, _ message: String) throws {
        assertions += 1;guard value else {throw Failure.assertion(message)}
    }
    static func process(_ pid: Int32, _ identifier: String, _ exe: String) throws -> IceSelectedBinding.Process {
        try .init(.init(pid:pid,launch:1,executable:exe,identifier:identifier,team:nil,sha256:String(repeating:"a",count:64),appleAnchor:false))
    }
    static func binding() throws -> IceSelectedBinding {
        let controller = try process(99,"com.ryanai.mactools","/tmp/Ice Selected Controller.app/Contents/MacOS/IceSelectedController")
        let owner = try process(20,"ordinary.owner","/Applications/Ordinary.app/Contents/MacOS/Ordinary")
        let neighborOwner = try process(21,"ordinary.neighbor","/Applications/Neighbor.app/Contents/MacOS/Neighbor")
        return .init(nonce:UUID(),controller:controller,owner:owner,display:1,space:2,area:.init(CGRect(x:0,y:0,width:2000,height:24)),
                     target:.init(id:1,process:owner,frame:.init(CGRect(x:-1000,y:0,width:30,height:24))),
                     neighbor:.init(id:2,process:neighborOwner,frame:.init(CGRect(x:-970,y:0,width:30,height:24))),
                     anchor:.init(id:3,process:controller,frame:.init(CGRect(x:1000,y:0,width:30,height:24))),returnOnLeft:true)
    }
    static func relativePlan(_ b:IceSelectedBinding)->IceRelativeReturn.Plan {
        typealias R=IceRelativeReturn
        func member(_ id:UInt32,_ p:IceSelectedBinding.Process,_ frame:CGRect)->R.Member {
            .init(identity:.init(windowID:id,pid:p.pid,launch:p.launch,executable:p.executable,identifier:p.identifier,team:p.team,sha256:p.sha256),frame:IceSelectedLiveRelative.rect(frame))
        }
        let members=[member(b.target.id,b.owner,b.target.frame.cg),member(b.neighbor.id,b.neighbor.process,b.neighbor.frame.cg),
            member(4,b.neighbor.process,CGRect(x:-940,y:0,width:30,height:24)),member(5,b.neighbor.process,CGRect(x:-910,y:0,width:1910,height:24)),
            member(b.anchor.id,b.controller,b.anchor.frame.cg)]
        let base=R.Snapshot(sequence:0,uptime:99,scope:.init(display:b.display,space:UInt64(b.space),bar:.init(x:0,y:0,width:2000,height:24),approvedArea:IceSelectedLiveRelative.rect(b.area.cg)),
            members:members,coherent:true,completeDirectory:true,readerHealthy:true,provenance:"injectedModelNotNative")
        return .init(baseline:base,target:b.target.id,neighbor:b.neighbor.id,anchor:b.anchor.id,returnOnLeft:b.returnOnLeft,cohort:[1,2,4])
    }
    static func relativeJournalChecks()async throws {
        let b=try binding(),p=relativePlan(b)
        try IceSelectedLiveRelative.validate(p,binding:b)
        var extra=p
        extra.baseline.members.append(.init(identity:.init(windowID:6,pid:222,launch:nil,executable:nil,identifier:nil,team:nil,sha256:nil),frame:.init(x:1030,y:0,width:30,height:24)))
        try IceSelectedLiveRelative.validate(extra,binding:b)
        try check(extra.baseline.members.last?.identity.launch==nil,"unprotected peer needs exact WindowID/PID, not a new full-signature gate")
        let parent=FileManager.default.temporaryDirectory.appendingPathComponent("relative-journal-replay-\(UUID())")
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:parent)}
        let store=IceSelectedJournal(directory:parent.appendingPathComponent("journal"))
        let record=IceSelectedRecord(binding:b,generation:UUID(),contract:.ordinaryIceRelativeV2,relativePlan:p)
        try record.validate();_ = try store.persist(record,replacing:nil)
        try check(record.schemaVersion==2,"new version stores reviewed frozen plan")
        try check(try store.inspect()==record,"relative baseline durable before effects")
        let data=try JSONEncoder().encode(record)
        var obj=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var rp=obj["relativePlan"] as! [String:Any],base=rp["baseline"] as! [String:Any]
        base["sequence"]=1;base["uptime"]=100;rp["baseline"]=base;obj["relativePlan"]=rp;obj["phase"]="moving";obj["revision"]=1
        let changed=try JSONDecoder().decode(IceSelectedRecord.self,from:JSONSerialization.data(withJSONObject:obj))
        try changed.validate();var denied=false
        do{_ = try store.persist(changed,replacing:record)}catch{denied=true}
        try check(denied && (try store.inspect())==record,"even geometrically identical baseline cannot change after prepare")
        var stopped=record;stopped.phase = .stopped;stopped.revision=1;stopped.stopReason="offline"
        var samples:[IceRelativeReturn.Snapshot]=[]
        for i in 1...5 {var sample=p.baseline;sample.sequence=i;sample.uptime=100+Double(i-1)*0.12;samples.append(sample)}
        let e=JSONEncoder(),raw=try JSONSerialization.jsonObject(with:e.encode(samples))
        let payload=try JSONSerialization.data(withJSONObject:["criterion":IceRelativeReturn.version,"nonce":b.nonce.uuidString,"relativeGeometryVerified":true,"samples":raw])
        let first=IceSelectedManualObservation(atUptime:99.7,hidLeftDown:false,combinedLeftDown:false,pressedButtons:0,noOwnerPopup:true)
        let second=IceSelectedManualObservation(atUptime:99.9,hidLeftDown:false,combinedLeftDown:false,pressedButtons:0,noOwnerPopup:true)
        let receipt=IceSelectedManualReceipt(version:2,record:stopped,recordSHA256:try IceSelectedOwnedRecovery.digest(stopped),returnEvidence:payload,first:first,second:second,verifiedAt:100.5,disposition:"manualRelativeReturnObserved",nativePosts:0,nativeReturnProven:false,physicalReleaseProven:false)
        try receipt.validate(stopped);try check(IceSelectedManualRecovery.eligible(stopped),"inert receipt parser accepts complete relative samples, not a live permit")
        var broken=samples;broken[4].members[0].frame.x+=1
        let wrong=try JSONSerialization.data(withJSONObject:["criterion":IceRelativeReturn.version,"nonce":b.nonce.uuidString,"relativeGeometryVerified":true,"samples":try JSONSerialization.jsonObject(with:e.encode(broken))])
        let bad=IceSelectedManualReceipt(version:2,record:stopped,recordSHA256:receipt.recordSHA256,returnEvidence:wrong,first:first,second:second,verifiedAt:100.5,disposition:receipt.disposition,nativePosts:0,nativeReturnProven:false,physicalReleaseProven:false)
        denied=false;do{try bad.validate(stopped)}catch{denied=true};try check(denied,"manual receipt rejects single target offset despite claimed success flag")
        let c=IceSelectedCoordinator(journal:store,binding:b,contract:.ordinaryIceRelativeV2,deadline:145,relativePlan:p,clock:{100})
        denied=false
        do{try await c.confirmReturned(evidence:Data("{\"liveCapture\":true,\"relativeGeometryVerified\":true}".utf8))}catch{denied=true}
        try check(denied && !c.completed && (try store.inspect())==record,"claimed JSON cannot admit live return or clear")
    }
    @MainActor final class Tap: IceBaselineTapControl {
        var rawReceipt:IceReceiverReceipt?
        var isEnabled = false
        let location: EventTap.Location, types: [CGEventType], callback: IceSelectedNative.TapCallback
        init(_ location: EventTap.Location, _ types: [CGEventType], _ callback: @escaping IceSelectedNative.TapCallback) {
            self.location=location;self.types=types;self.callback=callback
        }
        func enable(){isEnabled=true};func disable(){isEnabled=false}
    }
    @MainActor final class Server {
        var time = 100.0, taps: [Tap] = [], queued: [@MainActor () -> Void] = []
        var frames: [UInt32:CGRect], menu = false, menuOwner: Int32 = 20, healthy = true
        var handled: Set<Int64> = [], sends = 0, failSend: Int?, onSend: (() -> Void)?
        var cursorHides = 0, cursorShows = 0, warps = 0
        var identityValid = true, identityCost = 0.0, identityChecks = 0
        var scenario="", extendedPause=false,scopeValid=true
        var onPause:((Double)->Void)?
        let b: IceSelectedBinding
        init(_ b: IceSelectedBinding) {self.b=b;frames=[1:b.target.frame.cg,2:b.neighbor.frame.cg,3:b.anchor.frame.cg]}
        func makeTap(_ options:CGEventTapOptions,_ location:EventTap.Location,_ types:[CGEventType],_ callback:@escaping IceSelectedNative.TapCallback)->any IceBaselineTapControl {
            let tap=Tap(location,types,callback);taps.append(tap);return tap
        }
        func send(_ event: CGEvent, _ location: EventTap.Location) throws {
            sends += 1;if failSend == sends {throw Failure.injected};onSend?()
            if event.type != .null,handled.insert(event.getIntegerValueField(.eventSourceUserData)).inserted {
                if event.flags.contains(.maskCommand) {frames[1]=CGRect(x:19000,y:0,width:30,height:24)}
                else if event.type == .leftMouseUp,event.getIntegerValueField(.mouseEventClickState)==0 {
                    let destination=UInt32(event.getIntegerValueField(CGEventField(rawValue:0x33)!))
                    if let f=frames[destination] {frames[1]=CGRect(x:f.minX-30,y:0,width:30,height:24)}
                } else if event.type == .leftMouseUp {menu=true}
            }
            // Callback happens after the admitted send returns, as on a runloop.
            for tap in taps where tap.isEnabled && tap.location.logString == location.logString && tap.types.contains(event.type) {
                guard let copy=event.copy() else{throw Failure.injected}
                if sends==8 {
                    if ["tapUserEarly","tapTimeoutEarly","tapTimeoutLate","staleUserEarly","staleUserLate"].contains(scenario) {
                        if scenario != "staleUserEarly" && scenario != "staleUserLate" {tap.disable()}
                        let notice:CGEventType=["tapUserEarly","staleUserEarly","staleUserLate"].contains(scenario) ? .tapDisabledByUserInput : .tapDisabledByTimeout
                        queued.append {_=tap.callback(tap,notice,copy)}
                        if scenario=="tapTimeoutLate" || scenario=="staleUserLate" {continue}
                    }
                    if scenario=="ownFieldMismatch" {copy.setIntegerValueField(CGEventField(rawValue:0x33)!,value:0)}
                    if scenario=="ownWrongType" {copy.type = .leftMouseDown}
                    if scenario=="duplicateReceipt" {queued.append {_=tap.callback(tap,copy.type,copy)}}
                }
                if (sends==8 && ["timelyRawLateConsumer","receiptThenSenderThrows","rawThenCancel"].contains(scenario)) || (sends==1 && scenario=="nullRawLateConsumer") || (sends==2 && scenario=="sessionRawLateConsumer") {
                    let fence=IceSelectedFence(),state=IceReceiverState(),a=IceReceiverChecks.admission(IceReceiverKey(copy),UUID(),time+0.05)
                    state.arm(a,fence);state.posted(IceReceiverKey(copy),at:time)
                    tap.rawReceipt=state.receive(IceReceiverKey(copy),at:time+0.001,enabled:true)
                    if scenario=="receiptThenSenderThrows" {_=tap.callback(tap,copy.type,copy);throw Failure.injected}
                    queued.append {self.time+=0.09;if self.scenario=="rawThenCancel"{self.onSend?()};_=tap.callback(tap,copy.type,copy)}
                } else {queued.append { _=tap.callback(tap,copy.type,copy) }}
            }
            if sends==8 && scenario=="slowPost" {time+=0.09}
            // Simulate WindowServer annotations on the dispatched copy.
            event.flags.insert(.maskNonCoalesced)
        }
        func pause(_ duration:Double) async throws {
            time += duration;onPause?(duration)
            if sends==8 && !extendedPause && ["lateWake","tapTimeoutLate","staleUserLate"].contains(scenario) {
                time+=0.09;extendedPause=true
            }
            let pending=queued;queued=[];pending.forEach{$0()}
        }
        func awaitReceiptDeadline(_ deadline:Double) async throws {
            while !queued.isEmpty && time<deadline {
                try await pause(0.001)
                try Task.checkCancellation()
            }
            time=max(time,deadline)
        }
        func sample(_ sequence:Int)->IceSelectedMenuLease.Sample {
            .init(sequence:sequence,atUptime:time,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:healthy,
                  windows:menu ? [.init(id:100,pid:menuOwner,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))] : [])
        }
    }
    final class Effects: IceBaselineEffects {
        let native: IceSelectedNative, server: Server, coordinator: IceSelectedCoordinator
        init(_ native:IceSelectedNative,_ server:Server,_ coordinator:IceSelectedCoordinator){self.native=native;self.server=server;self.coordinator=coordinator}
        var time:Double{server.time};var lastMouseMove:Double?{nil};var mouseButtonDown:Bool{false}
        func checkRuntime()throws{try native.checkRuntime()}
        func frame(_ item:IceBaselineItem)throws->CGRect{try native.checkRuntime();guard let f=server.frames[item.windowID]else{throw Failure.injected};return f}
        func pause(_ seconds:Double)async throws{try await server.pause(seconds)}
        func cursor()throws->CGPoint{CGPoint(x:10,y:10)}
        func hideCursor(){try? coordinator.performAux("mock-hide"){server.cursorHides+=1}}
        func showCursor(){server.cursorShows+=1}
        func warp(_ point:CGPoint){try? coordinator.performAux("mock-warp"){server.warps+=1}}
        func configureSuppression()throws{try coordinator.performAux("mock-suppression"){} }
        func beginGesture(down:CGEvent,up:CGEvent)async throws{try await native.beginGesture(down:down,up:up)}
        func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent{try native.makePacket(type,move:move,point:point,item:item,pid:pid,marker:marker)}
        func prepareRoutingTaps(check:()throws->Void)throws{try native.prepareRoutingTaps(check:check)}
        func scromble(_ event:CGEvent,pid:Int32,check:@escaping()throws->Void)async throws{try await native.scromble(event,pid:pid,check:check)}
        func postAndWait(_ event:CGEvent,check:@escaping()throws->Void)async throws{try await native.postAndWait(event,check:check)}
        func note(_ phase:String,_ values:[String:Any]){native.note(phase,values)}
    }
    static func runCase(_ name:String)async throws {
        let b=try binding();try b.validate()
        let parent=FileManager.default.temporaryDirectory.appendingPathComponent("ice-selected-replay-\(UUID())")
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:parent)}
        let store=IceSelectedJournal(directory:parent.appendingPathComponent("journal"),fault:{ point in
            if name=="ioUncertain",case .renamed=point {throw Failure.injected}
        })
        let server=Server(b)
        server.scenario=name
        let coordinator=IceSelectedCoordinator(journal:store,binding:b,contract:name=="relativeJSONForgery" ? .ordinaryIceRelativeV2 : (name=="quickJSONForgery" ? .ordinaryIceQuickV4 : .ordinaryIceQuietV1),deadline:145,relativePlan:name=="relativeJSONForgery" ? relativePlan(b) : nil,clock:{server.time})
        if name=="hotValidationCost" {server.identityCost=0.004}
        if name=="ordinary8msValidation" {server.identityCost=0.008}
        if name=="identityLostBeforeDispatch" {server.onSend={if server.sends==1{server.identityValid=false}}}
        if name=="scopeLostBeforeClickUp" {server.onSend={if server.sends==7{server.scopeValid=false}}}
        let native=IceSelectedNative(windows:nil,pid:20,identity:{
            server.identityChecks+=1;server.time+=server.identityCost
            guard server.identityValid && server.scopeValid else{throw Failure.injected}
        },offline:true,clock:{server.time},sleep:{try await server.pause($0)},waitReceiptDeadline:{try await server.awaitReceiptDeadline($0)},
                                    permission:{true},send:{try server.send($0,$1)},makeTap:{server.makeTap($0,$1,$2,$3)})
        let effects=Effects(native,server,coordinator)
        var sequence=0
        let lease=IceSelectedMenuLease(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,clock:{server.time},reader:{sequence+=1;return server.sample(sequence)})
        try lease.begin(server.sample(0))
        if name=="restoreReopened" {server.onSend={if server.sends==9{server.menu=true}}}
        if name=="sendFailure" {server.failSend=2}
        if name=="cancelDuringDown" {server.onSend={if server.sends==2 {coordinator.cancel()}}}
        if name=="taskCancelDuringFirstPost" {server.onSend={if server.sends==1 {withUnsafeCurrentTask{$0?.cancel()}}}}
        if name=="rawThenCancel" {server.onSend={if server.sends==8 {coordinator.cancel()}}}
        if name=="foreignMenu" {server.menuOwner=21}
        var caught:Error?
        do {
            try await IceSelectedWorkflow.run(coordinator:coordinator,native:native,effects:effects,lease:lease,
                verifyVisible:{try check(server.frames[1]?.maxX==1000,"visible exact edge")},
                verifyReturned:{
                    try check(server.frames[1]==b.target.frame.cg,"exact original target")
                    try check(server.frames[2]==b.neighbor.frame.cg,"exact original neighbor")
                    try check(server.frames[3]==b.anchor.frame.cg,"exact original anchor")
                    if name=="returnRejected"{throw Failure.injected}
                    return Data("offline exact model evidence; not native".utf8)
                },afterMenuOpened:{
                    if name=="cancelAfterOpen"{coordinator.cancel()}
                    else if name=="unknownClosed"{server.healthy=false}
                    else{server.menu=false}
                })
        }catch{caught=error}
        try check(server.sends==native.posts,"count fake dispatch calls")
        try check(!lease.nativeObservation,"replay cannot claim native observation")
        if ["normal","hotValidationCost","ordinary8msValidation","tapUserEarly","tapTimeoutEarly","duplicateReceipt","staleUserEarly","timelyRawLateConsumer"].contains(name) {
            try check(caught==nil,"normal completed")
            try check(native.posts==14,"14 exact fake routes")
            try check(coordinator.completed,"completed receipt")
            try check(try store.inspect()==nil,"clear only returned")
            try check(coordinator.durableReturned?.phase == .returned,"returned durable")
            try check(coordinator.acknowledgments.count==22,"22 append-only durable ACKs")
            let record=try XCT(coordinator.durableReturned)
            try check(record.gestures.count==3,"three paired gestures")
            try check(record.gestures.allSatisfy{$0.status == .pairedTransportReturned},"paired transport only")
            try check(record.gestures.flatMap(\.routes).allSatisfy{$0.destination=="session event tap" || $0.destination=="PID 20"},"never post to foreign destination PID")
            try check(record.gestures[0].up.window==3 && record.gestures[2].up.window==2,"cross-owner windows bound")
            try check(record.gestures[0].down.flags==CGEventFlags.maskCommand.rawValue,"OS annotations did not mutate intent")
            if name=="timelyRawLateConsumer" {
                try check(native.events.contains{$0["phase"] as? String=="route-receipt-continuation-resumed" && $0["resumedAfterDeadline"] as? Bool==true},"timely raw with 90ms main delay completes exact normal14/22")
            }
            if name=="tapUserEarly" || name=="tapTimeoutEarly" {
                let notices=native.events.filter{$0["phase"] as? String=="tap-disable-notice"}
                try check(notices.count==1,"capture actual callback notification once")
                try check(notices[0]["reason"] as? String==(name=="tapUserEarly" ? "userInput" : "timeout"),"distinguish both disabled notification types")
                try check(!native.events.contains{$0["phase"] as? String=="tap-reenable-refused"},"early disable reenable retains original dispatch, no resend")
            }
            if name=="staleUserEarly" {
                try check(native.events.contains{$0["phase"] as? String=="tap-stale-disable-notice" && $0["action"] as? String=="alreadyEnabledNoop"},"already-enabled UserInput notice is informational")
                try check(!native.events.contains{$0["phase"] as? String=="ice-tap-reenabled" && $0["route"] as? String=="session-click"},"do not reenable a currently enabled tap")
            }
        }else{
            try check(caught != nil,"negative case rejected")
            try check(!coordinator.completed,"not returned")
            try check(try store.inspect() != nil,"retain responsibility")
            let count=native.posts,warps=server.warps
            do{try await native.postAndWait(try IceBaselinePacket.make(.leftMouseUp,move:false,point:CGPoint(x:100,y:12),item:.init(windowID:1,pid:20,key:"selected"),pid:20,marker:999),check:{})}catch{}
            try check(native.posts==count,"no post after terminal fence")
            try check(server.warps==warps,"no warp after terminal fence")
            if ["receiptThenSenderThrows","rawThenCancel"].contains(name) {
                try check(native.posts==8 && (try store.inspect())?.gestures.last?.status == .upReserved,"sender throw or cancellation overrides timely raw, no false durable up ACK")
            }
            if name=="nullRawLateConsumer" || name=="sessionRawLateConsumer" {
                try check(native.posts==(name=="nullRawLateConsumer" ? 1:2),"timely intermediate raw cannot authorize next dispatch after50ms")
                try check((try store.inspect())?.gestures.first?.status == .downReserved,"late intermediate keeps conservative original reservation")
            }
            if name=="cancelAfterOpen" || name=="unknownClosed" || name=="foreignMenu" {try check(native.posts==8,"no restore while cancelled/unknown")}
            if name=="restoreReopened" {try check(native.posts==9,"reopened menu refuses next restore dispatch")}
            if name=="identityLostBeforeDispatch" {try check(native.posts==1,"fresh identity rejects next dispatch, after only fake null")}
            if name=="taskCancelDuringFirstPost" {
                try check(native.posts==1 && coordinator.possibleDown,"Task cancellation while awaiting receipt retains only first admitted dispatch")
                try check(coordinator.fence.stop.snapshot.reason == .cancelled,"onCancel synchronously latches the send fence before its actor-hop")
                try check(try store.inspect()?.gestures.first?.status == .downReserved,"no route ACK after cancellation while awaiting receipt")
            }
            if name=="cancelDuringDown" || name=="sendFailure" {try check(coordinator.possibleDown,"conservative reserved down")}
            if name=="ioUncertain" {try check(native.posts==0 && coordinator.journalOutcomeUncertain,"unknown prepared IO sends zero")}
            if ["tapTimeoutLate","slowPost","lateWake","ownFieldMismatch","ownWrongType","staleUserLate"].contains(name) {
                try check(native.posts==8 && coordinator.possibleDown,"interrupted click up conservatively retains eight dispatched intents")
                try check(try store.inspect()?.gestures.last?.status == .upReserved,"missing/late receipt cannot create a transport ACK")
            }
            if name=="staleUserLate" {
                try check(native.events.contains{$0["phase"] as? String=="tap-stale-disable-notice"},"late informational notice remains distinguishable")
                try check(native.events.contains{$0["phase"] as? String=="route-receipt-timeout" && $0["completed"] as? Bool==false},"stale notice never satisfies or extends the 50ms receipt budget")
            }
            if name=="scopeLostBeforeClickUp" {
                try check(native.posts==7 && coordinator.possibleDown,"fresh scope rejection prevents the actual up dispatch")
                try check(try store.inspect()?.gestures.last?.status == .downReturned,"preserve partial gesture after scope loss, no invented up ACK")
            }
            if name=="tapTimeoutLate" {
                try check(native.events.contains{$0["phase"] as? String=="tap-disable-notice" && $0["reason"] as? String=="timeout"},"late notification type is captured before deadline check")
                try check(native.events.contains{$0["phase"] as? String=="tap-reenable-refused"},"never reenable after deadline")
            }
            if name=="slowPost" {
                try check(native.events.contains{$0["phase"] as? String=="post-call-exit" && ($0["elapsedMS"] as? Double ?? 0)>80 && $0["returnedNormally"] as? Bool==true},"separate long synchronous post from missing receipt")
                try check(!native.events.contains{$0["phase"] as? String=="route-wait-late-wake"},"long post is not mislabeled late await wake")
            }
            if name=="lateWake" {
                try check(native.events.contains{$0["phase"] as? String=="route-deadline-rejected"},"late actual callback receipt is still rejected without 1ms polling")
                try check(!native.events.contains{$0["phase"] as? String=="tap-disable-notice"},"late receipt need not imply a disabled notification")
            }
            if name=="ownFieldMismatch" {
                try check(native.events.contains{$0["phase"] as? String=="own-marker-observed" && $0["fieldsMatch"] as? Bool==false},"own marker with wrong window is observable but cannot ACK")
            }
            if name=="ownWrongType" {
                try check(native.events.contains{$0["phase"] as? String=="own-marker-observed" && $0["fieldsMatch"] as? Bool==true && $0["type"] as? UInt32==CGEventType.leftMouseDown.rawValue && $0["expectedType"] as? UInt32==CGEventType.leftMouseUp.rawValue},"four equal fields do not ACK the wrong mouse type on a prepared mixed mask")
            }
            if name=="relativeJSONForgery" {
                let stopped=try XCT(try store.inspect())
                try check(native.posts==14 && stopped.schemaVersion==2,"all fake routes do not manufacture native proof")
                try check(stopped.phase == .stopped && stopped.relativePlan==relativePlan(b),"retain immutable relative responsibility")
                var unpaired=stopped;unpaired.gestures[2].status = .upReserved;try unpaired.validate()
                let obs=IceSelectedManualObservation(atUptime:100,hidLeftDown:false,combinedLeftDown:false,pressedButtons:0,noOwnerPopup:true)
                let later=IceSelectedManualObservation(atUptime:100.2,hidLeftDown:false,combinedLeftDown:false,pressedButtons:0,noOwnerPopup:true)
                let receipt=IceSelectedManualReceipt(version:2,record:unpaired,recordSHA256:try IceSelectedOwnedRecovery.digest(unpaired),returnEvidence:Data("fake".utf8),first:obs,second:later,verifiedAt:100.3,disposition:"manualRelativeReturnObserved",nativePosts:0,nativeReturnProven:false,physicalReleaseProven:false)
                var refused=false;do{try receipt.validate(unpaired)}catch IceSelectedFailure.unresolvedDown{refused=true}
                try check(refused,"released flags cannot retire an unpaired ordinary transport")
            }
        }
    }
    static func XCT<T>(_ value:T?)throws->T{guard let value else{throw Failure.injected};return value}
    static func receiptWaitChecks()async throws {
        var clock=10.0
        let timely=IceSelectedReceiptWait(deadline:10.05,clock:{clock})
        try check(timely.received(),"timely callback accepted")
        clock=10.08
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in timely.install(c)}
        try check(timely.acceptedAt==10 && timely.settlementCount==1,"consumer wake after 50ms does not undo a timely actual receipt")
        try check(!timely.received() && !timely.fail(CancellationError()) && timely.settlementCount==1,"duplicate receipt/timeout/cancel cannot resume twice")
        let late=IceSelectedReceiptWait(deadline:10.05,clock:{clock})
        try check(!late.received(),"late callback cannot manufacture a timely receipt")
        var failed=false
        do{try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in late.install(c)}}catch{failed=true}
        try check(failed && late.acceptedAt==nil && late.settlementCount==1,"late receipt throws and records no acceptance")
        let cancelled=IceSelectedReceiptWait(deadline:11,clock:{clock})
        cancelled.fail(CancellationError());failed=false
        do{try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in cancelled.install(c)}}catch is CancellationError{failed=true}
        try check(failed && !cancelled.received(),"cancellation-before-install resumes once and rejects later receipt")
        let timeoutFirst=IceSelectedReceiptWait(deadline:11,clock:{clock})
        timeoutFirst.fail(IceBaselineError.timeout)
        try check(!timeoutFirst.received() && timeoutFirst.acceptedAt==nil && timeoutFirst.settlementCount==1,"timeout wins once and later callback cannot ACK")
        let pending=IceSelectedReceiptWait(deadline:11,clock:{clock})
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in pending.install(c);pending.received();pending.fail(IceBaselineError.timeout)}
        try check(pending.settlementCount==1,"installed continuation is resumed exactly once")
    }
    static func menuTraceChecks()throws {
        let b=try binding();var now=100.0,records:[[String:Any]]=[]
        func sample(_ sequence:Int,_ windows:[IceSelectedMenuLease.Window],space:UInt=2)->IceSelectedMenuLease.Sample {
            .init(sequence:sequence,atUptime:now,owner:b.owner,nonce:b.nonce,display:1,space:space,healthy:true,windows:windows)
        }
        let baseline=[IceSelectedMenuLease.Window(id:1,pid:20,level:25)]
        let popup=IceSelectedMenuLease.Window(id:200,pid:20,level:Int(CGWindowLevelForKey(.popUpMenuWindow)))
        let lease=IceSelectedMenuLease(owner:b.owner,nonce:b.nonce,display:1,space:2,clock:{now},trace:{kind,facts in var row=facts;row["kind"]=kind;records.append(row)})
        try lease.begin(sample(0,baseline));now+=0.01
        try check(lease.observe(sample(1,baseline+[popup])) == .open,"logged standard popup keeps original opening decision")
        now+=0.03;try check(lease.observe(sample(2,baseline)) == .unknown,"one absent sample does not prove closure")
        now+=0.14;try check(lease.observe(sample(3,baseline)) == .closed,"second original100ms absent sample confirms closure")
        let proof=try lease.confirmation()
        try check(!proof.nativeObservation && proof.observedMenus==[200],"trace replay cannot become live menu proof")
        try check(records.count==4 && records[1]["state"] as? String=="open" && records[3]["state"] as? String=="closed","trace emits exact before/after native-equivalent state sequence")
        try check(records[2]["unknownReason"] as? String=="awaitingSecondAbsentSample","trace distinguishes closure pending from no menu seen")
        let nonstandard=IceSelectedMenuLease(owner:b.owner,nonce:b.nonce,display:1,space:2,clock:{now},trace:{_,facts in records.append(facts)})
        try nonstandard.begin(sample(0,baseline));now+=0.01
        let custom=IceSelectedMenuLease.Window(id:201,pid:20,level:102)
        try check(nonstandard.observe(sample(1,baseline+[custom])) == .unknown,"102 panel remains unknown; no widened menu classification")
        let row=records.last!
        try check(row["unknownReason"] as? String=="noStandardPopupObserved" && (row["nonStandardHighOwnerWindows"] as? [[String:Any]])?.count==1,"capture wrong-layer evidence instead of guessing it closed")
        let scoped=IceSelectedMenuLease(owner:b.owner,nonce:b.nonce,display:1,space:2,clock:{now},trace:{_,facts in records.append(facts)})
        try scoped.begin(sample(0,baseline));now+=0.01
        try check(scoped.observe(sample(1,baseline+[popup],space:9)) == .unknown,"scope-invalid observation cannot open")
        let failed=records.last!
        try check(failed["validSample"] as? Bool==false && failed["expectedSpace"] as? UInt==2 && failed["sampleSpace"] as? UInt==9,"failed scope logs actual compared fields")
        now+=0.01
        try check(scoped.observe(sample(2,baseline+[popup])) == .unknown,"later corrected observation cannot reset identityLost")
        try check(scoped.diagnostics()["identityLost"] as? Bool==true,"trace never changes sticky failure behavior")
    }
    static func runAll()async throws->[String:Any] {
        assertions=0
        let interfaceChecks=try await IceInterfaceChecks.run()
        try menuTraceChecks()
        for name in ["normal","cancelAfterOpen","cancelDuringDown","sendFailure","unknownClosed","foreignMenu","ioUncertain","returnRejected","hotValidationCost","identityLostBeforeDispatch","restoreReopened","relativeJSONForgery","ordinary8msValidation","quickJSONForgery","tapUserEarly","tapTimeoutEarly","tapTimeoutLate","slowPost","lateWake","ownFieldMismatch","ownWrongType","duplicateReceipt","staleUserEarly","staleUserLate","scopeLostBeforeClickUp","timelyRawLateConsumer","nullRawLateConsumer","sessionRawLateConsumer","receiptThenSenderThrows","rawThenCancel"] {try await runCase(name)}
        let cancelledCase=Task {try await runCase("taskCancelDuringFirstPost")}
        try await cancelledCase.value
        let receiverAssertions=try IceReceiverChecks.replay()
        try await receiptWaitChecks()
        try await relativeJournalChecks()
        let t=CGRect(x:100,y:0,width:32,height:37),n=CGRect(x:132,y:0,width:38,height:37)
        try check(IceSelectedPlan.quickPosition(t,n,onLeft:true),"Ice original neighbor edge accepts exact adjacency")
        try check(IceSelectedPlan.quickPosition(t.offsetBy(dx:-16,dy:0),n.offsetBy(dx:-16,dy:0),onLeft:true),"shared translation does not block quick Ice position")
        try check(!IceSelectedPlan.quickPosition(t.offsetBy(dx:1,dy:0),n,onLeft:true),"single-item wrong position still fails Ice adjacency")
        try check(!IceSelectedPlan.quickPosition(t,n,onLeft:false),"wrong neighbor side still fails")
        try check(!IceSelectedPlan.quickPosition(t.offsetBy(dx:0,dy:1),n,onLeft:true),"wrong menu bar row still fails")
        return ["passed":true,"scenarios":42+interfaceChecks.0,"interfaceScenarios":interfaceChecks.0,"interfaceAssertions":interfaceChecks.1,"legacyScenarios":42,"legacyAssertions":assertions,"receiverAssertions":receiverAssertions,"assertions":assertions+interfaceChecks.1,"nativePosts":0,"nativeTaps":0,"cursorEffects":0,"provenance":"isolatedReplayWithInjectedSenderAndTaps"]
    }
}
