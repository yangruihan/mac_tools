import AppKit

enum MenuBarIceInterfaceProductChecks {
    static func run(_ resultURL: URL) throws -> [String: Any] {
        typealias Bridge = MenuBarIceInterfaceProductBridge
        let owner = MenuBarProcessSignature.Proof(pid: 77, launch: 100, executable: "/tmp/owned-fixture", identifier: "owned.fixture", team: "58TJ64422P", sha256: String(repeating: "a", count: 64), appleAnchor: false)
        let row = MenuBarIceSelectedTarget.Row(id: 99, pid: 77, title: "offline fixture", frame: CGRect(x: 100, y: 0, width: 32, height: 24))
        let directory = MenuBarIceSelectedTarget.Directory(display: 1, space: 2, rows: [row])
        let target = try MenuBarIceSelectedTarget(row: row, directory: directory, owner: owner)
        let nonce = UUID(), sha = String(repeating: "b", count: 64)
        let selected = try MenuBarIceSelectedTarget(row: row, directory: directory, owner: owner, nonce: nonce)
        let session = Bridge.root.appendingPathComponent("session-" + nonce.uuidString, isDirectory: true)
        func prepared(_ selection: MenuBarIceSelectedTarget? = selected, _ own: Bool = false, _ at: Double = 10) -> Bridge.Prepared {
            .init(nonce: nonce, selected: selection, selfOwned: own, controllerSHA256: sha, preparedAtUnix: at)
        }
        var assertions = 0
        func require(_ valid: Bool) throws { guard valid else { throw Bridge.Failure.invalid }; assertions += 1 }
        func reject(_ operation: () throws -> Void) throws {
            var rejected = false
            do { try operation() } catch { rejected = true }
            try require(rejected)
        }
        try Bridge.validate(prepared(), target: target, directory: session, sha: sha, now: 20); assertions += 1
        try reject { try Bridge.validate(prepared(nil, true), target: target, directory: session, sha: sha, now: 20) }
        try reject { try Bridge.validate(prepared(), target: target, directory: session, sha: sha, now: 130) }
        try reject { try Bridge.validate(prepared(), target: target, directory: session, sha: sha, now: 9) }
        try reject { try Bridge.validate(prepared(), target: target, directory: session, sha: sha, now: .nan) }
        try reject { try Bridge.validate(prepared(), target: target, directory: URL(fileURLWithPath: "/tmp/session-" + nonce.uuidString), sha: sha, now: 20) }
        try reject { try Bridge.validate(prepared(), target: target, directory: session, sha: "changed", now: 20) }
        let siblingRow = MenuBarIceSelectedTarget.Row(id: 100, pid: 77, title: row.title, frame: row.frame)
        let sibling = try MenuBarIceSelectedTarget(row: siblingRow, directory: .init(display: 1, space: 2, rows: [siblingRow]), owner: owner, nonce: nonce)
        try reject { try Bridge.validate(prepared(sibling), target: target, directory: session, sha: sha, now: 20) }
        let changedSpace = try MenuBarIceSelectedTarget(row: row, directory: .init(display: 1, space: 3, rows: [row]), owner: owner, nonce: nonce)
        try reject { try Bridge.validate(prepared(changedSpace), target: target, directory: session, sha: sha, now: 20) }
        let movedRow = MenuBarIceSelectedTarget.Row(id: row.id, pid: row.pid, title: row.title, frame: row.frame.offsetBy(dx: 1, dy: 0))
        let moved = try MenuBarIceSelectedTarget(row: movedRow, directory: .init(display: 1, space: 2, rows: [movedRow]), owner: owner, nonce: nonce)
        try reject { try Bridge.validate(prepared(moved), target: target, directory: session, sha: sha, now: 20) }
        let restarted = MenuBarProcessSignature.Proof(pid: owner.pid, launch: 101, executable: owner.executable, identifier: owner.identifier, team: owner.team, sha256: owner.sha256, appleAnchor: false)
        let replaced = try MenuBarIceSelectedTarget(row: row, directory: directory, owner: restarted, nonce: nonce)
        try reject { try Bridge.validate(prepared(replaced), target: target, directory: session, sha: sha, now: 20) }
        let wrongNonce = try MenuBarIceSelectedTarget(row: row, directory: directory, owner: owner)
        try reject { try Bridge.validate(prepared(wrongNonce), target: target, directory: session, sha: sha, now: 20) }
        let bytes = try Data(contentsOf: resultURL)
        guard bytes.count < 2_000_000, let original = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let resultNonce = (original["nonce"] as? String).flatMap(UUID.init(uuidString:)) else { throw Bridge.Failure.invalid }
        let result = try Bridge.result(original, nonce: resultNonce)
        try require(result.passed && result.posts == 14)
        try reject { _ = try Bridge.result(original, nonce: UUID()) }
        var changed = original; changed["menuClosedClaimed"] = true
        try reject { _ = try Bridge.result(changed, nonce: resultNonce) }
        changed = original; changed.removeValue(forKey: "interfaceCompletion")
        try reject { _ = try Bridge.result(changed, nonce: resultNonce) }
        changed = original
        var journal = original["journal"] as! [String: Any]; journal["pendingRecovery"] = true; changed["journal"] = journal
        try reject { _ = try Bridge.result(changed, nonce: resultNonce) }
        changed = original; journal = original["journal"] as! [String: Any]; journal["contract"] = "ordinaryIceQuickV4"; changed["journal"] = journal
        try reject { _ = try Bridge.result(changed, nonce: resultNonce) }
        let stopped: [String: Any] = ["nonce": resultNonce.uuidString, "posts": 8, "realClosedLoopVerified": false]
        try require(try Bridge.result(stopped, nonce: resultNonce).passed == false)
        let ready: [String: Any] = ["nonce": nonce.uuidString, "pid": Int32(77), "windowVisible": true, "nativePosts": 0, "windowNumber": 123]
        try Bridge.validateReady(ready, nonce: nonce, pid: 77); assertions += 1
        try reject { try Bridge.validateReady(ready, nonce: UUID(), pid: 77) }
        try reject { try Bridge.validateReady(ready, nonce: nonce, pid: 78) }
        var badReady = ready; badReady["windowVisible"] = false
        try reject { try Bridge.validateReady(badReady, nonce: nonce, pid: 77) }
        badReady = ready; badReady["nativePosts"] = 1
        try reject { try Bridge.validateReady(badReady, nonce: nonce, pid: 77) }
        let quiet: [String: Any] = ["nonce": nonce.uuidString, "pid": Int32(77),
            "windowVisible": false, "nativePosts": 0, "windowNumber": -1,
            "productionMode": true, "automaticStart": true]
        try Bridge.validateReady(quiet, nonce: nonce, pid: 77, production: true); assertions += 1
        try reject { try Bridge.validateReady(quiet, nonce: nonce, pid: 77) }
        try reject { try Bridge.validateReady(ready, nonce: nonce, pid: 77, production: true) }
        for field in ["nonce", "pid", "windowVisible", "nativePosts", "productionMode", "automaticStart"] {
            var invalid = quiet
            invalid[field] = ["nonce": UUID().uuidString, "pid": Int32(78), "windowVisible": true,
                              "nativePosts": 1, "productionMode": false, "automaticStart": false][field]
            try reject { try Bridge.validateReady(invalid, nonce: nonce, pid: 77, production: true) }
        }
        return ["passed": true, "assertions": assertions, "mousePosts": 0, "windowsOpened": 0,
                "permissionRequests": 0, "realResultReplayedAsDataOnly": true]
    }
}
