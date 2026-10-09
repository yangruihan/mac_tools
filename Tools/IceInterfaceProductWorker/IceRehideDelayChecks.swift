import Foundation

@MainActor enum IceRehideDelayChecks {
    enum Failure: Error { case assertion, inactiveRevoked }
    static func run() async throws -> [String: Any] {
        var assertions = 0
        func require(_ condition: Bool) throws { guard condition else { throw Failure.assertion }; assertions += 1 }
        var time = 100.0, pauses: [Double] = [], checks = 0
        try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1; time = 115.001 }, pause: { pauses.append($0) })
        try require(time >= 115 && pauses.isEmpty && checks == 1)
        // Reproduce the exact old loop's check-to-sleep boundary without executing
        // its fatal UInt64 conversion. The captured live crash proves that trap.
        try require(min(0.1, 115 - time) < 0)
        time = 100; pauses = []; checks = 0
        try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1 }, pause: { pauses.append($0); time += $0 })
        try require(time >= 115)
        try require(pauses.allSatisfy { $0 > 0 && $0 <= 0.1 })
        try require(abs(pauses.reduce(0, +) - 15) < 0.000001 && checks == pauses.count)
        time = 100; pauses = []; checks = 0
        var rejected = false
        do {
            try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1; throw Failure.inactiveRevoked }, pause: { pauses.append($0) })
        } catch Failure.inactiveRevoked { rejected = true }
        try require(rejected && pauses.isEmpty && checks == 1)
        time = 100; pauses = []
        let cancelled = Task { @MainActor in
            try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: {}, pause: { pauses.append($0) })
        }
        cancelled.cancel()
        rejected = false
        do { try await cancelled.value } catch is CancellationError { rejected = true }
        try require(rejected && pauses.isEmpty)
        var holdReports: [[String:Any]] = []
        for seconds in [32.0, 76.0] {
            let report = try await heldInterface(seconds)
            holdReports.append(report)
            fputs("interface-hold-replay: " + String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)+"\n",stderr)
            try require(report["modeledPosts"] as? Int == (seconds == 32 ? 14 : 8))
            try require(report["failure"] as? String == (seconds == 32 ? "policy" : "budget"))
            try require(report["nativeClosedLoopClaimed"] as? Bool == false)
            try require(report["routeBudgetsPreserved"] as? Bool == true)
        }
        return ["passed": true, "assertions": assertions, "nativePosts": 0,
                "deadlineCrossingInOccupancyCheckCovered": true, "delaySeconds": 15, "holdReports":holdReports]
    }

    static func heldInterface(_ seconds:Double) async throws -> [String:Any] {
        let b=try IceSelectedOfflineChecks.binding()
        let parent=FileManager.default.temporaryDirectory.appendingPathComponent("ice-held-interface-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:parent)}
        let store=IceSelectedJournal(directory:parent.appendingPathComponent("journal")),server=IceSelectedOfflineChecks.Server(b)
        let coordinator=IceSelectedCoordinator(journal:store,binding:b,contract:.ordinaryIceInterfaceV9,deadline:190,clock:{server.time})
        let native=IceSelectedNative(windows:nil,pid:b.owner.pid,identity:{},offline:true,clock:{server.time},sleep:{try await server.pause($0)},waitReceiptDeadline:{try await server.awaitReceiptDeadline($0)},permission:{true},send:{try server.send($0,$1)},makeTap:{server.makeTap($0,$1,$2,$3)})
        let effects=IceSelectedOfflineChecks.Effects(native,server,coordinator)
        var sequence=0
        let lease=IceSelectedInterfaceLease(owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,clock:{server.time},reader:{
            sequence+=1
            return .init(sequence:sequence,at:server.time,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:true,ownerActive:true,windows:[.init(id:100,pid:b.owner.pid,level:0,onScreen:server.menu)])
        })
        try lease.begin(.init(sequence:0,at:server.time,owner:b.owner,nonce:b.nonce,display:b.display,space:b.space,healthy:true,ownerActive:false,windows:[]))
        var failure="none"
        do {
            try await IceSelectedWorkflow.executeInterface(coordinator:coordinator,makeEffects:{(native,effects)},makeLease:{lease},verifyVisible:{},verifyReturned:{Data("injected result is not native proof".utf8)},afterInterfaceObserved:{
                try await server.pause(seconds);server.menu=false
            })
        }catch{failure=String(describing:error)}
        let budgets=native.events.filter{$0["phase"] as? String == "route-start"}.map{($0["deadlineUptime"] as! Double)-($0["uptime"] as! Double)}
        guard (try store.inspect())?.phase == .stopped,!coordinator.completed,!lease.nativeObservation else{throw Failure.assertion}
        return ["heldInterfaceSeconds":seconds,"modeledPosts":server.sends,"failure":failure,"nativeClosedLoopClaimed":false,"nativePosts":0,"routeBudgetsPreserved":!budgets.isEmpty && budgets.allSatisfy{abs($0-0.05)<0.000001},"elapsedSeconds":server.time-100]
    }
}
