// Actual native capture adapter for the reviewed pure relative geometry model.
// No JSON input can construct a live return proof. No new private API or sender.
import AppKit

@MainActor final class IceSelectedLiveReturnProof {
    let plan:IceRelativeReturn.Plan,data:Data,atUptime:Double
    fileprivate init(plan:IceRelativeReturn.Plan,data:Data,atUptime:Double){self.plan=plan;self.data=data;self.atUptime=atUptime}
    func validate(binding:IceSelectedBinding,now:Double)throws {
        try IceSelectedLiveRelative.validate(plan,binding:binding)
        guard now>=atUptime,now-atUptime<=0.25,!data.isEmpty else{throw IceSelectedFailure.binding}
    }
}

@MainActor final class IceSelectedLiveRelative {
    typealias R=IceRelativeReturn
    struct Fact:Codable,Equatable {let id:UInt32,pid:Int32,frame:R.Rect,spaces:[UInt64],alpha:Double}
    let binding:IceSelectedBinding,windows:IceBaselineWindows
    private(set)var plan:R.Plan!
    private(set)var protectedProcesses:[IceSelectedBinding.Process]=[]
    private var identities:[UInt32:R.Identity]=[:],sequence=0
    private var carrierProofs:[Int32:MenuBarProcessSignature.Proof]=[:]
    var diagnostics:(String,[String:Any])->Void={_,_ in}
    init(binding:IceSelectedBinding,windows:IceBaselineWindows,restoring:R.Plan?=nil,
         diagnostics:@escaping(String,[String:Any])->Void={_,_ in})throws {
        self.binding=binding;self.windows=windows;self.diagnostics=diagnostics
        if let restoring {
            try Self.validate(restoring,binding:binding);plan=restoring;sequence=restoring.baseline.sequence
            identities=Dictionary(uniqueKeysWithValues:restoring.baseline.members.map{($0.identity.windowID,$0.identity)})
        }else {
            let (facts,_,_) = try raw()
            for fact in facts {
                identities[fact.id] = .init(windowID:fact.id,pid:fact.pid,launch:nil,executable:nil,identifier:nil,team:nil,sha256:nil)
            }
            let initial=try snapshot(),ids=R.ordered(initial.members).map{$0.identity.windowID}
            guard let ti=ids.firstIndex(of:binding.target.id),let ni=ids.firstIndex(of:binding.neighbor.id),abs(ti-ni)==1 else{throw IceSelectedFailure.binding}
            let low=min(ti,ni),high=max(ti,ni)
            let candidates=[high+1,low-1].filter{$0>=0 && $0<ids.count && ids[$0] != binding.anchor.id}
            guard let wi=candidates.first else{throw IceSelectedFailure.binding}
            let cohort=[binding.target.id,binding.neighbor.id,ids[wi]],positions=cohort.compactMap{ids.firstIndex(of:$0)}.sorted()
            var protected=Set(cohort+[binding.anchor.id])
            if let first=positions.first,first>0{protected.insert(ids[first-1])}
            if let last=positions.last,last+1<ids.count{protected.insert(ids[last+1])}
            // The reviewed contract pins full process identities only for
            // protected roles; other queue members retain exact WindowID/PID.
            for id in protected.sorted() {
                guard let expected=identities[id] else{throw IceSelectedFailure.binding}
                diagnostics("relative-protected-process",["windowID":id,"pid":expected.pid])
                let p=try MenuBarProcessSignature.read(expected.pid)
                identities[id] = .init(windowID:id,pid:p.pid,launch:p.launch,executable:p.executable,identifier:p.identifier,team:p.team,sha256:p.sha256)
            }
            let baseline=try snapshot()
            plan = .init(baseline:baseline,target:binding.target.id,neighbor:binding.neighbor.id,anchor:binding.anchor.id,returnOnLeft:binding.returnOnLeft,cohort:cohort)
            try Self.validate(plan,binding:binding)
        }
        let ids=R.ordered(plan.baseline.members).map{$0.identity.windowID},positions=plan.cohort.compactMap{ids.firstIndex(of:$0)}.sorted()
        var protected=Set(plan.cohort+[plan.anchor])
        if let first=positions.first,first>0{protected.insert(ids[first-1])}
        if let last=positions.last,last+1<ids.count{protected.insert(ids[last+1])}
        protectedProcesses=try protected.sorted().map{id in
            guard let i=identities[id],let launch=i.launch,let path=i.executable,let bundle=i.identifier,let hash=i.sha256 else{throw IceSelectedFailure.binding}
            return try .init(.init(pid:i.pid,launch:launch,executable:path,identifier:bundle,team:i.team,sha256:hash,appleAnchor:false))
        }
    }
    nonisolated static func rect(_ f:CGRect)->R.Rect{.init(x:f.minX,y:f.minY,width:f.width,height:f.height)}
    func scope()throws->R.Scope {
        guard NSScreen.screens.count==1,let s=NSScreen.screens.first,let a=s.auxiliaryTopRightArea,
              let d=(s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else{throw IceSelectedFailure.binding}
        return .init(display:d,space:UInt64(windows.activeSpace(windows.connection())),bar:.init(x:s.frame.minX,y:binding.target.frame.y,width:s.frame.width,height:binding.target.frame.height),
                     approvedArea:.init(x:a.minX,y:binding.area.y,width:a.width,height:binding.area.height))
    }
    /// Each half independently joins a complete native enumeration with CG.
    /// Wide dividers and negative frames remain. Scope filtering is fixed here.
    private func raw()throws->([Fact],Bool,R.Scope) {
        let scopeBefore=try scope(),directory=try IceMenuBarReadAdapter.isolatedReadOnly().read()
        guard let all=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else{throw IceBaselineError.source}
        let rows=Dictionary(grouping:all,by:{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0})
        var facts:[Fact]=[],consistent=true
        for member in directory.members {
            guard let matching=rows[member.windowID],matching.count==1,let row=matching.first,
                  let pid=(row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,pid>0,
                  let layer=(row[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let values=row[kCGWindowBounds as String] as? [String:Any],let frame=CGRect(dictionaryRepresentation:values as CFDictionary),
                  let alpha=(row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,alpha.isFinite else{throw IceBaselineError.source}
            if layer != Int(CGWindowLevelForKey(.statusWindow)) {
                // Recognized menu-bar carrier only, never an arbitrary dropped row.
                guard layer==Int(CGWindowLevelForKey(.mainMenuWindow)),frame.minX==scopeBefore.bar.x,
                      frame.minY==scopeBefore.bar.y,frame.width==scopeBefore.bar.width,frame.height>0,frame.height<64 else{throw IceBaselineError.source}
                diagnostics("relative-carrier",["pid":pid,"windowID":member.windowID,"role":"classifierOnlyExistingReadCarrier"])
                let proof=try MenuBarProcessSignature.readCarrier(pid)
                guard proof.appleAnchor,proof.identifier=="com.apple.WindowServer",proof.executable=="/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
                      carrierProofs[pid]==nil || carrierProofs[pid]==proof else{throw IceSelectedFailure.binding}
                carrierProofs[pid]=proof
                continue
            }
            if !member.spaces.contains(scopeBefore.space){continue}
            guard frame.minY==scopeBefore.bar.y,frame.height==scopeBefore.bar.height,alpha>0,alpha<=1 else{throw IceBaselineError.geometry}
            consistent = consistent && frame==member.frame
            facts.append(.init(id:member.windowID,pid:pid,frame:Self.rect(frame),spaces:member.spaces.sorted(),alpha:alpha))
        }
        let after=try scope()
        consistent = consistent && scopeBefore==after && directory.spaceBefore==scopeBefore.space && directory.spaceAfter==scopeBefore.space
        guard !facts.isEmpty,Set(facts.map(\.id)).count==facts.count else{throw IceBaselineError.source}
        return(facts.sorted{$0.id<$1.id},consistent,after)
    }
    func snapshot()throws->R.Snapshot {
        let (before,firstCoherent,firstScope)=try raw(),(after,lastCoherent,lastScope)=try raw()
        sequence+=1
        let members=try after.map{f->R.Member in
            guard let identity=identities[f.id],identity.pid==f.pid else{throw IceSelectedFailure.binding}
            return .init(identity:identity,frame:f.frame)
        }
        let snap=R.Snapshot(sequence:sequence,uptime:ProcessInfo.processInfo.systemUptime,scope:lastScope,members:members,
                            coherent:firstCoherent && lastCoherent && before==after && firstScope==lastScope,
                            completeDirectory:true,readerHealthy:true,provenance:"liveNativeCGPrivateBeforeAfter")
        let encode=JSONEncoder();encode.outputFormatting=[.sortedKeys]
        diagnostics("relative-sample-\(sequence)",["snapshot":try JSONSerialization.jsonObject(with:encode.encode(snap)),
                      "rawBefore":try JSONSerialization.jsonObject(with:encode.encode(before)),"rawAfter":try JSONSerialization.jsonObject(with:encode.encode(after))])
        return snap
    }
    nonisolated static func validate(_ plan:R.Plan,binding:IceSelectedBinding)throws {
        var same=plan.baseline;same.sequence+=1;same.uptime+=1
        guard plan.target==binding.target.id,plan.neighbor==binding.neighbor.id,plan.anchor==binding.anchor.id,plan.returnOnLeft==binding.returnOnLeft,
              plan.baseline.scope.display==binding.display,plan.baseline.scope.space==binding.space,
              plan.baseline.scope.approvedArea==rect(binding.area.cg),R.evaluate(plan,same).proposedGeometrySatisfied else{throw IceSelectedFailure.binding}
        for item in [binding.target,binding.neighbor,binding.anchor] {
            guard let m=plan.baseline.members.first(where:{$0.identity.windowID==item.id}),m.frame==rect(item.frame.cg),
                  m.identity.pid==item.process.pid,m.identity.launch==item.process.launch,m.identity.executable==item.process.executable,
                  m.identity.identifier==item.process.identifier,m.identity.team==item.process.team,m.identity.sha256==item.process.sha256 else{throw IceSelectedFailure.binding}
        }
    }
    func verify(runtime:IceSelectedRuntime,check:()throws->Void={})async throws->IceSelectedLiveReturnProof {
        try runtime.checkFullSignatures()
        let limit=ProcessInfo.processInfo.systemUptime+1
        var stability=R.Stability(),samples:[R.Snapshot]=[],ready=false
        while !ready {
            try Task.checkCancellation();try check();try runtime.check()
            let sample=try snapshot(),observed=stability.observe(plan,sample,now:ProcessInfo.processInfo.systemUptime)
            samples.append(sample);ready=observed.1
            guard ProcessInfo.processInfo.systemUptime<limit else{throw IceBaselineError.geometry}
            if !ready{try await Task.sleep(nanoseconds:120_000_000)}
        }
        let settledDelta=stability.delta
        // Final samples must extend, not restart, the same settled layout.
        for _ in 0..<2 {
            try Task.checkCancellation();try check();try runtime.check()
            try await Task.sleep(nanoseconds:100_000_000)
            let sample=try snapshot(),observed=stability.observe(plan,sample,now:ProcessInfo.processInfo.systemUptime)
            guard observed.1,stability.delta==settledDelta else{throw IceBaselineError.geometry}
            samples.append(sample)
        }
        guard let last=samples.last else{throw IceBaselineError.geometry}
        let decision=R.evaluate(plan,last),encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let payload:[String:Any]=["version":2,"criterion":R.version,"guarantee":"originalRelativeSlot",
            "nonce":binding.nonce.uuidString,"relativeGeometryVerified":true,"nativeReadProvenance":last.provenance,
            "absoluteProtectedFramesVerified":decision.strictProtectedAbsoluteFrames as Any? ?? NSNull(),
            "absoluteScopedPeerFramesVerified":decision.strictAllPeerFrames as Any? ?? NSNull(),
            "decision":try JSONSerialization.jsonObject(with:encoder.encode(decision)),"samples":try JSONSerialization.jsonObject(with:encoder.encode(samples))]
        let data=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys])
        return .init(plan:plan,data:data,atUptime:last.uptime)
    }
}

// Only this live sampler can issue the persistent-layout completion proof.
@MainActor struct IceSelectedLayoutProof {
    let binding: IceSelectedBinding, data: Data, at: Double
    private init(binding:IceSelectedBinding,data:Data,at:Double){self.binding=binding;self.data=data;self.at=at}
    func validate(binding expected:IceSelectedBinding,now:Double)throws {
        guard binding==expected,expected.layoutDestination != nil,now>=at,now-at<0.25,!data.isEmpty else{throw IceSelectedFailure.binding}
    }
    static func capture(_ plan:IceSelectedPlan)async throws->Self {
        let b=plan.binding
        guard let destination=b.layoutDestination,let left=b.layoutOnLeft,
              plan.runtime.processes.contains(destination.process) else{throw IceSelectedFailure.policy}
        func sample()throws->[String:Any] {
            try plan.runtime.checkFullSignatures();try plan.verifyRuntime()
            let t=try plan.windows.frame(plan.item(b.target)),d=try plan.windows.frame(plan.item(destination))
            guard abs((left ? t.maxX-d.minX : t.minX-d.maxX))<=1,
                  t.minY==d.minY,t.height==d.height else{throw IceBaselineError.geometry}
            return ["targetID":b.target.id,"destinationID":destination.id,"onLeft":left,
                    "targetFrame":NSStringFromRect(t),"destinationFrame":NSStringFromRect(d)]
        }
        let first=try sample();try await Task.sleep(nanoseconds:120_000_000)
        let second=try sample();try Task.checkCancellation()
        guard first["targetFrame"] as? String==second["targetFrame"] as? String,
              first["destinationFrame"] as? String==second["destinationFrame"] as? String else{throw IceBaselineError.geometry}
        let at=ProcessInfo.processInfo.systemUptime
        let data=try JSONSerialization.data(withJSONObject:["criterion":"icePersistentNeighborEdgeV10","nonce":b.nonce.uuidString,
            "display":b.display,"space":b.space,"nativeObservation":true,"first":first,"second":second,"atUptime":at],options:.sortedKeys)
        return .init(binding:b,data:data,at:at)
    }
}
