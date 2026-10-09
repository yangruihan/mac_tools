// Copyright (c) 2026 Ryan.AI. MIT. Ice-compatible interface occupancy, not menu closure.
import AppKit

@MainActor final class IceSelectedInterfaceLease {
    enum State:String {case active,inactive,unknown}
    enum Kind:String,Codable {case standardPopup,ordinaryWindow}
    struct Window:Equatable {let id:UInt32,pid:Int32,level:Int,onScreen:Bool}
    struct Sample {
        let sequence:Int,at:Double,owner:IceSelectedBinding.Process,nonce:UUID,display:UInt32,space:UInt
        let healthy:Bool,ownerActive:Bool,windows:[Window]
    }
    struct Evidence:Encodable {
        let owner:IceSelectedBinding.Process,nonce:UUID,display:UInt32,space:UInt,windowID:UInt32,level:Int,kind:Kind
        let firstInactiveAt:Double,secondInactiveAt:Double,nativeObservation:Bool
        let criterion:String = "iceTrackedInterfaceInactiveV9"
    }
    let owner:IceSelectedBinding.Process,nonce:UUID,display:UInt32,space:UInt
    private let clock:()->Double,reader:(()->Sample)?,trace:((String,[String:Any])->Void)?
    private(set) var state:State = .unknown,nativeObservation=false,reason="notBegun"
    private var begun=false,lost=false,sequence = -1,at = -Double.infinity
    private var baseline:Set<UInt32>=[],tracked:Window?,kind:Kind?,firstInactive:Double?,secondInactive:Double?
    init(owner:IceSelectedBinding.Process,nonce:UUID,display:UInt32,space:UInt,clock:@escaping()->Double,
         reader:(()->Sample)?=nil,trace:((String,[String:Any])->Void)?=nil){
        self.owner=owner;self.nonce=nonce;self.display=display;self.space=space;self.clock=clock;self.reader=reader;self.trace=trace
    }
    static func live(owner:IceSelectedBinding.Process,nonce:UUID,display:UInt32,space:UInt,
                     scope:@escaping()->(UInt32,UInt),identity:@escaping()->Bool,
                     trace:((String,[String:Any])->Void)?=nil,
                     ownership:@escaping ([[String:Any]])->Bool={_ in true})->IceSelectedInterfaceLease {
        var sequence=0
        let lease=IceSelectedInterfaceLease(owner:owner,nonce:nonce,display:display,space:space,clock:{ProcessInfo.processInfo.systemUptime},reader:{
            sequence+=1;let identityValid=identity(),currentScope=scope()
            let rows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]]
            let app=NSRunningApplication(processIdentifier:owner.pid)
            var malformed=false
            let windows=(rows ?? []).compactMap{r->Window? in
                guard let id=(r[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      let pid=(r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      let level=(r[kCGWindowLayer as String] as? NSNumber)?.intValue else{malformed=true;return nil}
                return .init(id:id,pid:pid,level:level,onScreen:r[kCGWindowIsOnscreen as String] as? Bool ?? false)
            }
            return .init(sequence:sequence,at:ProcessInfo.processInfo.systemUptime,owner:owner,nonce:nonce,
                         display:currentScope.0,space:currentScope.1,
                         healthy:identityValid && app != nil && rows != nil && ownership(rows ?? []) && windows.count<=4096 && !malformed,
                         ownerActive:app?.isActive ?? false,windows:windows)
        },trace:trace)
        lease.nativeObservation=true;return lease
    }
    private func valid(_ s:Sample)->Bool {
        s.owner==owner && s.nonce==nonce && s.display==display && s.space==space && s.healthy
        && s.sequence>sequence && s.at.isFinite && s.at>=at && clock()>=s.at && clock()-s.at<=0.25
        && Set(s.windows.map(\.id)).count==s.windows.count
    }
    private func interfaces(_ s:Sample)->[Window] {
        s.windows.filter{$0.pid==owner.pid && $0.onScreen && $0.level != Int(CGWindowLevelForKey(.statusWindow))}
    }
    func diagnostics()->[String:Any] {
        ["state":state.rawValue,"reason":reason,"stickyInvalid":lost,"begun":begun,
         "trackedWindowID":tracked?.id as Any? ?? NSNull(),"trackedLevel":tracked?.level as Any? ?? NSNull(),
         "kind":kind?.rawValue as Any? ?? NSNull(),"nativeObservation":nativeObservation,
         "menuClosedClaimed":false,"firstInactiveAt":firstInactive as Any? ?? NSNull(),
         "secondInactiveAt":secondInactive as Any? ?? NSNull()]
    }
    private func emit(_ name:String,_ s:Sample){
        var row=diagnostics();row["sequence"]=s.sequence;row["atUptime"]=s.at;row["ownerActive"]=s.ownerActive
        row["sampleHealthy"]=s.healthy;row["sampleDisplay"]=s.display;row["sampleSpace"]=s.space
        row["ownerWindows"]=s.windows.filter{$0.pid==owner.pid}.map{["id":$0.id,"level":$0.level,"onScreen":$0.onScreen] as [String:Any]}
        trace?(name,row)
    }
    private func invalidate(_ reason:String)->State {lost=true;state = .unknown;self.reason=reason;firstInactive=nil;secondInactive=nil;return state}
    func begin(_ s:Sample)throws {
        guard !begun,valid(s) else{throw IceSelectedFailure.binding}
        // Do not attach to a pre-existing active owner interface.
        guard !interfaces(s).contains(where:{$0.level==Int(CGWindowLevelForKey(.popUpMenuWindow)) || s.ownerActive}) else{throw IceBaselineError.menu}
        baseline=Set(s.windows.filter{$0.pid==owner.pid && $0.onScreen}.map(\.id))
        begun=true;sequence=s.sequence;at=s.at;reason="awaitingObservedInterface";emit("baseline",s)
    }
    func beginLive()throws {guard let reader else{throw IceSelectedFailure.policy};try begin(reader())}
    @discardableResult func observe(_ s:Sample)->State {
        defer{emit("sample",s)}
        guard begun,!lost,valid(s) else{return invalidate("invalidObservation")}
        sequence=s.sequence;at=s.at
        let added=interfaces(s).filter{!baseline.contains($0.id)}
        if tracked==nil {
            guard added.count<=1 else{return invalidate("multipleNewOwnerWindows")}
            guard let w=added.first else{state = .unknown;reason="noInterfaceObserved";return state}
            tracked=w;kind=w.level==Int(CGWindowLevelForKey(.popUpMenuWindow)) ? .standardPopup : .ordinaryWindow
        }
        let w=tracked!
        // A replacement/additional interface is not the original window disappearing.
        guard !added.contains(where:{$0.id != w.id}) else{return invalidate("windowRebuiltOrCompetingInterface")}
        let matches=s.windows.filter{$0.id==w.id}
        if let current=matches.first, current.pid != w.pid || current.level != w.level {return invalidate("trackedWindowIdentityChanged")}
        let showing=(matches.first?.onScreen ?? false) && (kind == .standardPopup || s.ownerActive)
        if showing {state = .active;reason="trackedInterfaceShowing";firstInactive=nil;secondInactive=nil;return state}
        if firstInactive==nil {firstInactive=s.at;state = .unknown;reason="awaitingStableInactive"}
        else if s.at-firstInactive!>=0.1 {secondInactive=s.at;state = .inactive;reason="trackedInterfaceInactive"}
        return state
    }
    @discardableResult func refresh()->State {guard let reader else{return state};return observe(reader())}
    func confirmation()throws->Evidence {
        guard !lost,state == .inactive,let w=tracked,let kind,let first=firstInactive,let second=secondInactive,
              clock()>=second,clock()-second<=0.25 else{throw IceBaselineError.menu}
        return .init(owner:owner,nonce:nonce,display:display,space:space,windowID:w.id,level:w.level,kind:kind,
                     firstInactiveAt:first,secondInactiveAt:second,nativeObservation:nativeObservation)
    }
    func requireInactive(nativeRequired:Bool=false)throws {
        if reader != nil {_=refresh()}
        guard !nativeRequired || nativeObservation else{throw IceSelectedFailure.policy}
        _=try confirmation()
    }
}
