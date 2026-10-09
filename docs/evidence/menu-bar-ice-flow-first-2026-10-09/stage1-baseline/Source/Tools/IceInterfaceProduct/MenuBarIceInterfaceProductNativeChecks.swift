import AppKit

/// Drives only our signed targets and the controller's own cancel action.
/// This checks product launch/publication/cleanup; it never presses Start.
@MainActor enum MenuBarIceInterfaceProductNativeChecks {
    static func run(ordinary: Bool) async throws -> [String: Any] {
        typealias Bridge = MenuBarIceInterfaceProductBridge
        let manifest = try Bridge.manifest()
        let diagnostic = Bridge.root.appendingPathComponent("product-entry-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: diagnostic, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "MacTools 自建产品入口零输入检查"
        NSApp.setActivationPolicy(.regular); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(nanoseconds: 200_000_000)
        var fixture: Process?, fixtureOutput: URL?, selected: MenuBarIceSelectedTarget?
        var controller: Bridge.Launch?, session: URL?
        var assertions = 0
        func require(_ valid: Bool) throws { guard valid else { throw Bridge.Failure.invalid }; assertions += 1 }
        func quitFixture() async throws {
            guard let fixture, let fixtureOutput else { return }
            try Data().write(to: fixtureOutput.appendingPathExtension("quit"), options: .atomic)
            let until = ProcessInfo.processInfo.systemUptime + 5
            while fixture.isRunning, ProcessInfo.processInfo.systemUptime < until { try await Task.sleep(nanoseconds: 100_000_000) }
            try require(!fixture.isRunning && fixture.terminationStatus == 0)
        }
        do {
            if ordinary {
                let process = Process(), nonce = UUID().uuidString
                let output = diagnostic.appendingPathComponent("target.json")
                let (out, err) = try Bridge.files(diagnostic, "target")
                defer { try? out.close(); try? err.close() }
                process.executableURL = Bridge.root.appendingPathComponent("Ice Product Targets.app/Contents/MacOS/IceProductTargets")
                process.arguments = [nonce, output.path]; process.standardOutput = out; process.standardError = err
                try process.run(); fixture = process; fixtureOutput = output
                let proof = try MenuBarProcessSignature.read(process.processIdentifier)
                try require(proof.identifier == "com.ryanai.mactools.producttargets" && proof.team == "58TJ64422P" && proof.sha256 == manifest["productTargetSHA256"] as? String && proof.executable == process.executableURL?.path)
                let until = ProcessInfo.processInfo.systemUptime + 5
                while selected == nil, process.isRunning, ProcessInfo.processInfo.systemUptime < until {
                    if let bytes = try? Data(contentsOf: output), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                       value["nonce"] as? String == nonce, value["pid"] as? Int32 == process.processIdentifier,
                       let at = value["atUnix"] as? Double, (0...1).contains(Date().timeIntervalSince1970 - at),
                       let items = value["items"] as? [[String: Any]], let id = items.first(where: { $0["title"] as? String == "T" })?["windowID"] as? UInt32,
                       let directory = try? MenuBarIceSelectedTarget.readDirectory(), let row = directory.rows.first(where: { $0.id == id && $0.pid == proof.pid }) {
                        selected = try MenuBarIceSelectedTarget.capture(row, from: directory)
                    }
                    if selected == nil { try await Task.sleep(nanoseconds: 100_000_000) }
                }
                guard let selected else { throw Bridge.Failure.unknown(diagnostic) }
                session = try Bridge.prepare(selected)
            } else { session = try Bridge.prepareOwned() }
            guard let session else { throw Bridge.Failure.invalid }
            controller = try await Bridge.launch(session, target: selected, ownedCancelCheck: true)
            guard let controller else { throw Bridge.Failure.invalid }
            let until = ProcessInfo.processInfo.systemUptime + 25
            while controller.isRunning, ProcessInfo.processInfo.systemUptime < until { try await Task.sleep(nanoseconds: 100_000_000) }
            try require(!controller.isRunning)
            let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: session.appendingPathComponent("ready.json"))) as! [String: Any]
            try require(ready["windowVisible"] as? Bool == true && ready["pid"] as? Int32 == controller.proof.pid && ready["nativePosts"] as? Int == 0)
            let prepared = try JSONDecoder().decode(Bridge.Prepared.self, from: Data(contentsOf: session.appendingPathComponent("session.json")))
            let rawResult = try JSONSerialization.jsonObject(with: Data(contentsOf: session.appendingPathComponent("result.json"))) as! [String: Any]
            let result = try Bridge.result(rawResult, nonce: prepared.nonce)
            try require(!result.passed && result.posts == 0 && rawResult["failure"] as? String == "cancelledBeforeStart")
            try require(!FileManager.default.fileExists(atPath: session.appendingPathComponent("action-consumed.json").path))
            let cleanup = try JSONSerialization.jsonObject(with: Data(contentsOf: session.appendingPathComponent("cleanup.json"))) as! [String: Any]
            try require(cleanup["journalPending"] as? Bool == false && cleanup["fixtureExited"] as? Bool == true)
            try await quitFixture()
            _ = try Bridge.preflight()
            let value: [String: Any] = ["passed": true, "ordinarySelectionRoute": ordinary, "session": session.path,
                "assertions": assertions, "nativePosts": 0, "permissionRequests": 0, "startPressed": false,
                "cancelActionInvokedOnOwnControl": true, "controllerPID": controller.proof.pid,
                "directoryFixturePID": fixture?.processIdentifier as Any? ?? NSNull(), "targetOwner": selected.map { $0.owner.identifier } as Any? ?? NSNull(),
                "realMovementClosedLoopClaimed": false]
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: diagnostic.appendingPathComponent("passed.json"), options: .atomic)
            return value
        } catch {
            // Preserve any launched controller and session; do not kill an unknown worker.
            try? await quitFixture()
            let failure: [String: Any] = ["failure": String(describing: error), "session": session?.path as Any? ?? NSNull(),
                "controllerPID": controller?.proof.pid as Any? ?? NSNull(), "assertions": assertions, "nativePosts": 0, "startPressed": false]
            try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]).write(to: diagnostic.appendingPathComponent("failure.json"), options: .atomic)
            throw Bridge.Failure.unknown(diagnostic)
        }
    }
}
