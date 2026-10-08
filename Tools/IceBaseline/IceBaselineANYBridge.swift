// Copyright (c) 2026 Ryan.AI. MIT. Original ANY broker/Gate/Registry bridge.
// It does not issue Permits, decode an authorization receipt, relax an event
// match or change the original input policies. No third-party target is armed.
import AppKit

@MainActor final class IceBaselineANYBridge {
    enum Failure:Error {case unavailable,wrongOwner,used,receipt,policy,missingNativePermit,missingSigningTeam}
    enum Provenance:String {case nativeRealWorker,isolatedReplay}
    let provenance:Provenance,source:CGEventSource,senderPID:Int32
    let nonce:UUID,targetPID:Int32,targetWindow:UInt32
    private let input:(any MenuBarHiddenInterferenceSource)?,native:MenuBarListenOnlyInterferenceSource?
    private let clock:()->UInt64
    private var gate=MenuBarMoveInterference.Gate(),ticket:MenuBarListenOnlyInterferenceSource.Ticket?
    private var replayRegistry:MenuBarInputAttribution.Registry?
    private var stop:MenuBarOperationStop?,used=false,authorized=false,polling=false
    private init(provenance:Provenance,source:CGEventSource,senderPID:Int32,nonce:UUID,targetPID:Int32,targetWindow:UInt32,
                 input:(any MenuBarHiddenInterferenceSource)?,native:MenuBarListenOnlyInterferenceSource?,clock:@escaping()->UInt64) {
        self.provenance=provenance;self.source=source;self.senderPID=senderPID;self.nonce=nonce;self.targetPID=targetPID
        self.targetWindow=targetWindow;self.input=input;self.native=native;self.clock=clock
    }
    static func native(plan:MenuBarHiddenMoveModel.Plan,binding:IceCandidateBinding,
                       permit:MenuBarRealLocalAuthorization.Permit?,input:MenuBarListenOnlyInterferenceSource,
                       stop:MenuBarOperationStop)throws->IceBaselineANYBridge {
        // All immutable application facts must agree with the original plan.
        // A nil team cannot be renamed to a synthetic "local team" to pass.
        try binding.validate();try plan.validateStructure()
        guard let permit,permit.authority == .nativeRealWorker,!permit.diagnosticOnly else{throw Failure.missingNativePermit}
        guard let team=binding.fixture.team,!team.isEmpty else{throw Failure.missingSigningTeam}
        guard try IceCandidateBinding.Process(MenuBarProcessSignature.read(binding.fixture.pid))==binding.fixture,
              try IceCandidateBinding.Process(MenuBarProcessSignature.read(binding.controller.pid))==binding.controller,
              plan.original.owner.target.application==MenuBarApplicationIdentity.current(pid:binding.fixture.pid),
              plan.original.owner.team==team,
              plan.original.owner.nonce==binding.nonce,plan.original.owner.target.pid==binding.fixture.pid,
              plan.original.owner.target.windowID==binding.target.id,plan.original.owner.itemKey==binding.target.key,
              plan.original.owner.itemInstance.uuidString==binding.target.instance,
              plan.original.owner.codeHash==binding.fixture.sha256,plan.original.scope.displayID==binding.display,
              plan.original.scope.activeSpace==UInt64(binding.space),binding.controller.pid==getpid() else{throw Failure.wrongOwner}
        let witness=MenuBarDispatchWitness.Binding(nonce:binding.nonce,targetPID:binding.fixture.pid,controllerPID:binding.controller.pid,
            controllerLaunch:binding.controller.launch,controllerSHA256:binding.controller.sha256)
        try permit.checkForRealAction(binding:witness)
        let bridge=IceBaselineANYBridge(provenance:.nativeRealWorker,source:input.privateEventSource,senderPID:getpid(),nonce:binding.nonce,
            targetPID:binding.fixture.pid,targetWindow:binding.target.id,input:input,native:input,clock:{UInt64(ProcessInfo.processInfo.systemUptime*1000)})
        bridge.stop=stop;input.bindOperationStop(stop)
        do {
            try MenuBarRealLocalAuthorization.armAndHandoff(plan,permit:permit,input:input,gate:&bridge.gate,now:bridge.clock)
            guard permit.handedOff,bridge.gate.lease != nil else{throw Failure.unavailable}
            bridge.authorized=true;return bridge
        }catch{stop.request(.failed);input.bindOperationStop(nil);throw error}
    }
    /// Explicit replay provenance. A real Native instance cannot bind this.
    static func replay(binding:IceCandidateBinding,input:any MenuBarHiddenInterferenceSource,clock:@escaping()->UInt64)throws->IceBaselineANYBridge {
        guard let source=CGEventSource(stateID:.privateState)else{throw Failure.unavailable}
        let bridge=IceBaselineANYBridge(provenance:.isolatedReplay,source:source,senderPID:binding.controller.pid,nonce:binding.nonce,
            targetPID:binding.fixture.pid,targetWindow:binding.target.id,input:input,native:nil,clock:clock)
        let sample=input.read();_ = input.drainEvents();_ = try bridge.gate.begin(sample,now:clock())
        bridge.replayRegistry = .init(senderPID:binding.controller.pid,privateSourceState:Int64(source.sourceStateID.rawValue))
        bridge.authorized=true;return bridge
    }
    func bind(_ fence:MenuBarOperationStop,binding:IceCandidateBinding,offline:Bool)throws {
        guard !used,authorized,nonce==binding.nonce,targetPID==binding.fixture.pid,targetWindow==binding.target.id,
              senderPID==binding.controller.pid,provenance == .nativeRealWorker || offline,
              stop == nil || stop === fence else{throw Failure.policy}
        used=true;stop=fence;input?.bindOperationStop(fence);try runtimeCheck()
    }
    func runtimeCheck()throws {
        try stop?.check();guard authorized,gate.lease != nil else{throw Failure.unavailable}
        if let native {
            guard native.diagnostics().monitoringHealthy else{stop?.request(.monitorLost);throw Failure.unavailable}
        }
        guard !polling else{stop?.request(.failed);throw Failure.unavailable};polling=true;defer{polling=false}
        do {for event in input?.drainEvents() ?? [] {try gate.observe(event,now:clock())}}
        catch{stop?.request(.externalInput);throw error}
        try stop?.check()
    }
    func boundary()throws {
        try runtimeCheck();guard let input else{throw Failure.unavailable}
        let sample=input.read()
        for event in input.drainEvents(){try gate.observe(event,now:clock())}
        do{_ = try gate.verifyBoundary(sample,now:clock());try stop?.check()}
        catch{stop?.request(.interference);throw error}
    }
    func packet(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,marker:Int64)throws->CGEvent {
        try runtimeCheck();guard item.pid==targetPID,Int16(exactly:marker) != nil,
              let event=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:point,mouseButton:.left) else{throw Failure.wrongOwner}
        event.flags=move && type == .leftMouseDown ? .maskCommand : []
        event.timestamp=max(1,clock()*1_000_000)
        event.setIntegerValueField(.eventTargetUnixProcessID,value:Int64(targetPID));event.setIntegerValueField(.eventSourceUserData,value:marker)
        event.setIntegerValueField(.mouseEventNumber,value:marker)
        for field in IceBaselinePacket.matchFields.dropFirst(){event.setIntegerValueField(field,value:Int64(item.windowID))}
        event.setIntegerValueField(.mouseEventClickState,value:move ? (type == .leftMouseDown ? 1 : 0) : 1)
        if provenance == .isolatedReplay{event.setIntegerValueField(.eventSourceUnixProcessID,value:Int64(senderPID))}
        guard event.getIntegerValueField(.eventSourceUnixProcessID)==Int64(senderPID)else{throw Failure.wrongOwner};return event
    }
    func register(_ event:CGEvent)throws {
        try boundary();guard let lease=gate.lease,ticket==nil else{throw Failure.used}
        if let native {ticket=try native.registerForReceipt(event,gesture:lease.gesture,expectedEpoch:lease.externalEpoch,expectedContinuity:lease.continuity)}
        else {try replayRegistry!.register(MenuBarListenOnlyInterferenceSource.envelope(event),gesture:lease.gesture,now:clock())}
    }
    func receivedReplay(_ event:CGEvent)throws {
        guard provenance == .isolatedReplay,let lease=gate.lease else{throw Failure.policy}
        let attribution=replayRegistry!.consume(MenuBarListenOnlyInterferenceSource.envelope(event),now:clock())
        guard attribution == .ownGesture(lease.gesture)else{stop?.request(.externalInput);throw Failure.receipt}
    }
    func returned()throws {
        try runtimeCheck()
        if let native,let ticket {guard case .matched=native.receipt(ticket)else{stop?.request(.failed);throw Failure.receipt};self.ticket=nil}
        else {guard replayRegistry?.pending==nil else{stop?.request(.failed);throw Failure.receipt}}
        try boundary()
    }
    func finish() {input?.bindOperationStop(nil);native?.abandonReceipt();gate.finish();authorized=false}
}
