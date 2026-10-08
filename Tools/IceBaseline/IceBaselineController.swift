// Copyright (c) 2026 Ryan.AI. MIT; linked Ice files GPL-3.0.
import AppKit
import CryptoKit

@MainActor
final class IceBaselineController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let directory: URL, nonce: String
    var window: NSWindow!, status: NSTextField!, start: NSButton!, cancel: NSButton!
    var engine: IceBaselineEngine?, native: IceBaselineNative?
    var candidate: IceBaselineCandidateCoordinator?
    var used = false, running = false, cancellationRequested = false
    var watchdog: Timer?, runTask: Task<Void, Never>?
    var fixturePID: Int32?, operationID: String?, readyDeadline: Double?, operationDeadline: Double?
    var cleanupDeadline: Double?, idleResultWritten = false
    let nativeANY:Bool
    var nativeAuthorization:MenuBarRealLocalAuthorization?,nativeInput:MenuBarListenOnlyInterferenceSource?
    var nativeSampler:IceBaselineNativePlan?,nativePermit:MenuBarRealLocalAuthorization.Permit?
    var nativeBinding:IceCandidateBinding?,nativeStartCaptured=false,nativePolling=false
    var forceExit = false
    var retainedPossibleDown = false
    let startupDeadline = ProcessInfo.processInfo.systemUptime + 10
    init(directory: URL, nonce: String) {
        self.directory = directory; self.nonce = nonce
        let session=(try? JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("session.json")))) as? [String:Any]
        nativeANY=session?["contract"] as? String == IceCandidateContract.isolatedOwnedANYV1.rawValue
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 270),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = nativeANY ? "MacTools v3.6 原生 ANY · 仅自建 T/N" : "独立 Ice 0.11.12 基线 · 仅自建 T/N"; window.center()
        window.delegate = self
        let content = window.contentView!
        let text = NSTextField(wrappingLabelWithString: "本轮按 Ice 的鼠标静止策略运行，已移除严格 ANY 开始门禁。\n只搬移自建 T，打开并关闭菜单，等待15秒后归位。\n运行会短暂影响焦点和光标；取消后停止后续操作。\n正式版保持不变，本轮不会安装应用。")
        if nativeANY {text.stringValue="沿用原ANY本地授权：鼠标点击开始一次并松开，核对回执、250ms观察与3秒倒计时。\n只操作自建T/N；本轮会影响焦点和光标。\n未知输入或回执立即停止，不自动补up、重试或清除责任。\nAX启动不会授予原生许可；正式版保持不变。"}
        text.frame = NSRect(x: 20, y: 125, width: 580, height: 125); content.addSubview(text)
        status = NSTextField(wrappingLabelWithString: "等待现场协调；尚未创建 tap 或发送事件。")
        status.frame = NSRect(x: 20, y: 55, width: 580, height: 65); content.addSubview(status)
        start = NSButton(title: "开始自建 T 单轮", target: self, action: #selector(begin)); start.frame = NSRect(x: 20, y: 15, width: 200, height: 32); content.addSubview(start)
        start.isEnabled = false
        cancel = NSButton(title: "取消本轮", target: self, action: #selector(stop)); cancel.frame = NSRect(x: 260, y: 15, width: 200, height: 32); content.addSubview(cancel)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        watchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchLifetime() }
        }
        RunLoop.main.add(watchdog!, forMode: .common)
        Task {
            do {
                let root = directory.deletingLastPathComponent(), manifest = try prepared(root), d = try owner()
                guard let pid = d["pid"] as? Int32 else { throw IceBaselineError.identity }
                let proof = try MenuBarProcessSignature.read(pid)
                guard proof.identifier == "com.ryanai.mactools.nativetargets",
                      proof.sha256 == manifest["fixtureSHA256"] as? String,
                      proof.team == (try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)).team,
                      proof.executable == root.appendingPathComponent("Ice Baseline Targets.app/Contents/MacOS/IceBaselineTargets").resolvingSymlinksInPath().path
                else { throw IceBaselineError.identity }
                fixturePID = pid
                let id = try signalLifetime(.ready), state = try await acknowledgment(id, phase: .ready)
                guard !cancellationRequested, let deadline = state["deadlineUptime"] as? Double,
                      deadline.isFinite, ProcessInfo.processInfo.systemUptime < deadline else { throw IceBaselineError.cancelled }
                readyDeadline = deadline
                if nativeANY {try await prepareNativeANY(deadline:deadline)}
                start.isEnabled = true
                status.stringValue = nativeANY ? "原生ANY已就绪：鼠标点击开始一次并松开，按原契约完成观察与倒计时；AX启动不接受。" : "自建会话已就绪；120秒内可开始一次。发布覆盖操作及清理，状态鲜度仍限1秒。"
                try save("controller-ready.json", ["nonce":nonce,"pid":ProcessInfo.processInfo.processIdentifier,"lifetime":state,"nativeEffects":nativeANY ? 2 : 0,"nativeMousePosts":0,"listenOnlyTaps":nativeANY ? 2 : 0,"contract":nativeANY ? "isolatedOwnedANYV1" : "isolatedOwnedQuietV1","strictANYRequired":nativeANY,"inputPolicy":nativeANY ? "strictANYDiagnostic" : "iceMouseTracking"])
            } catch {
                var evidence:[String:Any]=["failure":String(describing:error),"stage":nativeSampler?.lastStage ?? "handshake","posts":0]
                if let first=nativeSampler?.lastFirst {evidence["first"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(first))}
                if let second=nativeSampler?.lastSecond {evidence["second"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(second))}
                try? save("native-preparation-failure.json",evidence)
                if nativeANY {endNativeAuthorization(error)}else{endIdle(reason:"ready handshake: \(error)")}
            }
        }
    }
    @objc func stop() {
        guard !cancellationRequested else { return }
        cancellationRequested = true; nativeAuthorization?.cancel(); start.isEnabled = false; candidate?.cancel(); if candidate == nil { engine?.cancel() }; runTask?.cancel()
        do { try save("cancel-receipt.json", ["nonce":nonce,"atUnix":Date().timeIntervalSince1970,
            "operationStarted":used,"operationRunning":running,"postsAtCancel":native?.posts ?? 0,
            "possibleDown":retainedPossibleDown || (engine?.possibleDown ?? false) || (candidate?.possibleDown ?? false)]) }
        catch { fputs("controller cancel receipt save failed: \(error)\n", stderr) }
        startCleanup(.cancel)
        status.stringValue = "本轮已取消；停止后续鼠标操作。辅助会话将在15秒内退出，自建项移除不计作原生归位。"
        if !running { writeIdle(reason: "cancelledBeforeStart") }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stop(); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if forceExit { engine?.cancel(); native?.stopMonitoring(); return .terminateNow }
        if running { stop(); return .terminateCancel }
        startCleanup(.terminal); return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.invalidate(); engine?.cancel(); runTask?.cancel(); native?.stopMonitoring(); nativeAuthorization?.monitor.stop(); nativeInput?.bindOperationStop(nil);nativeInput?.stop()
        do { try save("controller-exit.json", ["nonce":nonce,"running":running,"cancelRequested":cancellationRequested,
            "possibleDown":retainedPossibleDown || (engine?.possibleDown ?? false),"exitIsNativeRestore":false,"physicalReleaseProven":false]) }
        catch { fputs("controller exit evidence save failed: \(error)\n", stderr) }
    }
    private func signalLifetime(_ action: IceBaselineSessionLifetime.Action) throws -> String {
        if action == .ready || action == .begin {
            guard !cancellationRequested else { throw IceBaselineError.cancelled }
        }
        guard let pid = fixturePID else { throw IceBaselineError.identity }
        let id = UUID().uuidString
        try save("owner-state/lifetime-request.json", ["nonce":nonce,"fixturePID":pid,
            "controllerPID":ProcessInfo.processInfo.processIdentifier,"action":action.rawValue,
            "request":id,"atUnix":Date().timeIntervalSince1970])
        return id
    }
    private func lifetime(_ d: [String: Any]) throws -> [String: Any] {
        guard let state = (d["menuControl"] as? [String: Any])?["lifetime"] as? [String: Any] else { throw IceBaselineError.identity }
        return state
    }
    private func acknowledgment(_ id: String, phase: IceBaselineSessionLifetime.Phase) async throws -> [String: Any] {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            guard !cancellationRequested else { throw IceBaselineError.cancelled }
            let state = try lifetime(owner())
            if state["acknowledgment"] as? String == id {
                guard state["phase"] as? String == phase.rawValue else { throw IceBaselineError.identity }; return state
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw IceBaselineError.timeout
    }
    private func startCleanup(_ action: IceBaselineSessionLifetime.Action) {
        guard cleanupDeadline == nil else { return }
        cleanupDeadline = ProcessInfo.processInfo.systemUptime + IceBaselineSessionLifetime.cleanupBudget
        do { _ = try signalLifetime(action) }
        catch { fputs("controller lifecycle cleanup signal failed: \(error)\n", stderr) }
    }
    func writeIdle(reason: String) {
        guard !used, !idleResultWritten else { return }; idleResultWritten = true
        do { try save("result.json", ["nonce":nonce,"failure":reason,"posts":0,"realClosedLoopVerified":false,
            "cancelRequested":cancellationRequested,"physicalButtonReleaseVerified":false,"thirdPartyTargetActions":0]) }
        catch { fputs("idle terminal evidence save failed: \(error)\n", stderr) }
    }
    private func endIdle(reason: String) {
        if running { stop(); return }
        cancellationRequested = true; start.isEnabled = false
        writeIdle(reason: reason); startCleanup(.terminal); status.stringValue = "本轮停止：\(reason)。辅助会话有界退出。"
    }
    private func watchLifetime() {
        tickNativeAuthorization()
        let now = ProcessInfo.processInfo.systemUptime
        if let deadline = cleanupDeadline, now >= deadline { forceExit = true; NSApp.terminate(nil); return }
        if cleanupDeadline != nil { return }
        if running {
            if let deadline = operationDeadline, now >= deadline { stop() }
        } else if !used {
            if let deadline = readyDeadline {
                if now >= deadline { endIdle(reason: "readyDeadline") }
            } else if now >= startupDeadline { endIdle(reason: "startupDeadline") }
        }
    }
    private func owner() throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("owner-state/latest.json"))
        guard data.count < 256_000, let d = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              d["nonce"] as? String == nonce, let at = d["atUnix"] as? Double,
              (0...1).contains(Date().timeIntervalSince1970 - at), d["phase"] as? String == "timer",
              let p = d["bundlePath"] as? String,
              URL(fileURLWithPath: p).resolvingSymlinksInPath() == directory.deletingLastPathComponent().appendingPathComponent("Ice Baseline Targets.app").resolvingSymlinksInPath()
        else { throw IceBaselineError.identity }; return d
    }
    private func models(_ d: [String: Any]) throws -> [[String: Any]] {
        guard let a = d["modelsAfter"] as? [[String: Any]], a.count == 2,
              Set(a.compactMap { $0["title"] as? String }) == Set(["T", "N"]) else { throw IceBaselineError.identity }; return a
    }
    private func stableLayout(area: CGRect, display: UInt32) async throws -> ([String: Any], IceBaselineLayout) {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var stability = IceBaselineLayout.Stability(), lastError: Error = IceBaselineError.geometry
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard !cancellationRequested else { throw IceBaselineError.cancelled }
            do {
                let d = try owner(), layout = try IceBaselineLayout.read(d, area: area, display: display)
                guard let sequence = d["sequence"] as? Int, let at = d["atUnix"] as? Double else { throw IceBaselineError.identity }
                if stability.observe(layout, sequence: sequence, at: at, now: Date().timeIntervalSince1970) { return (d, layout) }
            } catch { stability.reset(); lastError = error }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        throw lastError
    }
    private func menuOpen(_ pid: Int32) throws -> Bool {
        let d = try owner(); guard d["pid"] as? Int32 == pid,
            let menu = d["menuControl"] as? [String: Any] else { throw IceBaselineError.identity }
        return menu["openKey"] as? String == "mactools_native_acceptance_T"
    }
    private func settledReturn(_ expected: IceBaselineLayout, pid: Int32, area: CGRect, display: UInt32, op: IceBaselineEngine) async throws {
        let first = try owner()
        guard let sequence = first["sequence"] as? Int else { throw IceBaselineError.identity }
        var stability = IceBaselineLayout.ReturnStability(expected: expected, pid: pid, nonce: nonce, minimumSequence: sequence)
        var observations: [[String: Any]] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            try op.check()
            let d = try owner(); observations.append(d)
            try save("return-observations.json", ["nonce":nonce,"minimumSequence":sequence,"samples":observations])
            if try stability.observe(d, area: area, display: display, now: Date().timeIntervalSince1970) { return }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        throw IceBaselineError.geometry
    }
    private func save(_ file: String, _ value: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(file), options: .atomic)
    }
    private func prepared(_ root: URL) throws -> [String: Any] {
        guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("prepared-build.json"))) as? [String: Any],
              let sources = manifest["sources"] as? [String: String], sources.count >= 10,
              manifest["repository"] as? String == "/Users/yangruihan/Workspace/mac_tools" else { throw IceBaselineError.identity }
        func sha(_ path: String) throws -> String {
            SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
        }
        for (path, digest) in sources {
            guard path.hasPrefix("/Users/yangruihan/Workspace/mac_tools/"), try sha(path) == digest else { throw IceBaselineError.identity }
        }
        let controller = try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
        guard controller.identifier == "com.ryanai.mactools", controller.sha256 == manifest["controllerSHA256"] as? String,
              controller.executable == root.appendingPathComponent("Ice Baseline Controller.app/Contents/MacOS/IceBaselineController").resolvingSymlinksInPath().path,
              try sha("/Applications/MacTools.app/Contents/MacOS/MacTools") == manifest["formalSHA256"] as? String else { throw IceBaselineError.identity }
        return manifest
    }
    private func menuWindows(_ pid: Int32) -> [[String: Any]] {
        (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.popUpMenuWindow))
        }
    }
    private func peerFacts(_ rows: [[String: Any]], excluding pid: Int32) -> [[String: Any]] {
        rows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != pid }
            .map { ["id": $0[kCGWindowNumber as String]!, "pid": $0[kCGWindowOwnerPID as String]!, "bounds": $0[kCGWindowBounds as String]!] }
            .sorted { ($0["id"] as! NSNumber).uint32Value < ($1["id"] as! NSNumber).uint32Value }
    }
    private func prepareNativeANY(deadline:Double)async throws {
        let store=IceBaselineCandidateJournal(directory:directory.deletingLastPathComponent().appendingPathComponent("candidate-recovery-v1"))
        guard try store.inspect()==nil,AXIsProcessTrusted(),CGPreflightPostEventAccess(),CGPreflightListenEventAccess(),
              let screen=NSScreen.screens.first,let area=screen.auxiliaryTopRightArea,
              let display=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else{throw IceCandidateFailure.policy}
        let (before,layout)=try await stableLayout(area:area,display:display)
        guard let pid=before["pid"] as? Int32 else{throw IceCandidateFailure.binding}
        let windows=try IceBaselineWindows(),controller=try IceCandidateBinding.Process(MenuBarProcessSignature.read(getpid())),fixture=try IceCandidateBinding.Process(MenuBarProcessSignature.read(pid))
        guard controller.team=="58TJ64422P",fixture.team==controller.team else{throw IceCandidateFailure.binding}
        let binding=IceCandidateBinding(nonce:UUID(uuidString:nonce)!,controller:controller,fixture:fixture,display:display,
            space:windows.activeSpace(windows.connection()),area:.init(x:area.minX,y:layout.anchor.frame.minY,width:area.width,height:layout.anchor.frame.height),layout:layout)
        try binding.validate()
        for item in [binding.target,binding.neighbor,binding.anchor,binding.divider] {
            guard try windows.frame(.init(windowID:item.id,pid:pid,key:item.key))==item.frame.cg else{throw IceCandidateFailure.binding}
        }
        let sampler=IceBaselineNativePlan(binding:binding,windows:windows,publication:{try self.owner()});nativeSampler=sampler
        let plan=try sampler.pair();try save("native-prepared-plan.json",try JSONSerialization.jsonObject(with:JSONEncoder().encode(plan)) as! [String:Any])
        let adapter=IceBaselineCandidateCoordinator(journal:store,binding:binding,contract:.isolatedOwnedANYV1,deadline:deadline+50)
        candidate=adapter;nativeBinding=binding;nativeSampler=sampler
        let input=MenuBarListenOnlyInterferenceSource()
        nativeInput=input;try adapter.fence.perform("native-any-source-start"){try input.start(.isolatedListenOnly)}
        let witness=MenuBarDispatchWitness.Binding(nonce:binding.nonce,targetPID:pid,controllerPID:getpid(),controllerLaunch:controller.launch,controllerSHA256:controller.sha256)
        let stages=try MenuBarMoveStageRecorder(directory:directory.appendingPathComponent("native-authorization-stages"),nonce:binding.nonce,controllerPID:getpid())
        try stages.append("native-prepared-plan",plan)
        let authorization=try MenuBarRealLocalAuthorization(binding:witness,plan:plan,input:input,
            expires:DispatchTime.now().uptimeNanoseconds+UInt64(max(0,deadline-ProcessInfo.processInfo.systemUptime)*1_000_000_000),evidence:stages,captureActionLayout:{try sampler.pair()})
        nativeAuthorization=authorization
        try adapter.fence.perform("native-local-receipt-start"){try authorization.monitor.start();authorization.monitor.configureLocalStart(window:self.window.windowNumber)}
        RunLoop.main.add(watchdog!,forMode:.eventTracking)
    }
    private func endNativeAuthorization(_ error:Error) {
        try? nativeAuthorization?.recordTerminal(error)
        if let terminal=nativeAuthorization?.terminalEvidence,let data=try? JSONEncoder().encode(terminal),
           let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any]{try? save("native-authorization-terminal.json",value)}
        nativeAuthorization?.monitor.stop();nativeInput?.bindOperationStop(nil);nativeInput?.stop();candidate?.fence.fail()
        endIdle(reason:"native ANY authorization: \(error)")
    }
    private func tickNativeAuthorization() {
        guard nativeANY,!nativePolling,!running,!used,!cancellationRequested,cleanupDeadline==nil,let authorization=nativeAuthorization else{return}
        nativePolling=true;defer{nativePolling=false}
        do {
            try authorization.poll()
            if authorization.monitor.state == .validatedRealInput {
                nativePermit=try authorization.permit();used=true;running=true;start.isEnabled=false
                runTask=Task{await run()}
            }else if nativeStartCaptured {status.stringValue="原生授权：\(authorization.monitor.state)；尚未发送鼠标事件。"}
        }catch{endNativeAuthorization(error)}
    }
    @objc func begin() {
        guard !used, !cancellationRequested, let deadline = readyDeadline else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { endIdle(reason: "lateStart"); return }
        if nativeANY {
            guard !nativeStartCaptured,let authorization=nativeAuthorization,authorization.monitor.state == .ready,
                  let event=NSApp.currentEvent,event.type == .leftMouseUp,event.window === window,event.windowNumber==window.windowNumber,
                  start.bounds.contains(start.convert(event.locationInWindow,from:nil)),let packet=event.cgEvent?.copy() else {
                endNativeAuthorization(IceCandidateFailure.binding);return
            }
            nativeStartCaptured=true;start.isEnabled=false;authorization.begin(packet);tickNativeAuthorization();return
        }
        used = true; running = true; start.isEnabled = false
        runTask = Task { await run() }
    }
    func run() async {
        var result: [String: Any] = ["nonce": nonce, "policy": nativeANY ? "isolatedOwnedANYV1" : "isolated-Ice-0.11.12-mouseQuiet", "productANYChanged": false,
            "strictANYRequired":nativeANY,"inputPolicy":nativeANY ? "strictANYDiagnostic" : "iceMouseTracking",
            "realClosedLoopVerified": false, "thirdPartyTargetActions": 0]
        defer {
            if let authorization=nativeAuthorization {
                try? authorization.recordTerminal(nil)
                if let terminal=authorization.terminalEvidence {result["nativeAuthorization"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(terminal))}
                authorization.monitor.stop()
            }
            nativeInput?.bindOperationStop(nil);nativeInput?.stop()
            if let native { result["posts"] = native.posts; result["events"] = native.events; native.stopMonitoring() }
            result["posts"] = native?.posts ?? 0
            retainedPossibleDown = retainedPossibleDown || (engine?.possibleDown ?? false) || (candidate?.possibleDown ?? false)
            result["possibleDown"] = retainedPossibleDown
            result["cancelRequested"] = cancellationRequested
            result["candidateJournal"] = candidate?.diagnostics() as Any? ?? NSNull()
            result["physicalButtonReleaseVerified"] = false // Route completion does not prove hardware release.
            do {
                try save("result.json", result)
                if result["realClosedLoopVerified"] as? Bool == true {
                    status.stringValue = "本轮真实 move/menu/close/restore 证据通过；result.json 已记录，仍不启用产品搬移。"
                }
            } catch {
                status.stringValue = "终态写入失败：\(error)。闭环结果不能作为已落盘证据；请保留此窗口与现场状态。"
                fputs("Ice baseline terminal evidence save failed: \(error)\n", stderr)
            }
            engine = nil; running = false
            startCleanup(cancellationRequested ? .cancel : .terminal)
        }
        do {
            guard !cancellationRequested else { throw IceBaselineError.cancelled }
            let id = try signalLifetime(.begin)
            let active = try await acknowledgment(id, phase: .active)
            guard let deadline = active["deadlineUptime"] as? Double,
                  IceBaselineSessionLifetime.permitsEffects(active, operation: id, now: ProcessInfo.processInfo.systemUptime)
            else { throw IceBaselineError.identity }
            operationID = id; operationDeadline = deadline
            let root = directory.deletingLastPathComponent(), manifest = try prepared(root)
            guard AXIsProcessTrusted(), CGPreflightPostEventAccess(), CGPreflightListenEventAccess(),
                ProcessInfo.processInfo.operatingSystemVersionString.contains("15.7.4") else { throw IceBaselineError.source }
            guard let screen = NSScreen.screens.first, let area = screen.auxiliaryTopRightArea,
                  let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { throw IceBaselineError.geometry }
            status.stringValue = "只读等待三份稳定布局：屏外 T/N、可见 H 及足够空间；尚未创建运输。"
            let initialScreenFrame = screen.frame
            let (before, layout) = try await stableLayout(area: area, display: display), rows = try models(before)
            guard let pid = before["pid"] as? Int32 else { throw IceBaselineError.identity }
            let tid = layout.target.id, nid = layout.neighbor.id, hid = layout.anchor.id
            let proof = try MenuBarProcessSignature.read(pid)
            guard proof.identifier == "com.ryanai.mactools.nativetargets",
                  proof.sha256 == manifest["fixtureSHA256"] as? String,
                  proof.team == (try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)).team,
                  proof.executable == root.appendingPathComponent("Ice Baseline Targets.app/Contents/MacOS/IceBaselineTargets").resolvingSymlinksInPath().path else { throw IceBaselineError.identity }
            let target = IceBaselineItem(windowID: tid, pid: pid, key: "T"), neighbor = IceBaselineItem(windowID: nid, pid: pid, key: "N")
            let anchor = IceBaselineItem(windowID: hid, pid: pid, key: "H")
            let divider = IceBaselineItem(windowID: layout.divider.id, pid: pid, key: "D")
            let windows = try IceBaselineWindows(), tf = try windows.frame(target), nf = try windows.frame(neighbor)
            let hf = try windows.frame(anchor)
            let df = try windows.frame(divider)
            guard tf == layout.target.frame, nf == layout.neighbor.frame, hf == layout.anchor.frame, df == layout.divider.frame else { throw IceBaselineError.geometry }
            result["before"] = before; result["peerBefore"] = IceBaselineWindows.rows()
            let ownProof = try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
            let safeMenuBar = CGRect(x:area.minX,y:layout.anchor.frame.minY,width:area.width,height:layout.anchor.frame.height)
            let binding = IceCandidateBinding(nonce:UUID(uuidString:nonce)!,controller:try .init(ownProof),fixture:try .init(proof),
                display:display,space:windows.activeSpace(windows.connection()),area:safeMenuBar,layout:layout)
            let store = IceBaselineCandidateJournal(directory:root.appendingPathComponent("candidate-recovery-v1",isDirectory:true))
            let adapter:IceBaselineCandidateCoordinator
            if nativeANY {
                guard binding==nativeBinding,let pending=candidate,let permit=nativePermit,
                      let input=nativeInput,let authorization=nativeAuthorization else{throw IceCandidateFailure.binding}
                adapter=pending;try adapter.constrainDeadline(deadline)
                let bridge=try IceBaselineANYBridge.native(plan:authorization.plan,binding:binding,permit:permit,input:input,stop:adapter.fence.stop)
                try adapter.bindANY(bridge,offline:false);authorization.monitor.stop()
            }else{adapter=IceBaselineCandidateCoordinator(journal:store,binding:binding,contract:.isolatedOwnedQuietV1,deadline:deadline)}
            candidate=adapter
            try await adapter.run {
            let e = try adapter.performAux("owned-transport-create") { IceBaselineNative(windows: windows, pid: pid) {
                let current = try MenuBarProcessSignature.read(pid)
                let owner = try self.owner()
                guard !self.cancellationRequested,
                      IceBaselineSessionLifetime.permitsEffects(try self.lifetime(owner), operation: id, now: ProcessInfo.processInfo.systemUptime),
                      current == proof, owner["pid"] as? Int32 == pid,
                      NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == display,
                      NSScreen.screens.first?.frame == initialScreenFrame,
                      NSScreen.screens.first?.auxiliaryTopRightArea == area,
                      let h = (owner["menuControl"] as? [String: Any])?["visibleAnchorModel"] as? [String: Any],
                      let d = (owner["menuControl"] as? [String: Any])?["dividerModel"] as? [String: Any] else { throw IceBaselineError.identity }
                let m = try self.models(owner) + [h, d]
                for expected in [layout.target, layout.neighbor, layout.anchor, layout.divider] {
                    guard m.contains(where: { $0["windowNumber"] as? UInt32 == expected.id && $0["itemInstance"] as? String == expected.instance && $0["itemKey"] as? String == expected.key && $0["screenDisplayID"] as? UInt32 == display && $0["windowOnActiveSpace"] as? Bool == true }) else { throw IceBaselineError.identity }
                }
            } }
            try e.bindCandidate(adapter)
            native = e
            let budget = min(45, deadline - e.time)
            guard budget > 0 else { throw IceBaselineError.budget }
            native = e; let op = IceBaselineEngine(e, budget: budget); engine = op
            try adapter.attach(op)
            guard !cancellationRequested else { op.cancel(); throw IceBaselineError.cancelled }
            try Data(nonce.utf8).write(to: directory.appendingPathComponent("action-consumed"), options: .withoutOverwriting)
            let originalDestination: IceBaselineDestination = layout.returnOnLeft ? .left(neighbor) : .right(neighbor)
            try save("plan.json", ["nonce": nonce, "pid": pid, "target": tid, "returnNeighbor": nid, "visibleAnchor": hid,
                "visibleDestination": "leftOfOwnedH", "returnDestination": layout.returnOnLeft ? "leftOfN" : "rightOfN", "policy": result["policy"]!])
            status.stringValue = "Ice 基线搬移 T；产品 ANY 门禁未接入此候选。"
            try await adapter.advance(.moving)
            try await op.move(target, to: .left(anchor))
            let visibleFrame = try windows.frame(target)
            guard visibleFrame.minX >= area.minX + 20, visibleFrame.maxX <= area.maxX else { throw IceBaselineError.geometry }
            result["visibleFrame"] = ["x": visibleFrame.minX, "y": visibleFrame.minY, "width": visibleFrame.width, "height": visibleFrame.height]
            try await adapter.advance(.visible)
            let lease=IceBaselineMenuLease.live(owner:binding.fixture,nonce:binding.nonce,display:display,space:binding.space) {
                (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0,windows.activeSpace(windows.connection()))
            }
            try lease.beginLive();try adapter.bindMenuLease(lease)
            try await adapter.advance(.opening)
            try await op.click(target)
            let menuDeadline = e.time + 2
            while !(try menuOpen(pid)) || menuWindows(pid).count != 1 {
                try op.check(); guard e.time < menuDeadline else { throw IceBaselineError.menu }; try await e.pause(0.01)
            }
            guard lease.refresh() == .open else{throw IceBaselineError.menu}
            result["menuOpenOwner"] = try owner(); result["menuOpenWindows"] = menuWindows(pid)
            let d = try owner(), control = d["menuControl"] as! [String: Any], generation = control["generation"] as! Int
            let request = UUID().uuidString
            try op.check()
            let body: [String: Any] = ["nonce": nonce, "pid": pid, "request": request, "atUnix": Date().timeIntervalSince1970,
                "generation": generation, "itemKey": "mactools_native_acceptance_T"]
            try adapter.performAux("owned-menu-close-request") {
                try JSONSerialization.data(withJSONObject: body).write(to: directory.appendingPathComponent("owner-state/cancel-request.json"), options: .withoutOverwriting)
            }
            e.note("owned-menu-close-request", body)
            let closeDeadline = e.time + 2
            while true {
                try op.check(); let latest = try owner(), m = latest["menuControl"] as! [String: Any]
                if m["cancelAcknowledged"] as? String == request, m["closedGeneration"] as? Int == generation,
                   m["openKey"] is NSNull, menuWindows(pid).isEmpty,lease.refresh() == .closed { break }
                guard e.time < closeDeadline else { throw IceBaselineError.menu }; try await e.pause(0.01)
            }
            result["menuClosedOwner"] = try owner()
            result["menuClosureProof"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(lease.confirmation()))
            try await adapter.advance(.menuClosed)
            try await adapter.advance(.restoring)
            status.stringValue = "菜单已证实关闭，等待 Ice 原有15秒临时显示间隔后归位。"
            try await op.rehide(target, to: originalDestination, interfaceOpen: { try self.menuOpen(pid) || !self.menuWindows(pid).isEmpty || lease.refresh() != .closed })
            result["restoreTransportCompletedUptime"] = e.time
            result["restoreTransportCompletedOwner"] = try owner()
            try await settledReturn(layout, pid: pid, area: area, display: display, op: op)
            var returned: [[String: Any]] = []
            var privateReturns: [[String: Any]] = []
            for _ in 0..<2 {
                try op.check(); try await e.pause(0.12)
                let final = try owner(), finalModels = try models(final)
                result["returnFinalObservations"] = returned + [final]
                for original in rows {
                    guard let model = finalModels.first(where: { $0["title"] as? String == original["title"] as? String }),
                          model["windowNumber"] as? UInt32 == original["windowNumber"] as? UInt32,
                          model["itemInstance"] as? String == original["itemInstance"] as? String,
                          NSDictionary(dictionary: model["windowFrameAppKit"] as! [String: Any]).isEqual(to: original["windowFrameAppKit"] as! [String: Any])
                    else { throw IceBaselineError.geometry }
                }
                let currentFrames = try [windows.frame(target), windows.frame(neighbor), windows.frame(anchor), windows.frame(divider)]
                privateReturns.append(Dictionary(uniqueKeysWithValues: zip(["T","N","H","D"], currentFrames).map { name,f in
                    (name,["x":f.minX,"y":f.minY,"width":f.width,"height":f.height])
                }))
                result["returnPrivateFrames"] = privateReturns
                guard currentFrames == [tf,nf,hf,df], menuWindows(pid).isEmpty else { throw IceBaselineError.geometry }
                returned.append(final)
            }
            let after = IceBaselineWindows.rows(); result["returnedOwners"] = returned; result["peerAfter"] = after
            let beforePeers = peerFacts(result["peerBefore"] as! [[String: Any]], excluding: pid), afterPeers = peerFacts(after, excluding: pid)
            guard NSArray(array: beforePeers).isEqual(to: afterPeers) else { throw IceBaselineError.geometry }
            let returnedEvidence = try JSONSerialization.data(withJSONObject:["nonce":nonce,"returnedOwners":returned,"privateFrames":privateReturns,"peerBefore":result["peerBefore"]!,"peerAfter":after],options:.sortedKeys)
            try await adapter.confirmReturned(evidence:returnedEvidence)
            }
            try Task.checkCancellation()
            result["realClosedLoopVerified"] = true
            status.stringValue = "现场闭环检查通过，正在保存证据。"
        } catch {
            try? nativeAuthorization?.recordTerminal(error)
            result["failure"] = String(describing: error)
            if error is IceBaselineLayout.Failure {
                result["layoutPreflightRejected"] = true
                result["preflightOwner"] = try? owner()
                result["setupNeeded"] = "只读布局尚未满足：T/N需屏外隐藏且邻接，H需CG/AppKit一致并可见，左侧留足T宽度；保留本轮，勿盲目拖动隐藏项。"
            }
            status.stringValue = "本轮停止：\(error)。\(result["setupNeeded"] as? String ?? "未通过闭环；终态将在 result.json 保存。")"
        }
    }
}

