import AppKit

/// Injected sender, taps, windows, identity and clock only. No live input.
@MainActor enum IceDispatchValidationChecks {
    enum Failure: Error { case assertion(String), injected }
    static var assertions = 0
    static func require(_ ok: Bool, _ label: String) throws {
        assertions += 1; guard ok else { throw Failure.assertion(label) }
    }
    static func run() async throws -> [String: Any] {
        assertions = 0
        var reads = 0, scopeReads = 0, valid = true
        let validation = IceSynchronousDispatchValidation(read: {
            reads += 1; guard valid else { throw Failure.injected }; return (1, UInt(reads))
        }, scope: { scopeReads += 1; return (1, 99) })
        try validation.perform {
            try validation.validateRuntime(); try validation.validateRuntime()
            try require(reads == 1 && scopeReads == 0 && validation.scope().1 == 1, "one complete read in one synchronous dispatch")
            var rejected = false
            do { try validation.perform {} } catch { rejected = true }
            try require(rejected, "nested dispatch cannot reuse the outer sample")
        }
        try validation.perform { try require(reads == 2 && validation.scope().1 == 2, "next dispatch gets new sample") }
        try validation.validateRuntime()
        try require(reads == 3 && validation.scope().1 == 99 && scopeReads == 1, "outside dispatch runtime/scope remain fresh")
        do { try validation.perform { throw Failure.injected } } catch Failure.injected {}
        try validation.validateRuntime()
        try require(reads == 5, "throwing body clears sample")
        valid = false; var rejected = false, bodies = 0
        do { try validation.perform { bodies += 1 } } catch Failure.injected { rejected = true }
        try require(rejected && bodies == 0, "failed runtime validation cannot enter dispatch")
        valid = true
        try validation.perform { try require(reads == 7, "failed validation leaves no reusable sample") }
        let binding = try IceSelectedOfflineChecks.binding(), items = [binding.target,binding.neighbor,binding.anchor]
        let rows: [[String: Any]] = items.map { [kCGWindowNumber as String: $0.id, kCGWindowOwnerPID as String: $0.process.pid, kCGWindowLayer as String: Int(CGWindowLevelForKey(.statusWindow))] }
        try require(IceSelectedPlan.windowOwnershipMatches(rows,items:items), "fresh occupancy rows preserve all three exact owner checks")
        var bad = rows; bad[0][kCGWindowOwnerPID as String] = Int32(444)
        try require(!IceSelectedPlan.windowOwnershipMatches(bad,items:items), "changed target owner rejected")
        try require(!IceSelectedPlan.windowOwnershipMatches(Array(rows.dropLast()),items:items), "missing anchor rejected")
        try require(!IceSelectedPlan.windowOwnershipMatches(rows + [rows[1]],items:items), "duplicate bound window rejected")
        bad = rows; bad[1][kCGWindowLayer as String] = 0
        try require(!IceSelectedPlan.windowOwnershipMatches(bad,items:items), "changed neighbor layer rejected")

        var reports: [[String: Any]] = []
        for name in ["legacyDuplicateReads", "sharedPerPost", "identityChanged", "scopeChanged", "identityChangedWithinPost", "scopeChangedWithinPost", "interfaceReactivated", "cancelledDuringRead", "permissionRevoked", "singleReadPastDeadline"] {
            reports.append(try await pipeline(name))
        }
        return ["passed": true, "assertions": assertions, "scenarios": reports.count + 1,
                "nativePosts": 0, "nativeTaps": 0, "permissionRequests": 0,
                "routeBudgetMS": 50, "provenance": "injectedClockSenderIdentityAndInterface", "reports": reports]
    }
    static func pipeline(_ name: String) async throws -> [String: Any] {
        let b = try IceSelectedOfflineChecks.binding()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("ice-dispatch-validation-replay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = IceSelectedJournal(directory: parent.appendingPathComponent("journal"))
        let server = IceSelectedOfflineChecks.Server(b)
        let coordinator = IceSelectedCoordinator(journal: store, binding: b, contract: .ordinaryIceInterfaceV9, deadline: 190, clock: { server.time })
        var inPost = false, runtimeReads = 0, finalReads = 0, scopeReads = 0, occupancyReads = 0, permission = true, sequence = 0
        let shared = name != "legacyDuplicateReads"
        let validation = IceSynchronousDispatchValidation(read: {
            if coordinator.retained?.phase == .restoring {
                if inPost { runtimeReads += 1 }
                server.time += inPost && name == "singleReadPastDeadline" ? 0.051 : 0.0085
                if inPost && name == "cancelledDuringRead" { coordinator.cancel() }
            }
            guard server.identityValid && server.scopeValid else { throw Failure.injected }
            return (b.display, b.space)
        }, scope: {
            if coordinator.retained?.phase == .restoring { if inPost { scopeReads += 1 }; server.time += 0.0045 }
            return (b.display, server.scopeValid ? b.space : 9)
        }, final: {
            finalReads += 1; server.time += 0.0045
            guard server.identityValid else { throw Failure.injected }
            return (b.display, server.scopeValid ? b.space : 9)
        }, clock: { server.time })
        let native = IceSelectedNative(windows: nil, pid: b.owner.pid,
            identity: { try validation.validateBeforePost() }, offline: true, clock: { server.time },
            sleep: { try await server.pause($0) }, waitReceiptDeadline: { try await server.awaitReceiptDeadline($0) },
            withDispatchValidation: { body in
                inPost = true; defer { inPost = false }
                if shared { try validation.perform(body) } else { try body() }
            }, permission: { permission }, send: { try server.send($0, $1) },
            makeTap: { server.makeTap($0, $1, $2, $3) })
        let effects = IceSelectedOfflineChecks.Effects(native, server, coordinator)
        let lease = IceSelectedInterfaceLease(owner: b.owner, nonce: b.nonce, display: b.display, space: b.space, clock: { server.time }, reader: {
            sequence += 1
            let identityOK = (try? validation.validateRuntime()) != nil
            let scope = validation.scope()
            if coordinator.retained?.phase == .restoring { if inPost { occupancyReads += 1 }; server.time += 0.0005 }
            if inPost && name == "identityChangedWithinPost" { server.identityValid = false }
            if inPost && name == "scopeChangedWithinPost" { server.scopeValid = false }
            return .init(sequence: sequence, at: server.time, owner: b.owner, nonce: b.nonce, display: scope.0, space: scope.1,
                healthy: identityOK, ownerActive: true,
                windows: [.init(id: 100, pid: b.owner.pid, level: 0, onScreen: server.menu)])
        })
        try lease.begin(.init(sequence: 0, at: server.time, owner: b.owner, nonce: b.nonce, display: b.display, space: b.space,
                             healthy: true, ownerActive: false, windows: []))
        server.onSend = {
            if server.sends == 9 {
                if name == "identityChanged" { server.identityValid = false }
                if name == "scopeChanged" { server.scopeValid = false }
                if name == "interfaceReactivated" { server.menu = true }
                if name == "permissionRevoked" { permission = false }
            }
        }
        var caught: Error?
        do {
            try await IceSelectedWorkflow.executeInterface(coordinator: coordinator, makeEffects: { (native, effects) }, makeLease: { lease },
                verifyVisible: {}, verifyReturned: { Data("injected return cannot be admitted as native proof".utf8) },
                afterInterfaceObserved: { server.menu = false })
        } catch { caught = error }
        try require(caught != nil && !coordinator.completed && (try store.inspect())?.phase == .stopped, name + ": model cannot clear live responsibility")
        try require(!lease.nativeObservation, name + ": model never claims native occupancy proof")
        let events = native.events
        let routeBudgets = events.filter { $0["phase"] as? String == "route-start" }.compactMap { row -> Double? in
            guard let start = row["uptime"] as? Double, let end = row["deadlineUptime"] as? Double else { return nil }; return end - start
        }
        try require(!routeBudgets.isEmpty && routeBudgets.allSatisfy { abs($0 - 0.05) < 0.000001 }, name + ": exact 50ms route budget")
        if name == "legacyDuplicateReads" {
            try require(server.sends == 10 && coordinator.possibleDown && native.transportFailure == "timeout", "legacy repeated reads reproduce partial return timeout")
            try require(scopeReads == 3 && runtimeReads == 6, "legacy return attempts repeat runtime plus separate scope reads")
        } else if name == "sharedPerPost" {
            try require(server.sends == 14 && !coordinator.possibleDown && native.transportFailure == nil, "one fresh sample per post completes modeled transport under unchanged budget")
            try require(runtimeReads == 6 && scopeReads == 0 && occupancyReads == 6 && finalReads == 14, "every post gets full ownership sample plus final identity/scope check; six fresh return occupancy reads")
            try require(coordinator.retained?.gestures.allSatisfy { $0.status == .pairedTransportReturned } == true, "all three modeled gestures paired")
        } else if name == "singleReadPastDeadline" {
            try require(server.sends == 8 && coordinator.possibleDown && native.transportFailure == "timeout", "single runtime read past deadline still blocks all return posts")
        } else if name == "cancelledDuringRead" || name == "identityChangedWithinPost" || name == "scopeChangedWithinPost" {
            try require(server.sends == 8 && coordinator.possibleDown, "cancel during fresh runtime read cannot enter return dispatch")
        } else {
            try require(server.sends == 9 && coordinator.possibleDown, name + ": next actual post revalidates and rejects change")
        }
        return ["name": name, "modeledPosts": server.sends, "returnPostRuntimeReads": runtimeReads,
                "finalIdentityScopeChecks": finalReads,
                "returnPostAdditionalScopeReads": scopeReads, "returnPostOccupancyReads": occupancyReads,
                "possibleDownRetained": coordinator.possibleDown, "nativeClosedLoopClaimed": false]
    }
}
