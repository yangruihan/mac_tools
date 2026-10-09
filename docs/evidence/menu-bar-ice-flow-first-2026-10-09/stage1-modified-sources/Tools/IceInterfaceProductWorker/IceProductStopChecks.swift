// Native Cocoa controls with isolated historical replay journals. No sender.
import AppKit

@MainActor enum IceProductStopChecks {
    static func run() async throws -> [String: Any] {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let parent = IceSelectedSession.root.appendingPathComponent("product-stop-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var assertions = 0, shutdowns = 0, controls: [IceSelectedController] = []
        defer { controls.forEach { $0.window?.orderOut(nil) } }
        func require(_ value: Bool) throws { guard value else { throw IceSelectedFailure.policy }; assertions += 1 }
        func make(_ directory: URL, _ journal: IceSelectedJournal, _ binding: IceSelectedBinding) throws -> IceSelectedController {
            let p = binding.owner
            let proof = MenuBarProcessSignature.Proof(pid: p.pid, launch: p.launch, executable: p.executable, identifier: p.identifier, team: p.team, sha256: p.sha256, appleAnchor: false)
            let row = MenuBarIceSelectedTarget.Row(id: binding.target.id, pid: p.pid, title: "historical replay only", frame: binding.target.frame.cg)
            let selected = try MenuBarIceSelectedTarget(row: row, directory: .init(display: binding.display, space: UInt64(binding.space), rows: [row]), owner: proof, nonce: binding.nonce)
            let prepared = IceSelectedSession.Prepared(nonce: binding.nonce, selected: selected, selfOwned: false, controllerSHA256: binding.controller.sha256, preparedAtUnix: Date().timeIntervalSince1970)
            let c = IceSelectedController(directory: directory, prepared: prepared, autoOwned: false, journal: journal, shutdownApplication: { shutdowns += 1 })
            c.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
            c.window.isReleasedWhenClosed = false
            c.status = NSTextField(labelWithString: "replay")
            c.start = NSButton(title: "开始单轮", target: c, action: #selector(IceSelectedController.begin))
            c.window.contentView?.addSubview(c.start); controls.append(c)
            return c
        }
        for (name, expectedNeedsRelease, posts) in [("menu-bar-ice-v9-interface-self-window-stop-2026-10-09", true, 3), ("menu-bar-ice-v9-interface-self-window-scope-stop-2026-10-09", false, 8)] {
            let replay = parent.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: replay, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let source = IceSelectedSession.packageRoot.appendingPathComponent("Fixtures/"+name+".json")
            let bytes = try Data(contentsOf: source)
            let ledger = replay.appendingPathComponent("ledger")
            try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let file = ledger.appendingPathComponent("ice-selected-relative-v2.json")
            try bytes.write(to: file); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let journal = IceSelectedJournal(directory: ledger)
            guard let record = try journal.inspect() else { throw IceSelectedFailure.binding }
            try require(record.needsRelease == expectedNeedsRelease && record.contract == .ordinaryIceInterfaceV9)
            let c = try make(replay, journal, record.binding)
            await c.finish(["realClosedLoopVerified": false, "posts": posts, "failure": "historicalReplay"])
            try require(c.recoveryPending && c.start.title == "本轮已结束" && !c.start.isEnabled)
            c.start.performClick(nil); c.verifyManualRecovery()
            try await Task.sleep(nanoseconds: 100_000_000)
            try require(!c.used && !c.start.isEnabled && (try Data(contentsOf: file)) == bytes)
            try require(!FileManager.default.fileExists(atPath: replay.appendingPathComponent("manual-recovery.json").path))
            c.stop(); try await Task.sleep(nanoseconds: 100_000_000)
            try require(c.quitting && (try journal.inspect()) == record && (try Data(contentsOf: file)) == bytes)
            let cleanup = try JSONSerialization.jsonObject(with: Data(contentsOf: replay.appendingPathComponent("cleanup.json"))) as! [String: Any]
            try require(cleanup["journalPending"] as? Bool == true)
        }
        let beforeStart = parent.appendingPathComponent("cancel-before-start")
        try FileManager.default.createDirectory(at: beforeStart, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let empty = IceSelectedJournal(directory: beforeStart.appendingPathComponent("ledger"))
        let c = try make(beforeStart, empty, IceSelectedOfflineChecks.binding())
        c.stop(); try await Task.sleep(nanoseconds: 100_000_000)
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: beforeStart.appendingPathComponent("result.json"))) as! [String: Any]
        try require(result["nonce"] as? String == c.prepared.nonce.uuidString && result["posts"] as? Int == 0 && result["failure"] as? String == "cancelledBeforeStart")
        try require(c.cancelled && c.quitting && !c.used && (try empty.inspect()) == nil && shutdowns == 3)
        try require(try IceSelectedSession.journal.inspect() == nil)
        return ["scenarios": 3, "assertions": assertions, "nativePosts": 0, "AXActions": 0, "permissionRequests": 0,
                "isolatedHistoricalReplayJournals": true, "realManualRecoveryClaimed": false, "evidenceDirectory": parent.path]
    }
}