@main struct IceBaselineControllerMain {
    @MainActor static func main() async {
        if CommandLine.arguments.count == 4,CommandLine.arguments[1] == "--retire-owned-fixture" {
            do {
                guard let nonce=UUID(uuidString:CommandLine.arguments[2]),IceCandidateBinding.validHash(CommandLine.arguments[3]) else{throw IceCandidateFailure.binding}
                let store=IceBaselineCandidateJournal(directory:URL(fileURLWithPath:"/tmp/mac-tools-ice-baseline-candidate-20261007/candidate-recovery-v1"))
                let receipt=try await IceBaselineRecovery.retire(store,nonce:nonce,expectedHash:CommandLine.arguments[3])
                let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
                print(String(decoding:try encoder.encode(receipt),as:UTF8.self))
            }catch{fputs("explicit retirement refused: \(error)\n",stderr);exit(1)};return
        }
        if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--inspect-recovery" {
            do {
                let directory=URL(fileURLWithPath:"/tmp/mac-tools-ice-baseline-candidate-20261007/candidate-recovery-v1")
                let record=try IceBaselineCandidateJournal(directory:directory).inspect()
                let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                let digest=try record.map{IceBaselineCandidateJournal.hash(try encoder.encode($0))}
                let disposition=record.map{IceBaselineRecovery.disposition($0,IceBaselineRecovery.sample($0))}
                let value:[String:Any]=["journalPending":record != nil,"phase":record?.phase.rawValue as Any? ?? NSNull(),
                    "nonce":record?.binding.nonce.uuidString as Any? ?? NSNull(),"unconfirmedDown":record?.needsRelease ?? false,
                    "hasPossibleEffect":record?.hasPossibleEffect ?? false,"physicalReleaseProven":false,"nativeEffects":0,
                    "recordSHA256":digest as Any? ?? NSNull(),"recoveryDisposition":disposition as Any? ?? NSNull()]
                print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:.sortedKeys),as:UTF8.self))
            }catch{fputs("recovery inspection rejected: \(error)\n",stderr);exit(1)};return
        }
        if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--status-snapshot" {
            do {
                let rows = IceBaselineWindows.rows().map { ["id": $0[kCGWindowNumber as String] as Any, "pid": $0[kCGWindowOwnerPID as String] as Any, "bounds": $0[kCGWindowBounds as String] as Any] }
                let data = try JSONSerialization.data(withJSONObject: ["atUnix": Date().timeIntervalSince1970, "statusRows": rows, "nativeEffects": 0], options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { fputs("\(error)\n", stderr); exit(1) }; return
        }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--check-layout" {
            do {
                let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
                let area = try IceBaselineLayout.rect(input["area"] as? [String: Any])
                let sequence = input["samples"] as! [[String: Any]], display = input["display"] as! UInt32
                var stability = IceBaselineLayout.Stability(), ready = false
                for d in sequence {
                    let layout = try IceBaselineLayout.read(d, area: area, display: display)
                    ready = stability.observe(layout, sequence: d["sequence"] as! Int, at: d["atUnix"] as! Double, now: input["now"] as! Double)
                }
                print("{\"layoutAccepted\":\(ready),\"nativeEffects\":0}")
                if !ready { exit(3) }
            } catch { fputs("layout rejected: \(error)\n", stderr); exit(1) }; return
        }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--check-return" {
            do {
                let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
                let area = try IceBaselineLayout.rect(input["area"] as? [String: Any]), display = input["display"] as! UInt32
                let before = input["expected"] as! [String: Any], layout = try IceBaselineLayout.read(before, area: area, display: display)
                var observer = IceBaselineLayout.ReturnStability(expected: layout, pid: before["pid"] as! Int32,
                    nonce: before["nonce"] as! String, minimumSequence: input["minimumSequence"] as! Int)
                var accepted = false
                for d in input["samples"] as! [[String: Any]] {
                    accepted = try observer.observe(d, area: area, display: display, now: input["now"] as! Double)
                }
                print("{\"returnAccepted\":\(accepted),\"nativeEffects\":0}"); if !accepted { exit(3) }
            } catch { fputs("return rejected: \(error)\n", stderr); exit(1) }; return
        }
        if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--permission-preflight" {
            do {
                let proof=try MenuBarProcessSignature.read(getpid())
                let value:[String:Any]=["pid":getpid(),"signature":try JSONSerialization.jsonObject(with:JSONEncoder().encode(proof)),
                    "AXTrusted":AXIsProcessTrusted(),"postPermission":CGPreflightPostEventAccess(),"listenPermission":CGPreflightListenEventAccess(),
                    "permissionRequests":0,"nativePosts":0,"nativeTaps":0,"windowsOpened":0]
                print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:.sortedKeys),as:UTF8.self))
            }catch{fputs("permission preflight rejected: \(error)\n",stderr);exit(1)};return
        }
        if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--offline-tests" {
            do { try IceBaselineSessionLifetimeTests.run(); try await IceBaselineOffline.run(); try await IceBaselineCandidateTests.run(); try await IceBaselineIntegrationTests.run(); print("Ice baseline offline checks passed; native posts/taps/windows = 0") }
            catch { fputs("\(error)\n", stderr); exit(1) }; return
        }
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--session",
              CommandLine.arguments[2].hasPrefix("/tmp/mac-tools-ice-baseline-candidate-20261007/session-"),
              UUID(uuidString: URL(fileURLWithPath: CommandLine.arguments[2]).lastPathComponent.replacingOccurrences(of: "session-", with: "")) != nil else { exit(2) }
        let dir = URL(fileURLWithPath: CommandLine.arguments[2]), nonce = dir.lastPathComponent.replacingOccurrences(of: "session-", with: "")
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = IceBaselineController(directory: dir, nonce: nonce); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
