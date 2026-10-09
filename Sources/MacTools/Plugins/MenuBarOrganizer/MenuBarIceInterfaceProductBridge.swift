#if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
// Copyright (c) 2026 Ryan.AI. MIT. Product adapter; no mouse sender.
import AppKit
import CryptoKit

enum MenuBarIceInterfaceProductBridge {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacTools/IceInterfaceCandidate", isDirectory: true)
    static let packageRoot = Bundle.main.resourceURL!.appendingPathComponent("IceWorker",isDirectory:true)
    static let controller = packageRoot.appendingPathComponent("Ice Selected Controller.app/Contents/MacOS/IceSelectedController")
    static let revision = "ordinary-Ice-product-stage1"
    struct Prepared: Codable {
        let nonce: UUID, selected: MenuBarIceSelectedTarget?, selfOwned: Bool, controllerSHA256: String
        let preparedAtUnix: Double
    }
    struct Launch {
        let application: NSRunningApplication, proof: MenuBarProcessSignature.Proof
        var isRunning: Bool { !application.isTerminated }
    }
    enum Failure: LocalizedError {
        case invalid, unknown(URL), targetChanged, startup(URL, String)
        var errorDescription: String? {
            switch self {
            case .invalid: return "v9 组件或会话无法核实，请保留记录。"
            case .unknown(let url): return "组件启动结果未知，不要重复启动。诊断：\(url.path)"
            case .targetChanged: return "选定图标、所属进程或桌面已改变；本轮没有启动移动。"
            case .startup(let url, let reason): return "控制窗口准备失败（\(reason)）。本轮未开始；记录：\(url.path)"
            }
        }
    }
    static func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    static func manifest() throws -> [String: Any] {
        guard ["com.ryanai.mactools.iceinterfacecandidate","com.ryanai.mactools"].contains(Bundle.main.bundleIdentifier ?? ""),
              let url = Bundle.main.url(forResource: "ice-interface-bridge", withExtension: "json"),
              let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              receipt["manifestSHA256"] as? String == (try hash(packageRoot.appendingPathComponent("prepared-build.json"))),
              let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: packageRoot.appendingPathComponent("prepared-build.json"))) as? [String: Any],
              manifest["revision"] as? String == revision,
              manifest["controllerSHA256"] as? String == (try hash(controller)),
              manifest["fixtureSHA256"] as? String == (try hash(packageRoot.appendingPathComponent("Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture"))),
              let sources = manifest["sources"] as? [String: String], sources.count > 50 else { throw Failure.invalid }
        let sourceRoot=packageRoot.appendingPathComponent("Source",isDirectory:true)
        for (path,expected) in sources {
            let file=sourceRoot.appendingPathComponent(path).resolvingSymlinksInPath()
            guard !path.hasPrefix("/"),!path.split(separator:"/").contains(".."),file.path.hasPrefix(sourceRoot.path+"/"),try hash(file)==expected else{throw Failure.invalid}
        }
        return manifest
    }
    static func files(_ directory: URL, _ prefix: String) throws -> (FileHandle, FileHandle) {
        let out = directory.appendingPathComponent(prefix + ".stdout"), err = directory.appendingPathComponent(prefix + ".stderr")
        guard FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw Failure.invalid }
        return (try FileHandle(forWritingTo: out), try FileHandle(forWritingTo: err))
    }
    static func command(_ arguments: [String]) throws -> [String: Any] {
        guard arguments == ["--inspect-recovery"] || arguments == ["--prepare-owned"] || (arguments.count == 2 && arguments[0] == "--prepare-target" && UInt32(arguments[1]) != nil) else { throw Failure.invalid }
        let manifest = try manifest()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let diagnostic = root.appendingPathComponent("product-command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: diagnostic, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let (out, err) = try files(diagnostic, "command")
        defer { try? out.close(); try? err.close() }
        let process = Process(), done = DispatchSemaphore(value: 0)
        process.executableURL = controller; process.arguments = arguments
        process.standardOutput = out; process.standardError = err
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 15) != .success {
            // Keep the process and diagnostics: preparation may already have succeeded.
            throw Failure.unknown(diagnostic)
        }
        guard process.terminationStatus == 0, try hash(controller) == manifest["controllerSHA256"] as? String else { throw Failure.unknown(diagnostic) }
        let data = try Data(contentsOf: diagnostic.appendingPathComponent("command.stdout"))
        guard data.count < 1_048_576, let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unknown(diagnostic) }
        return result
    }
    static func preflight() throws -> [String: Any] {
        for app in NSWorkspace.shared.runningApplications {
            let path = app.executableURL?.path ?? ""
            guard !path.hasSuffix("/Ice Selected Controller.app/Contents/MacOS/IceSelectedController"),
                  !path.hasSuffix("/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController") else { throw Failure.invalid }
        }
        let recovery = try command(["--inspect-recovery"])
        guard recovery["journalPending"] as? Bool == false else { throw Failure.invalid }
        return ["workerRevision": revision, "contract": "ordinaryIceInterfaceV9", "journalPending": false,
                "ordinaryEntryConnected": true, "automaticStart": false, "mousePosts": 0, "windowsOpened": 0, "permissionRequests": 0]
    }
    static func recovery() throws -> [String: Any] {
        var value = try command(["--inspect-recovery"])
        guard value["journalPending"] is Bool, value["unconfirmedDown"] is Bool else { throw Failure.invalid }
        value["evidenceDirectory"] = root.appendingPathComponent("selected-relative-recovery-v2").path
        value["nativePosts"] = 0; value["recordsCleared"] = 0
        return value
    }
    static func prepareOwned() throws -> URL {
        _ = try preflight()
        let value = try command(["--prepare-owned"])
        guard value["posts"] as? Int == 0, let path = value["session"] as? String else { throw Failure.invalid }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard directory.deletingLastPathComponent() == root, directory.resolvingSymlinksInPath() == directory else { throw Failure.invalid }
        return directory
    }
    static func prepare(_ target: MenuBarIceSelectedTarget) throws -> URL {
        _ = try preflight()
        let current = try target.validate(directory: MenuBarIceSelectedTarget.readDirectory(), owner: MenuBarProcessSignature.read(target.owner.pid))
        guard current.frame == target.originalFrame else { throw Failure.targetChanged }
        let result = try command(["--prepare-target", String(target.windowID)])
        guard result["posts"] as? Int == 0, let path = result["session"] as? String else { throw Failure.invalid }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard directory.deletingLastPathComponent() == root, directory.resolvingSymlinksInPath() == directory else { throw Failure.invalid }
        return directory
    }
    /// A worker's new nonce does not permit it to recapture a different selection.
    static func validate(_ prepared: Prepared, target: MenuBarIceSelectedTarget, directory: URL, sha: String, now: Double) throws {
        guard let selected = prepared.selected, !prepared.selfOwned,
              directory.deletingLastPathComponent() == root, directory.lastPathComponent == "session-" + prepared.nonce.uuidString,
              selected.nonce == prepared.nonce, prepared.controllerSHA256 == sha,
              now.isFinite, prepared.preparedAtUnix.isFinite, now >= prepared.preparedAtUnix, now - prepared.preparedAtUnix < 120,
              selected.owner == target.owner, selected.windowID == target.windowID,
              selected.display == target.display, selected.space == target.space,
              selected.originalFrame == target.originalFrame else { throw Failure.targetChanged }
    }
    static func validateReady(_ value: [String: Any], nonce: UUID, pid: Int32, production: Bool = false) throws {
        guard value["nonce"] as? String == nonce.uuidString, value["pid"] as? Int32 == pid,
              value["nativePosts"] as? Int == 0 else { throw Failure.invalid }
        if production {
            guard value["productionMode"] as? Bool == true, value["automaticStart"] as? Bool == true,
                  value["windowVisible"] as? Bool == false else { throw Failure.invalid }
        } else {
            guard value["productionMode"] as? Bool != true, value["automaticStart"] as? Bool != true,
                  value["windowVisible"] as? Bool == true,
                  let number = value["windowNumber"] as? Int, number > 0 else { throw Failure.invalid }
        }
    }
    static func launch(_ directory: URL, target: MenuBarIceSelectedTarget? = nil, ownedWindow: Bool = false, ownedCancelCheck: Bool = false, production: Bool = false) async throws -> Launch {
        guard !production || (target != nil && !ownedWindow && !ownedCancelCheck) else { throw Failure.invalid }
        let manifest = try manifest()
        guard directory.resolvingSymlinksInPath() == directory,
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("action-consumed.json").path),
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("result.json").path) else { throw Failure.invalid }
        let data = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        guard data.count < 65_536, let sha = manifest["controllerSHA256"] as? String else { throw Failure.invalid }
        let prepared = try JSONDecoder().decode(Prepared.self, from: data)
        if let target {
            guard !ownedWindow else { throw Failure.invalid }
            try validate(prepared, target: target, directory: directory, sha: sha, now: Date().timeIntervalSince1970)
            let current = try target.validate(directory: MenuBarIceSelectedTarget.readDirectory(), owner: MenuBarProcessSignature.read(target.owner.pid))
            guard current.frame == target.originalFrame else { throw Failure.targetChanged }
        } else {
            let now = Date().timeIntervalSince1970
            guard prepared.selfOwned, prepared.selected == nil, prepared.controllerSHA256 == sha,
                  directory.deletingLastPathComponent() == root, directory.lastPathComponent == "session-" + prepared.nonce.uuidString,
                  prepared.preparedAtUnix.isFinite, now >= prepared.preparedAtUnix, now - prepared.preparedAtUnix < 120 else { throw Failure.invalid }
        }
        // This is an independently signed GUI app. LaunchServices supplies its normal
        // application lifecycle and existing TCC identity; do not spawn it as a child
        // of the unprivileged product host or alter its permissions/environment.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--session", directory.path]
        configuration.activates = !production
        if production { configuration.arguments.append("--production-session") }
        try Task.checkCancellation()
        if ownedCancelCheck { configuration.arguments.append("--owned-entry-cancel-check") }
        else if ownedWindow { configuration.arguments.append("--owned-window-session") }
        let application: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: packageRoot.appendingPathComponent("Ice Selected Controller.app"), configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? Failure.unknown(directory)) }
            }
        }
        do {
            let proof = try MenuBarProcessSignature.read(application.processIdentifier)
            guard proof.executable == controller.path, proof.identifier == "com.ryanai.mactools", proof.team == "58TJ64422P",
                  proof.sha256 == sha, proof.launch != nil, !application.isTerminated else { throw Failure.invalid }
            let launch = Launch(application: application, proof: proof)
            try JSONSerialization.data(withJSONObject: ["nonce": prepared.nonce.uuidString, "pid": proof.pid,
                "launchMethod": "NSWorkspace.openApplication", "automaticStart": production, "productionMode": production, "permissionRequests": 0], options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("product-launch.json"), options: .atomic)
            let until = ProcessInfo.processInfo.systemUptime + 20
            while ProcessInfo.processInfo.systemUptime < until {
                if let bytes = try? Data(contentsOf: directory.appendingPathComponent("ready.json")), bytes.count < 65_536,
                   let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    try validateReady(value, nonce: prepared.nonce, pid: proof.pid, production: production)
                    if !ownedCancelCheck {
                        guard launch.isRunning else { throw Failure.invalid }
                        guard try MenuBarProcessSignature.read(proof.pid) == proof else { throw Failure.invalid }
                    }
                    return launch
                }
                if let bytes = try? Data(contentsOf: directory.appendingPathComponent("result.json")), bytes.count < 2_000_000,
                   let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                   value["nonce"] as? String == prepared.nonce.uuidString, value["posts"] as? Int == 0,
                   let failure = value["failure"] as? String {
                    throw Failure.startup(directory, failure)
                }
                guard launch.isRunning else { throw Failure.unknown(directory) }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw Failure.unknown(directory)
        } catch let error as Failure { throw error }
        catch { throw Failure.unknown(directory) }
    }
    static func result(_ value: [String: Any], nonce: UUID) throws -> (passed: Bool, posts: Int) {
        guard value["nonce"] as? String == nonce.uuidString, let posts = value["posts"] as? Int, posts >= 0,
              let passed = value["realClosedLoopVerified"] as? Bool else { throw Failure.invalid }
        if passed {
            guard value["menuClosedClaimed"] as? Bool == false, value["icePositionVerified"] as? Bool == true,
                  let journal = value["journal"] as? [String: Any], journal["contract"] as? String == "ordinaryIceInterfaceV9",
                  journal["phase"] as? String == "returned", journal["pendingRecovery"] as? Bool == false,
                  journal["possibleDown"] as? Bool == false, journal["journalOutcomeUncertain"] as? Bool == false,
                  let durable = journal["durableRecord"] as? [String: Any], durable["schemaVersion"] as? Int == 4,
                  durable["phase"] as? String == "returned",
                  let completion = value["interfaceCompletion"] as? [String: Any], completion["nonce"] as? String == nonce.uuidString,
                  completion["criterion"] as? String == "iceTrackedInterfaceInactiveV9", completion["nativeObservation"] as? Bool == true,
                  let evidence = value["returnEvidence"] as? [String: Any], evidence["nonce"] as? String == nonce.uuidString,
                  evidence["criterion"] as? String == "iceNeighborEdgeV4" else { throw Failure.invalid }
        }
        return (passed, posts)
    }
}

#endif
