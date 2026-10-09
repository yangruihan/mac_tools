// Copyright (c) 2026 Ryan.AI. MIT. Shared ordinary/self/replay closed-loop sequence.
import AppKit

@MainActor enum IceSelectedWorkflow {
    private static func execute(coordinator: IceSelectedCoordinator,
                                makeEffects: () throws -> (IceSelectedNative, any IceBaselineEffects),
                                makeLease: () throws -> IceSelectedMenuLease,
                                verifyVisible: () throws -> Void,
                                verifyReturned: () async throws -> Data,
                                afterMenuOpened: (() async throws -> Void)?,
                                onReturned: ((Data,IceSelectedMenuLease.Closure)throws->Void)? = nil) async throws {
        let b = coordinator.binding
        let target = IceBaselineItem(windowID:b.target.id,pid:b.owner.pid,key:"selected")
        let anchor = IceBaselineItem(windowID:b.anchor.id,pid:b.anchor.process.pid,key:"anchor")
        let neighbor = IceBaselineItem(windowID:b.neighbor.id,pid:b.neighbor.process.pid,key:"original-neighbor")
        try await coordinator.run {
            // The transport factory is inside the durable prepared boundary.
            let (native,effects) = try makeEffects();defer{native.stopMonitoring()}
            try native.bindCandidate(coordinator)
            let engine = IceBaselineEngine(effects);try coordinator.attach(engine)
            try await coordinator.advance(.moving)
            try await engine.move(target,to:.left(anchor))
            try verifyVisible();try await coordinator.advance(.visible)
            let lease = try makeLease()
            if lease.nativeObservation { try lease.beginLive() }
            try coordinator.bindMenuLease(lease);try await coordinator.advance(.opening)
            try await engine.click(target)
            var opened = false
            while true {
                try coordinator.check()
                let state = lease.refresh()
                if state == .open, !opened {
                    opened = true
                    // Only owned self verification supplies a close callback.
                    // Ordinary execution waits for the user's normal closure.
                    try await afterMenuOpened?()
                }
                if state == .closed { break }
                try await effects.pause(0.1)
            }
            guard opened else { throw IceBaselineError.menu }
            try lease.requireClosed(nativeRequired:lease.nativeObservation)
            try await coordinator.advance(.menuClosed);try await coordinator.advance(.restoring)
            // One return only. Same Ice 15s delay; no automatic rehide retry.
            try await effects.pause(15);try coordinator.check()
            try lease.requireClosed(nativeRequired:lease.nativeObservation)
            guard !effects.mouseButtonDown else{throw IceBaselineError.menu}
            try await engine.move(target,to:b.returnOnLeft ? .left(neighbor) : .right(neighbor))
            try lease.requireClosed(nativeRequired:lease.nativeObservation)
            let evidence = try await verifyReturned()
            try lease.requireClosed(nativeRequired:lease.nativeObservation)
            try onReturned?(evidence,lease.confirmation())
            try await coordinator.confirmReturned(evidence:evidence)
        }
    }
    static func executeInterface(coordinator:IceSelectedCoordinator,
                                 makeEffects:()throws->(IceSelectedNative,any IceBaselineEffects),
                                 makeLease:()throws->IceSelectedInterfaceLease,verifyVisible:()throws->Void,
                                 verifyReturned:()async throws->Data,afterInterfaceObserved:(()async throws->Void)?=nil,
                                 onReturned:((Data,IceSelectedInterfaceLease.Evidence)throws->Void)?=nil)async throws {
        let b=coordinator.binding,target=IceBaselineItem(windowID:b.target.id,pid:b.owner.pid,key:"selected")
        let anchor=IceBaselineItem(windowID:b.anchor.id,pid:b.anchor.process.pid,key:"anchor")
        let neighbor=IceBaselineItem(windowID:b.neighbor.id,pid:b.neighbor.process.pid,key:"original-neighbor")
        try await coordinator.run {
            let(native,effects)=try makeEffects();defer{native.stopMonitoring()}
            try native.bindCandidate(coordinator);let engine=IceBaselineEngine(effects,budget:90);try coordinator.attach(engine)
            try await coordinator.advance(.moving);try await engine.move(target,to:.left(anchor))
            try verifyVisible();try await coordinator.advance(.visible)
            let lease=try makeLease();if lease.nativeObservation {try lease.beginLive()}
            try coordinator.bindInterfaceLease(lease);try await coordinator.advance(.opening)
            // Left button is unchanged. No automatic second/right click.
            try await engine.click(target);try await effects.pause(0.1)
            var observed=false
            while true {
                try coordinator.check();let state=lease.refresh()
                if state == .active,!observed {observed=true;try await afterInterfaceObserved?()}
                if state == .inactive {break}
                if lease.diagnostics()["stickyInvalid"] as? Bool == true {throw IceSelectedFailure.binding}
                try await effects.pause(0.1)
            }
            try lease.requireInactive(nativeRequired:lease.nativeObservation)
            try await coordinator.advance(.interfaceInactive)
            // A bounded, cancellable 15s delay, with live occupancy rechecks.
            // Reactivation stops this one attempt rather than silently retrying.
            try await IceInterfaceRehideDelay.wait(seconds:15,clock:{effects.time},check:{
                try coordinator.check();try lease.requireInactive(nativeRequired:lease.nativeObservation)
            },pause:{try await effects.pause($0)})
            try coordinator.check();try lease.requireInactive(nativeRequired:lease.nativeObservation)
            guard !effects.mouseButtonDown else{throw IceBaselineError.menu}
            try await coordinator.advance(.restoring)
            try await engine.move(target,to:b.returnOnLeft ? .left(neighbor) : .right(neighbor))
            try lease.requireInactive(nativeRequired:lease.nativeObservation)
            let evidence=try await verifyReturned();try lease.requireInactive(nativeRequired:lease.nativeObservation)
            try onReturned?(evidence,lease.confirmation());try await coordinator.confirmReturned(evidence:evidence)
        }
    }
    static func run(coordinator: IceSelectedCoordinator, native: IceSelectedNative, effects: any IceBaselineEffects,
                    lease: IceSelectedMenuLease, verifyVisible: () throws -> Void,
                    verifyReturned: () async throws -> Data,
                    afterMenuOpened: (() async throws -> Void)? = nil) async throws {
        try await execute(coordinator:coordinator,makeEffects:{(native,effects)},makeLease:{lease},
                          verifyVisible:verifyVisible,verifyReturned:verifyReturned,afterMenuOpened:afterMenuOpened)
    }
    static func runNative(_ plan: IceSelectedPlan, journal: IceSelectedJournal,
                          onCoordinator: (IceSelectedCoordinator) -> Void,
                          quick:Bool = false,
                          selfOwnedConsumerDelay:Bool = false,
                          onMenuObservation:((String,[String:Any])->Void)?=nil,
                          afterMenuOpened: (() async throws -> Void)? = nil) async throws -> [String:Any] {
        guard quick else{throw IceSelectedFailure.policy}
        try plan.runtime.checkFullSignatures()
        let coordinator = IceSelectedCoordinator(journal:journal,binding:plan.binding,contract:quick ? .ordinaryIceInterfaceV9 : .ordinaryIceRelativeV2,
                                                  deadline:ProcessInfo.processInfo.systemUptime+90,relativePlan:quick ? nil : plan.relative?.plan)
        onCoordinator(coordinator)
        var native: IceSelectedNative?,interfaceLease:IceSelectedInterfaceLease?
        let dispatchValidation=IceSynchronousDispatchValidation(read:{try plan.verifiedRuntimeScope()},scope:{plan.scope()},final:{try plan.finalRuntimeScope()},trace:{facts in
            native?.note("dispatch-runtime-snapshot",facts)
        })
        var returnEvidence:Any=NSNull(),interfaceCompletion:Any=NSNull()
        do {
            try await executeInterface(coordinator:coordinator,makeEffects:{
                let transport = try coordinator.performAux("selected-transport-create") {
                    IceSelectedNative(windows:plan.windows,pid:plan.binding.owner.pid,identity:{try dispatchValidation.validateBeforePost()},withDispatchValidation:{try dispatchValidation.perform($0)})
                }
                if selfOwnedConsumerDelay {
                    guard plan.binding.owner.identifier=="com.ryanai.mactools.nativetargets",
                          plan.binding.owner.executable==IceSelectedSession.packageRoot.appendingPathComponent("Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture").path else{throw IceSelectedFailure.policy}
                    transport.selfOwnedMainConsumerDelay=true
                }
                native = transport;return (transport,transport)
            },makeLease:{
                let b = plan.binding
                let lease=IceSelectedInterfaceLease.live(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,
                    scope:{dispatchValidation.scope()},identity:{(try? dispatchValidation.validateRuntime()) != nil},trace:{kind,facts in
                        var row=facts;row["operationPhase"]=coordinator.retained?.phase.rawValue ?? "none"
                        native?.note("interface-lease-"+kind,row)
                        // Persist/update UI only outside transport-critical return dispatches.
                        if coordinator.retained?.phase != .restoring {onMenuObservation?(kind,row)}
                    },ownership:{plan.validateWindowOwnership($0)},ownershipWindowIDs:[b.target.id,b.neighbor.id,b.anchor.id])
                interfaceLease=lease;return lease
            },verifyVisible:{try plan.verifyVisible()},verifyReturned:{
                // Ice completion is the original neighbor edge, not an absolute-layout audit.
                return try coordinator.admitQuickReturn(plan)
            },afterInterfaceObserved:afterMenuOpened,onReturned:{data,closure in
                returnEvidence=try JSONSerialization.jsonObject(with:data)
                interfaceCompletion=try JSONSerialization.jsonObject(with:JSONEncoder().encode(closure))
            })
            return ["realClosedLoopVerified":true,"posts":native?.posts ?? 0,"events":native?.events ?? [],
                    "interfaceLeaseDiagnostics":interfaceLease?.diagnostics() as Any? ?? NSNull(),"journal":coordinator.diagnostics(),"nonce":plan.binding.nonce.uuidString,
                    "scope":"singleScreenExactSelectedIcon","guarantee":quick ? "iceOriginalNeighborEdge" : "originalRelativeSlot","relativeReturnVerified":!quick,"fullQueueRequired":!quick,"icePositionVerified":quick,"strictAbsoluteClosedLoopVerified":NSNull(),"returnEvidence":returnEvidence,"interfaceCompletion":interfaceCompletion,"menuClosedClaimed":false,"wholeRunBudgetSeconds":90,"interfaceEndAction":afterMenuOpened == nil ? "userClosesOrDefocusesInterface" : "selfOwnedFixtureVerificationOnly"]
        } catch {
            native?.stopMonitoring()
            return ["realClosedLoopVerified":false,"failure":String(describing:error),"transportFailure":native?.transportFailure as Any? ?? NSNull(),"posts":native?.posts ?? 0,"events":native?.events ?? [],
                    "interfaceLeaseDiagnostics":interfaceLease?.diagnostics() as Any? ?? NSNull(),"journal":coordinator.diagnostics(),"nonce":plan.binding.nonce.uuidString,"scope":"singleScreenExactSelectedIcon"]
        }
    }
}
