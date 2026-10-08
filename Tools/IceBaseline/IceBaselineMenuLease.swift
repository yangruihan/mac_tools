// Copyright (c) 2026 Ryan.AI. MIT. Metadata-only menu lease, no close/click API.
import AppKit

@MainActor final class IceBaselineMenuLease {
    enum State:String,Codable {case open,closed,unknown}
    struct Window:Codable,Equatable {let id:UInt32,pid:Int32,level:Int}
    struct Sample:Codable,Equatable {
        let sequence:Int,atUptime:Double,owner:IceCandidateBinding.Process,nonce:UUID,display:UInt32,space:UInt
        let healthy:Bool,windows:[Window]
    }
    struct Closure:Codable,Equatable {
        let nonce:UUID,owner:IceCandidateBinding.Process,display:UInt32,space:UInt
        let observedMenus:[UInt32],firstClosed:Sample,secondClosed:Sample
        let nativeObservation:Bool
    }
    let owner:IceCandidateBinding.Process,nonce:UUID,display:UInt32,space:UInt
    private(set)var nativeObservation=false
    private let reader:(()->Sample)?,clock:()->Double
    private(set)var state:State = .unknown
    private var baseline:Set<UInt32>=[],observed:Set<UInt32>=[]
    private var begun=false,ambiguousAction=false,identityLost=false,sequence = -1,at = -Double.infinity
    private var firstClosed:Sample?,secondClosed:Sample?
    init(owner:IceCandidateBinding.Process,nonce:UUID,display:UInt32,space:UInt,clock:@escaping()->Double,
         reader:(()->Sample)?=nil) {
        self.owner=owner;self.nonce=nonce;self.display=display;self.space=space;self.clock=clock
        self.reader=reader
    }
    static func live(owner:IceCandidateBinding.Process,nonce:UUID,display:UInt32,space:UInt,
                     scope:@escaping()->(UInt32,UInt)) -> IceBaselineMenuLease {
        var sequence=0
        let lease=IceBaselineMenuLease(owner:owner,nonce:nonce,display:display,space:space,clock:{ProcessInfo.processInfo.systemUptime},reader:{
            sequence += 1
            let current=try? IceCandidateBinding.Process(MenuBarProcessSignature.read(owner.pid))
            let rows=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]]
            let windows=(rows ?? []).compactMap{r->Window? in
                guard let id=(r[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      let pid=(r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      let level=r[kCGWindowLayer as String] as? Int else{return nil}
                return .init(id:id,pid:pid,level:level)
            }
            let currentScope=scope()
            return .init(sequence:sequence,atUptime:ProcessInfo.processInfo.systemUptime,owner:current ?? owner,nonce:nonce,
                display:currentScope.0,space:currentScope.1,healthy:current == owner && rows != nil && windows.count<=4096,windows:windows)
        })
        lease.nativeObservation=true;return lease
    }
    private func valid(_ sample:Sample)->Bool {
        sample.owner==owner && sample.nonce==nonce && sample.display==display && sample.space==space && sample.healthy
            && sample.sequence>sequence && sample.atUptime.isFinite && sample.atUptime>=at
            && clock()>=sample.atUptime && clock()-sample.atUptime<=0.25
    }
    func begin(_ sample:Sample)throws {
        guard !begun,valid(sample)else{throw IceCandidateFailure.binding}
        let menus=sample.windows.filter{$0.pid==owner.pid && $0.level==Int(CGWindowLevelForKey(.popUpMenuWindow))}
        guard menus.isEmpty else{throw IceBaselineError.menu}
        baseline=Set(sample.windows.filter{$0.pid==owner.pid}.map(\.id));begun=true;sequence=sample.sequence;at=sample.atUptime
    }
    func beginLive()throws {guard let reader else{throw IceCandidateFailure.policy};try begin(reader())}
    func actionUncertain() {ambiguousAction=true;state = .unknown;firstClosed=nil;secondClosed=nil}
    @discardableResult func observe(_ sample:Sample)->State {
        guard begun,!identityLost,valid(sample)else{identityLost=true;state = .unknown;firstClosed=nil;secondClosed=nil;return state}
        sequence=sample.sequence;at=sample.atUptime
        guard !ambiguousAction else{state = .unknown;return state}
        let menus=Set(sample.windows.filter{$0.pid==owner.pid && $0.level==Int(CGWindowLevelForKey(.popUpMenuWindow)) && !baseline.contains($0.id)}.map(\.id))
        if !menus.isEmpty {observed.formUnion(menus);state = .open;firstClosed=nil;secondClosed=nil;return state}
        guard !observed.isEmpty else{state = .unknown;return state}
        if firstClosed == nil {firstClosed=sample;state = .unknown}
        else if sample.atUptime-firstClosed!.atUptime>=0.1 {secondClosed=sample;state = .closed}
        return state
    }
    @discardableResult func refresh()->State {guard let reader else{return state};return observe(reader())}
    func confirmation()throws->Closure {
        guard state == .closed,!ambiguousAction,!identityLost,let firstClosed,let secondClosed,
              clock()>=secondClosed.atUptime,clock()-secondClosed.atUptime<=0.25 else{throw IceBaselineError.menu}
        return .init(nonce:nonce,owner:owner,display:display,space:space,observedMenus:observed.sorted(),
            firstClosed:firstClosed,secondClosed:secondClosed,nativeObservation:nativeObservation)
    }
    func requireClosed(nativeRequired:Bool=false)throws {
        if reader != nil {_ = refresh()}
        guard !nativeRequired || nativeObservation else{throw IceCandidateFailure.policy}
        _ = try confirmation()
    }
}
