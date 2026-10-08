import Foundation

@MainActor enum IceBaselineSessionLifetimeTests {
    enum Failure: Error { case assertion(String) }
    static func run() throws {
        var count = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw Failure.assertion(label) }; count += 1
        }
        func rejected(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch { return true }
        }
        var s = IceBaselineSessionLifetime(now: 0)
        s.tick(now: 9.999); try check(s.phase == .initializing, "initialization before boundary")
        s.tick(now: 10); try check(s.phase == .cleaning && s.deadline == 25, "initialization timeout retains cleanup")
        try check(rejected { try s.accept(.ready, request: "r", now: 10) }, "late ready cannot reopen timeout")
        s.tick(now: 25); try check(s.phase == .finished, "initialization bounded exit")
        s = IceBaselineSessionLifetime(now: 0)
        try s.accept(.ready, request: "r", now: 1)
        try check(s.deadline == 121, "120s ready budget starts after acknowledged setup")
        try check(rejected { try s.accept(.ready, request: "r", now: 20) } && s.deadline == 121, "duplicate ready cannot renew")
        try check(rejected { try s.accept(.ready, request: "r2", now: 20) }, "new ready request cannot renew")
        try s.accept(.begin, request: "b", now: 114.4)
        try check(s.deadline == 164.4 && s.allowsEffects(operation: "b", now: 129.4), "late click reserves full operation and rehide")
        try check(!s.allowsEffects(operation: "other", now: 129.4), "operation token binding")
        try check(rejected { try s.accept(.begin, request: "b2", now: 115) }, "second start refused")
        let fresh = s.snapshot(now: 129.4)
        try check(IceBaselineSessionLifetime.permitsEffects(fresh, operation: "b", now: 129.9), "fresh publication admitted")
        try check(!IceBaselineSessionLifetime.permitsEffects(fresh, operation: "b", now: 130.4001), "stale publication refused")
        try check(!IceBaselineSessionLifetime.permitsEffects(fresh, operation: "b", now: 129.3), "future publication refused")
        try check(!IceBaselineSessionLifetime.permitsEffects(fresh, operation: "other", now: 129.9), "published token mismatch refused")
        try check(!IceBaselineSessionLifetime.permitsEffects(fresh, operation: "b", now: .nan), "nonfinite time refused")
        try check(!s.allowsEffects(operation: "b", now: 164.4), "effects cease at exact operation boundary")
        s.tick(now: 164.4)
        try check(s.phase == .cleaning && s.deadline == 179.4, "operation timeout retains bounded cleanup publication")
        try check(rejected { try s.accept(.begin, request: "late", now: 165) }, "expired operation cannot restart")
        try s.accept(.terminal, request: "t", now: 170)
        try check(s.deadline == 179.4, "terminal does not renew cleanup")
        try s.accept(.cancel, request: "c", now: 171)
        try check(s.deadline == 179.4 && !s.allowsEffects(operation: "b", now: 171), "cancel never extends cleanup or restores permission")
        s.tick(now: 179.4); try check(s.phase == .finished, "operation bounded exit")
        try check(rejected { try s.accept(.terminal, request: "t2", now: 180) }, "finished lifetime sticky")
        s = IceBaselineSessionLifetime(now: 0); try s.accept(.ready, request: "r", now: 1)
        try check(rejected { try s.accept(.begin, request: "b", now: 121) } && s.phase == .cleaning, "exact ready deadline rejects late click")
        s = IceBaselineSessionLifetime(now: 0); try s.accept(.cancel, request: "c", now: 2)
        try check(rejected { try s.accept(.ready, request: "r", now: 3) } && s.deadline == 17, "cancel before start cannot rearm")
        s = IceBaselineSessionLifetime(now: 0); try s.accept(.ready, request: "r", now: 9.9)
        try s.accept(.begin, request: "b", now: 129.8)
        try check(s.deadline == 179.8, "latest admitted start reserves operation and cleanup below hard cap")
        s.tick(now: 1000); try check(s.phase == .finished && s.deadline == 200, "hard cap survives delayed timer")
        s = IceBaselineSessionLifetime(now: 0); try s.accept(.terminal, request: "quit", now: 2)
        s.tick(now: 17); try check(s.phase == .finished, "quit without start has bounded exit")
        let id = UUID().uuidString
        var r: [String: Any] = ["nonce":"n","fixturePID":Int32(123),"controllerPID":Int32(456),"request":id,"action":"begin","atUnix":100.0]
        let request = try IceBaselineSessionLifetime.Request(r, nonce: "n", fixturePID: 123, now: 100.5)
        try check(request.id == id && request.controllerPID == 456 && request.action == .begin, "RPC envelope decoded")
        try check(rejected { _ = try IceBaselineSessionLifetime.Request(r, nonce: "other", fixturePID: 123, now: 100.5) }, "RPC nonce mismatch")
        try check(rejected { _ = try IceBaselineSessionLifetime.Request(r, nonce: "n", fixturePID: 124, now: 100.5) }, "RPC fixture PID mismatch")
        try check(rejected { _ = try IceBaselineSessionLifetime.Request(r, nonce: "n", fixturePID: 123, now: 101.01) }, "RPC stale timestamp")
        r["controllerPID"] = -1
        try check(rejected { _ = try IceBaselineSessionLifetime.Request(r, nonce: "n", fixturePID: 123, now: 100.5) }, "RPC invalid controller PID")
        // Execute the controller's actual writer without creating NSApplication/UI.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ice-result-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = IceBaselineController(directory: directory, nonce: UUID().uuidString)
        controller.used = true
        controller.writeIdle(reason: "cancelAfterStart")
        let file = directory.appendingPathComponent("result.json")
        try check(!FileManager.default.fileExists(atPath: file.path), "cancel after start cannot fabricate zero-post idle result")
        let completed = Data("{\"realClosedLoopVerified\":true,\"posts\":14}".utf8)
        try completed.write(to: file)
        controller.writeIdle(reason: "cancelAfterCompletion")
        try check(try Data(contentsOf: file) == completed, "cancel after completion retains original result bytes")
        try FileManager.default.removeItem(at: file)
        let idle = IceBaselineController(directory: directory, nonce: UUID().uuidString)
        idle.writeIdle(reason: "cancelBeforeStart")
        let original = try Data(contentsOf: file)
        idle.writeIdle(reason: "secondCancel")
        try check(try Data(contentsOf: file) == original, "idle terminal is written once")
        print("\(count) bounded lifetime/RPC checks; late start, cancellation, freshness, timeout and exit; native effects = 0")
    }
}
