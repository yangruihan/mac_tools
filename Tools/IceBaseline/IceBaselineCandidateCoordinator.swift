// Copyright (c) 2026 Ryan.AI. MIT; candidate-only async journal/stop adapter.
import Foundation
import CoreGraphics

final class IceCandidateFence: @unchecked Sendable {
    let stop=MenuBarOperationStop()
    func cancel() { stop.request(.cancelled) }
    func fail() { stop.request(.failed) }
    func check() throws { try stop.check() }
    func perform<T>(_ name:String,_ body:()throws->T)throws->T { try stop.perform(name,body) }
}

@MainActor final class IceBaselineCandidateCoordinator {
    let journal:IceBaselineCandidateJournal,binding:IceCandidateBinding,contract:IceCandidateContract
    let fence=IceCandidateFence()
    private let clock:()->Double
    private var deadline:Double
    private(set) var retained:IceCandidateRecord?,uncertainProposal:IceCandidateRecord?
    private(set) var durableReturned:IceCandidateRecord?
    private(set) var acknowledgments:[[String:Any]]=[]
    private(set) var active=false,used=false,completed=false,journalOutcomeUncertain=false,clearAdmitted=false
    private var reservation:[IceCandidateRecord.Route]=[],nextRoute=0
    private var currentPacket:IceCandidatePacket?
    private weak var engine:IceBaselineEngine?
    private var menuLease:IceBaselineMenuLease?
    private(set)var anyBridge:IceBaselineANYBridge?
    func bindANY(_ bridge:IceBaselineANYBridge,offline:Bool)throws {
        guard contract == .isolatedOwnedANYV1,!used,!active,anyBridge==nil else{throw IceCandidateFailure.policy}
        try bridge.bind(fence.stop,binding:binding,offline:offline);anyBridge=bridge
    }
    init(journal:IceBaselineCandidateJournal,binding:IceCandidateBinding,contract:IceCandidateContract = .disabled,
         deadline:Double,clock:@escaping()->Double={ProcessInfo.processInfo.systemUptime}) {
        self.journal=journal;self.binding=binding;self.contract=contract;self.deadline=deadline;self.clock=clock
    }
    func constrainDeadline(_ value:Double)throws {guard !used,!active,value.isFinite,value<deadline,value>clock() else{throw IceCandidateFailure.budget};deadline=value}
    var possibleDown:Bool { retained?.needsRelease == true || uncertainProposal?.needsRelease == true }
    func attach(_ engine:IceBaselineEngine) throws { try check();guard self.engine == nil else{throw IceCandidateFailure.phase};self.engine=engine }
    func bindMenuLease(_ lease:IceBaselineMenuLease)throws {
        try check();guard menuLease==nil,lease.owner==binding.fixture,lease.nonce==binding.nonce,
            lease.display==binding.display,lease.space==binding.space else{throw IceCandidateFailure.binding}
        menuLease=lease
    }
    func requireMenuLease(nativeRequired:Bool,restoring:Bool)throws {
        guard let menuLease else{if nativeRequired{throw IceCandidateFailure.policy};return}
        if nativeRequired && !menuLease.nativeObservation{throw IceCandidateFailure.policy}
        if restoring{try menuLease.requireClosed(nativeRequired:nativeRequired)}
    }
    func cancel() { fence.cancel();engine?.cancel() }
    func check() throws {
        if Task.isCancelled { fence.cancel() }
        try fence.check()
        try anyBridge?.runtimeCheck()
        guard active,!completed else{throw IceCandidateFailure.stopped}
        guard clock().isFinite,clock()<deadline else{fence.fail();throw IceCandidateFailure.budget}
        guard !journalOutcomeUncertain else{throw IceCandidateFailure.stopped}
    }
    private func io<T:Sendable>(_ body:@escaping @Sendable()throws->T)async throws->T {
        let fence=self.fence
        let worker=Task.detached(priority:.userInitiated,operation:body)
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{fence.cancel();worker.cancel()})
    }
    private func commit(_ next:IceCandidateRecord,terminal:Bool=false)async throws {
        if !terminal { try check() }
        let store=journal,expected=retained
        uncertainProposal=next
        do {
            let saved=try await io{try store.persist(next,replacing:expected)}
            retained=saved;uncertainProposal=nil
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            acknowledgments.append(["revision":saved.revision,"phase":saved.phase.rawValue,"atUptime":clock(),
                "recordSHA256":IceBaselineCandidateJournal.hash(try encoder.encode(saved)),
                "unconfirmedDown":saved.needsRelease,"hasPossibleEffect":saved.hasPossibleEffect])
        }catch{journalOutcomeUncertain=true;fence.fail();throw error}
        if !terminal { try check() }
    }
    func run<T>(_ body:()async throws->T)async throws->T {
        let fence=self.fence
        return try await withTaskCancellationHandler(operation:{try await runScoped(body)},onCancel:{fence.cancel()})
    }
    private func runScoped<T>(_ body:()async throws->T)async throws->T {
        // Product ANY and disabled always fail before journal or native effects.
        guard contract == .isolatedOwnedQuietV1 || (contract == .isolatedOwnedANYV1 && anyBridge != nil) else{throw IceCandidateFailure.policy}
        guard !used else{throw IceCandidateFailure.stopped};used=true
        try binding.validate();active=true
        defer{active=false;engine=nil;anyBridge?.finish()}
        do {
            try check();let store=journal
            guard try await io({try store.inspect()}) == nil else{throw IceCandidateFailure.pendingRecovery}
            try check()
            var prepared=IceCandidateRecord(binding:binding,generation:fence.stop.generation,contract:contract)
            if let anyBridge{prepared.packetSource = .init(senderPID:anyBridge.senderPID,state:Int64(anyBridge.source.sourceStateID.rawValue));try anyBridge.boundary()}
            try await commit(prepared)
            let value=try await body()
            try check()
            guard let record=retained,record.phase  ==  .returned,!record.needsRelease else{throw IceCandidateFailure.phase}
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
    func advance(_ phase:IceCandidateRecord.Phase)async throws {
        try check();guard var next=retained else{throw IceCandidateFailure.phase}
        if phase == .menuClosed || phase == .restoring,let menuLease{try menuLease.requireClosed()}
        next.revision+=1;next.phase=phase;try await commit(next)
    }
    func beginGesture(down:CGEvent,up:CGEvent)async throws {
        try check();guard var next=retained,!next.needsRelease,
            next.gestures.last == nil || next.gestures.last?.status  ==  .pairedTransportReturned else{throw IceCandidateFailure.unresolvedDown}
        let d=IceCandidatePacket(down),u=IceCandidatePacket(up)
        guard d.pid == Int64(binding.fixture.pid),u.pid == d.pid,d.window == Int64(binding.target.id),u.flags == 0,
              d.type == 1,u.type == 2,next.validSource(d),next.validSource(u) else{throw IceCandidateFailure.packet}
        switch next.phase {
        case .moving:
            guard next.gestures.count == 0,d.flags == CGEventFlags.maskCommand.rawValue,d.click == 1,u.click == 0,
                  d.x == 20000,d.y == 20000,u.window == Int64(binding.anchor.id),
                  u.x == binding.anchor.frame.x,u.y == binding.anchor.frame.cg.midY else{throw IceCandidateFailure.packet}
        case .opening:
            guard next.gestures.count == 1,d.flags == 0,d.click == 1,u.click == 1,u.window == d.window,d.x == u.x,d.y == u.y,
                  binding.area.cg.contains(CGPoint(x:d.x,y:d.y)) else{throw IceCandidateFailure.packet}
        case .restoring:
            guard next.gestures.count == 2,d.flags == CGEventFlags.maskCommand.rawValue,d.click == 1,u.click == 0,
                  d.x == 20000,d.y == 20000,u.window == Int64(binding.neighbor.id),
                  u.y == binding.neighbor.frame.cg.midY else{throw IceCandidateFailure.packet}
        default:throw IceCandidateFailure.phase
        }
        next.gestures.append(.init(id:UUID(),down:d,up:u));next.revision+=1
        try await commit(next)
    }
    func prepareRoute(_ event:CGEvent,null:CGEvent?)async throws {
        try check();guard var next=retained,!next.gestures.isEmpty else{throw IceCandidateFailure.packet}
        let packet=IceCandidatePacket(event),index=next.gestures.count-1,gesture=next.gestures[index]
        if packet == gesture.down { guard gesture.status  ==  .registered else{throw IceCandidateFailure.packet};next.gestures[index].status = .downReserved }
        else if packet == gesture.up { guard gesture.status  ==  .downReturned else{throw IceCandidateFailure.packet};next.gestures[index].status = .upReserved }
        else{throw IceCandidateFailure.packet}
        let pid="PID \(binding.fixture.pid)"
        var routes:[IceCandidateRecord.Route]=[]
        if let null {
            let p=IceCandidatePacket(null);guard p.type == 0,p.marker == IceBaselinePacket.nullMarker else{throw IceCandidateFailure.packet}
            routes.append(.init(id:UUID(),packet:p,destination:pid))
        }
        routes.append(.init(id:UUID(),packet:packet,destination:"session event tap"))
        if null  !=  nil { routes.append(.init(id:UUID(),packet:packet,destination:pid)) }
        next.gestures[index].routes+=routes;next.revision+=1
        let start=clock();try await commit(next)
        guard clock()-start<0.5 else{fence.fail();throw IceCandidateFailure.budget}
        try anyBridge?.register(event)
        reservation=routes;nextRoute=0;currentPacket=packet
    }
    func performRoute<T>(_ event:CGEvent,destination:String,_ body:()throws->T)throws->T {
        try check()
        guard nextRoute<reservation.count else{fence.fail();throw IceCandidateFailure.packet}
        let route=reservation[nextRoute]
        guard route.packet == IceCandidatePacket(event),route.destination == destination else{fence.fail();throw IceCandidateFailure.packet}
        nextRoute+=1
        return try fence.perform("native-route:\(route.id)",body)
    }
    func routeReturned(_ event:CGEvent)async throws {
        try anyBridge?.returned()
        try check();guard var next=retained,let packet=currentPacket,packet == IceCandidatePacket(event),
              nextRoute == reservation.count,!next.gestures.isEmpty else{throw IceCandidateFailure.packet}
        let i=next.gestures.count-1
        if packet == next.gestures[i].down,next.gestures[i].status  ==  .downReserved { next.gestures[i].status = .downReturned }
        else if packet == next.gestures[i].up,next.gestures[i].status  ==  .upReserved { next.gestures[i].status = .pairedTransportReturned }
        else{throw IceCandidateFailure.packet}
        next.revision+=1;try await commit(next)
        reservation=[];nextRoute=0;currentPacket=nil
    }
    func routeFailed() { fence.fail() }
    func confirmReturned(evidence:Data)async throws {
        try check();guard var next=retained,next.phase  ==  .restoring,!next.needsRelease,!next.gestures.isEmpty,
              next.gestures.count == 3,next.gestures.allSatisfy({$0.status  ==  .pairedTransportReturned}),!evidence.isEmpty else{throw IceCandidateFailure.unresolvedDown}
        next.revision+=1;next.phase = .returned;next.returnedEvidenceSHA256=IceBaselineCandidateJournal.hash(evidence)
        try await commit(next)
    }
    func performAux<T>(_ name:String,_ body:()throws->T)throws->T { try check();return try fence.perform(name,body) }
    func diagnostics()->[String:Any] {
        func value(_ record:IceCandidateRecord?)->Any {
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
