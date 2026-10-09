// Copyright (c) 2026 Ryan.AI. MIT; candidate-only async journal/stop adapter.
import Foundation
import CoreGraphics

final class IceSelectedFence: @unchecked Sendable {
    let stop=MenuBarOperationStop()
    func cancel() { stop.request(.cancelled) }
    func fail() { stop.request(.failed) }
    func check() throws { try stop.check() }
    func perform<T>(_ name:String,_ body:()throws->T)throws->T { try stop.perform(name,body) }
}

@MainActor final class IceSelectedCoordinator {
    let journal:IceSelectedJournal,binding:IceSelectedBinding,contract:IceSelectedContract
    let fence=IceSelectedFence()
    private let clock:()->Double
    private var deadline:Double
    private(set) var retained:IceSelectedRecord?,uncertainProposal:IceSelectedRecord?
    private(set) var durableReturned:IceSelectedRecord?
    private(set) var acknowledgments:[[String:Any]]=[]
    private(set) var active=false,used=false,completed=false,journalOutcomeUncertain=false,clearAdmitted=false
    private var reservation:[IceSelectedRecord.Route]=[],nextRoute=0
    private var currentPacket:IceSelectedPacket?
    private weak var engine:IceBaselineEngine?
    private var menuLease:IceSelectedMenuLease?
    private var interfaceLease:IceSelectedInterfaceLease?
    let relativePlan:IceRelativeReturn.Plan?
    private var liveReturnProof:IceSelectedLiveReturnProof?
    private var quickReturnEvidence:Data?,quickReturnAt:Double?
    init(journal:IceSelectedJournal,binding:IceSelectedBinding,contract:IceSelectedContract = .disabled,
         deadline:Double,relativePlan:IceRelativeReturn.Plan?=nil,clock:@escaping()->Double={ProcessInfo.processInfo.systemUptime}) {
        self.journal=journal;self.binding=binding;self.contract=contract;self.deadline=deadline;self.clock=clock;self.relativePlan=relativePlan
    }
    func constrainDeadline(_ value:Double)throws {guard !used,!active,value.isFinite,value<deadline,value>clock() else{throw IceSelectedFailure.budget};deadline=value}
    var possibleDown:Bool { retained?.needsRelease == true || uncertainProposal?.needsRelease == true }
    func attach(_ engine:IceBaselineEngine) throws { try check();guard self.engine == nil else{throw IceSelectedFailure.phase};self.engine=engine }
    func bindMenuLease(_ lease:IceSelectedMenuLease)throws {
        try check();guard menuLease==nil,lease.owner==binding.owner,lease.nonce==binding.nonce,
            lease.display==binding.display,lease.space==binding.space else{throw IceSelectedFailure.binding}
        menuLease=lease
    }
    func bindInterfaceLease(_ lease:IceSelectedInterfaceLease)throws {
        try check();guard contract == .ordinaryIceInterfaceV9,interfaceLease==nil,menuLease==nil,
              lease.owner==binding.owner,lease.nonce==binding.nonce,lease.display==binding.display,lease.space==binding.space else{throw IceSelectedFailure.binding}
        interfaceLease=lease
    }
    func requireMenuLease(nativeRequired:Bool,restoring:Bool)throws {
        if contract == .ordinaryIceInterfaceV9 {
            guard let interfaceLease else{throw IceSelectedFailure.policy}
            if restoring {try interfaceLease.requireInactive(nativeRequired:nativeRequired)}
            else if nativeRequired && !interfaceLease.nativeObservation {throw IceSelectedFailure.policy}
            return
        }
        guard let menuLease else{if nativeRequired{throw IceSelectedFailure.policy};return}
        if nativeRequired && !menuLease.nativeObservation{throw IceSelectedFailure.policy}
        if restoring{try menuLease.requireClosed(nativeRequired:nativeRequired)}
    }
    func cancel() { fence.cancel();engine?.cancel() }
    func check() throws {
        if Task.isCancelled { fence.cancel() }
        try fence.check()
        guard active,!completed else{throw IceSelectedFailure.stopped}
        guard clock().isFinite,clock()<deadline else{fence.fail();throw IceSelectedFailure.budget}
        guard !journalOutcomeUncertain else{throw IceSelectedFailure.stopped}
    }
    private func io<T:Sendable>(_ body:@escaping @Sendable()throws->T)async throws->T {
        let fence=self.fence
        let worker=Task.detached(priority:.userInitiated,operation:body)
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{fence.cancel();worker.cancel()})
    }
    private func commit(_ next:IceSelectedRecord,terminal:Bool=false)async throws {
        if !terminal { try check() }
        let store=journal,expected=retained
        uncertainProposal=next
        do {
            let saved=try await io{try store.persist(next,replacing:expected)}
            retained=saved;uncertainProposal=nil
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            acknowledgments.append(["revision":saved.revision,"phase":saved.phase.rawValue,"atUptime":clock(),
                "recordSHA256":IceSelectedJournal.hash(try encoder.encode(saved)),
                "unconfirmedDown":saved.needsRelease,"hasPossibleEffect":saved.hasPossibleEffect])
        }catch{journalOutcomeUncertain=true;fence.fail();throw error}
        if !terminal { try check() }
    }
    func run<T>(_ body:()async throws->T)async throws->T {
        let fence=self.fence
        return try await withTaskCancellationHandler(operation:{try await runScoped(body)},onCancel:{fence.cancel()})
    }
    private func runScoped<T>(_ body:()async throws->T)async throws->T {
        // Explicit Ice quiet contract; disabled fails before effects or journal writes.
        guard [.ordinaryIceQuietV1,.ordinaryIceRelativeV2,.ordinaryIceQuickV4,.ordinaryIceInterfaceV9].contains(contract) else{throw IceSelectedFailure.policy}
        guard !used else{throw IceSelectedFailure.stopped};used=true
        try binding.validate();active=true
        defer{active=false;engine=nil}
        do {
            try check();let store=journal
            guard try await io({try store.inspect()}) == nil else{throw IceSelectedFailure.pendingRecovery}
            try check()
            let prepared=IceSelectedRecord(binding:binding,generation:fence.stop.generation,contract:contract,relativePlan:relativePlan)
            try await commit(prepared)
            let value=try await body()
            try check()
            guard let record=retained,record.phase  ==  .returned,!record.needsRelease else{throw IceSelectedFailure.phase}
            durableReturned=record
            // Only dispatch to I/O is admitted here. Already admitted clear may
            // finish after stop; returned proof is durable before this point.
            let clearJob=try fence.perform("journal-clear-dispatch") {
                Task.detached(priority:.userInitiated){try store.clear(record)}
            }
            clearAdmitted=true
            do { try await clearJob.value }
            catch{journalOutcomeUncertain=true;fence.fail();throw error}
            retained=nil;completed=true
            return value
        }catch{
            if Task.isCancelled || error is CancellationError { fence.cancel() } else { fence.fail() }
            engine?.cancel()
            if var next=retained,!journalOutcomeUncertain,next.phase  !=  .returned,next.phase  !=  .stopped {
                next.revision+=1;next.phase = .stopped;next.stopReason=String(describing:error)
                try? await commit(next,terminal:true)
            }
            throw error
        }
    }
    func advance(_ phase:IceSelectedRecord.Phase)async throws {
        try check();guard var next=retained else{throw IceSelectedFailure.phase}
        if contract == .ordinaryIceInterfaceV9 {
            guard phase != .menuClosed else{throw IceSelectedFailure.policy}
            if phase == .interfaceInactive || phase == .restoring {try requireMenuLease(nativeRequired:false,restoring:true)}
        } else if phase == .menuClosed || phase == .restoring { guard let menuLease else { throw IceSelectedFailure.policy };try menuLease.requireClosed() }
        next.revision+=1;next.phase=phase;try await commit(next)
    }
    func beginGesture(down:CGEvent,up:CGEvent)async throws {
        try check();guard var next=retained,!next.needsRelease,
            next.gestures.last == nil || next.gestures.last?.status  ==  .pairedTransportReturned else{throw IceSelectedFailure.unresolvedDown}
        let d=IceSelectedPacket(down),u=IceSelectedPacket(up)
        guard d.pid == Int64(binding.owner.pid),u.pid == d.pid,d.window == Int64(binding.target.id),u.flags == 0,
              d.type == 1,u.type == 2,next.validSource(d),next.validSource(u) else{throw IceSelectedFailure.packet}
        switch next.phase {
        case .moving:
            guard next.gestures.count == 0,d.flags == CGEventFlags.maskCommand.rawValue,d.click == 1,u.click == 0,
                  d.x == 20000,d.y == 20000,u.window == Int64(binding.anchor.id),
                  u.x == binding.anchor.frame.x,u.y == binding.anchor.frame.cg.midY else{throw IceSelectedFailure.packet}
        case .opening:
            guard next.gestures.count == 1,d.flags == 0,d.click == 1,u.click == 1,u.window == d.window,d.x == u.x,d.y == u.y,
                  binding.area.cg.contains(CGPoint(x:d.x,y:d.y)) else{throw IceSelectedFailure.packet}
        case .restoring:
            guard next.gestures.count == 2,d.flags == CGEventFlags.maskCommand.rawValue,d.click == 1,u.click == 0,
                  d.x == 20000,d.y == 20000,u.window == Int64(binding.neighbor.id),
                  u.y == binding.neighbor.frame.cg.midY else{throw IceSelectedFailure.packet}
        default:throw IceSelectedFailure.phase
        }
        next.gestures.append(.init(id:UUID(),down:d,up:u));next.revision+=1
        try await commit(next)
    }
    func prepareRoute(_ event:CGEvent,null:CGEvent?)async throws {
        try check();guard var next=retained,!next.gestures.isEmpty else{throw IceSelectedFailure.packet}
        let packet=IceSelectedPacket(event),index=next.gestures.count-1,gesture=next.gestures[index]
        if packet == gesture.down { guard gesture.status  ==  .registered else{throw IceSelectedFailure.packet};next.gestures[index].status = .downReserved }
        else if packet == gesture.up { guard gesture.status  ==  .downReturned else{throw IceSelectedFailure.packet};next.gestures[index].status = .upReserved }
        else{throw IceSelectedFailure.packet}
        let pid="PID \(binding.owner.pid)"
        var routes:[IceSelectedRecord.Route]=[]
        if let null {
            let p=IceSelectedPacket(null);guard p.type == 0,p.marker == IceBaselinePacket.nullMarker else{throw IceSelectedFailure.packet}
            routes.append(.init(id:UUID(),packet:p,destination:pid))
        }
        routes.append(.init(id:UUID(),packet:packet,destination:"session event tap"))
        if null  !=  nil { routes.append(.init(id:UUID(),packet:packet,destination:pid)) }
        next.gestures[index].routes+=routes;next.revision+=1
        let start=clock();try await commit(next)
        guard clock()-start<0.5 else{fence.fail();throw IceSelectedFailure.budget}
        reservation=routes;nextRoute=0;currentPacket=packet
    }
    func performRoute<T>(_ event:CGEvent,destination:String,_ body:()throws->T)throws->T {
        try check()
        // Fresh menu observation at each actual return dispatch, instead of
        // repeating the same signature/window read in every recursive check.
        if retained?.phase == .restoring {try requireMenuLease(nativeRequired:false,restoring:true)}
        guard nextRoute<reservation.count else{fence.fail();throw IceSelectedFailure.packet}
        let route=reservation[nextRoute]
        guard route.packet == IceSelectedPacket(event),route.destination == destination else{fence.fail();throw IceSelectedFailure.packet}
        nextRoute+=1
        return try fence.perform("native-route:\(route.id)",body)
    }
    func routeReturned(_ event:CGEvent)async throws {
        try check();guard var next=retained,let packet=currentPacket,packet == IceSelectedPacket(event),
              nextRoute == reservation.count,!next.gestures.isEmpty else{throw IceSelectedFailure.packet}
        let i=next.gestures.count-1
        if packet == next.gestures[i].down,next.gestures[i].status  ==  .downReserved { next.gestures[i].status = .downReturned }
        else if packet == next.gestures[i].up,next.gestures[i].status  ==  .upReserved { next.gestures[i].status = .pairedTransportReturned }
        else{throw IceSelectedFailure.packet}
        next.revision+=1;try await commit(next)
        reservation=[];nextRoute=0;currentPacket=nil
    }
    func routeFailed() { fence.fail() }
    func admitReturn(_ proof:IceSelectedLiveReturnProof)throws {
        try check();guard contract == .ordinaryIceRelativeV2,proof.plan == relativePlan else{throw IceSelectedFailure.policy}
        try proof.validate(binding:binding,now:clock());liveReturnProof=proof
    }
    func admitQuickReturn(_ plan:IceSelectedPlan)throws->Data {
        try check();guard [.ordinaryIceQuickV4,.ordinaryIceInterfaceV9].contains(contract),plan.binding == binding else{throw IceSelectedFailure.policy}
        let data=try plan.quickReturnedSample();quickReturnEvidence=data;quickReturnAt=clock();return data
    }
    func confirmReturned(evidence:Data)async throws {
        if [.ordinaryIceQuickV4,.ordinaryIceInterfaceV9].contains(contract) {guard quickReturnEvidence == evidence,let at=quickReturnAt,clock()-at>=0,clock()-at<0.25 else{throw IceSelectedFailure.policy}}

        if contract == .ordinaryIceRelativeV2 {guard let liveReturnProof,liveReturnProof.data==evidence else{throw IceSelectedFailure.policy};try liveReturnProof.validate(binding:binding,now:clock())}
        try check();guard var next=retained,next.phase  ==  .restoring,!next.needsRelease,!next.gestures.isEmpty,
              next.gestures.count == 3,next.gestures.allSatisfy({$0.status  ==  .pairedTransportReturned}),!evidence.isEmpty else{throw IceSelectedFailure.unresolvedDown}
        next.revision+=1;next.phase = .returned;next.returnedEvidenceSHA256=IceSelectedJournal.hash(evidence)
        try await commit(next)
    }
    func performAux<T>(_ name:String,_ body:()throws->T)throws->T { try check();return try fence.perform(name,body) }
    func diagnostics()->[String:Any] {
        func value(_ record:IceSelectedRecord?)->Any {
            guard let record,let data=try? JSONEncoder().encode(record),let json=try? JSONSerialization.jsonObject(with:data) else{return NSNull()}
            return json
        }
        let known=retained ?? durableReturned
        return ["contract":contract.rawValue,"transaction":known?.transaction.uuidString as Any? ?? NSNull(),
         "generation":fence.stop.generation.uuidString,"phase":known?.phase.rawValue as Any? ?? NSNull(),
         "possibleDown":possibleDown,"journalOutcomeUncertain":journalOutcomeUncertain,
         "pendingRecovery":retained  !=  nil || journalOutcomeUncertain,"completed":completed,
         "clearAdmitted":clearAdmitted,"effectsAdmitted":fence.stop.snapshot.effectsAdmitted,
         "stopReason":fence.stop.snapshot.reason?.rawValue as Any? ?? NSNull(),"physicalReleaseProven":false,
         "durableRecord":value(known),"uncertainProposal":value(uncertainProposal),"acknowledgments":acknowledgments]
    }
}
