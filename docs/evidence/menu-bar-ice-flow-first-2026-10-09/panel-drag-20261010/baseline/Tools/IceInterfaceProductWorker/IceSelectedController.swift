// Copyright (c) 2026 Ryan.AI. MIT; Ice-derived linked transport GPL-3.0.
import AppKit

@MainActor final class IceSelectedController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let directory: URL, prepared: IceSelectedSession.Prepared
    var production: Bool { CommandLine.arguments.contains("--production-session") }
    let autoOwned: Bool
    var window: NSWindow!, status: NSTextField!, start: NSButton!, cancelButton: NSButton!
    let journal: IceSelectedJournal
    let shutdownApplication: () -> Void
    var anchor: NSStatusItem?, fixture: Process?, fixturePID: Int32?
    var operation: IceSelectedCoordinator?, task: Task<Void,Never>?
    var used=false, cancelled=false, running=false, quitting=false
    var readyDeadline=ProcessInfo.processInfo.systemUptime+110
    var watchdog: Timer?
    var stage="launch"
    var recoveryPending=false
    var escGlobal:Any?,escLocal:Any?
    var escObservations:[[String:Any]]=[]
    var lastMenuState="",lastMenuFileAt = -Double.infinity
    func beginEscObservation() {
        func record(_ event:NSEvent,_ source:String) {
            guard event.keyCode==53,self.running else{return}
            self.escObservations.append(["keyCode":53,"atUptime":ProcessInfo.processInfo.systemUptime,"source":source,
                "nonce":self.prepared.nonce.uuidString,"operationPhase":self.operation?.retained?.phase.rawValue ?? "none",
                "diagnosticOnly":true,"QQConsumedEscProven":false])
        }
        escGlobal=NSEvent.addGlobalMonitorForEvents(matching:.keyDown){record($0,"global")}
        escLocal=NSEvent.addLocalMonitorForEvents(matching:.keyDown){record($0,"local");return $0}
    }
    func menuObservation(_ kind:String,_ facts:[String:Any]) {
        let state=facts["state"] as? String ?? "unknown",now=ProcessInfo.processInfo.systemUptime
        if state != lastMenuState || now-lastMenuFileAt>=0.5 {
            var value=facts;value["kind"]=kind;value["escObservations"]=escObservations
            try? save("menu-observation-latest.json",value);lastMenuFileAt=now
        }
        guard state != lastMenuState else{return};lastMenuState=state
        if state=="active"{status.stringValue="已观察到目标界面；请关闭界面或切换至其他应用，随后等待15秒归位。"}
        else if state=="inactive"{status.stringValue="界面已不再占用；正在等待15秒归位。"}
        else if kind != "baseline"{status.stringValue="正在核实目标界面；若有菜单请正常关闭，普通窗口可切换至其他应用。"}
    }
    var anchorKey: String { "ice_selected_A_"+prepared.nonce.uuidString }
    init(directory:URL,prepared:IceSelectedSession.Prepared,autoOwned:Bool,
         journal: IceSelectedJournal? = nil,
         shutdownApplication: (() -> Void)? = nil) {
        self.journal = journal ?? IceSelectedSession.journal; self.shutdownApplication = shutdownApplication ?? { NSApp.terminate(nil) }
        self.directory=directory;self.prepared=prepared;self.autoOwned=autoOwned
        readyDeadline=ProcessInfo.processInfo.systemUptime+(autoOwned ? 110 : 900)
    }
    func save(_ name:String,_ value:Any) throws {try IceSelectedSession.write(value,to:directory.appendingPathComponent(name))}
    func mark(_ value:String) throws {
        stage=value;try save("stage.json",["stage":stage,"nonce":prepared.nonce.uuidString,"controllerPID":ProcessInfo.processInfo.processIdentifier,"atUnix":Date().timeIntervalSince1970])
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:230),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title=production ? "MacTools · 菜单栏图标恢复" : "MacTools · Ice 快速功能验证";window.center();window.delegate=self
        let label=NSTextField(wrappingLabelWithString: prepared.selfOwned ? "仅操作自建 T。按 Ice 流程搬出、打开菜单、关闭及归位。\n会短暂影响焦点和光标；正式版保持不变。" : "仅操作预先选定的一个图标。搬出并打开界面后，请关闭该界面或切换至其他应用。\n等待15秒后归位；取消会停止后续操作。")
        label.frame=NSRect(x:20,y:130,width:560,height:80);window.contentView?.addSubview(label)
        status=NSTextField(wrappingLabelWithString:"正在准备自有锚点与目标身份…")
        status.frame=NSRect(x:20,y:65,width:560,height:60);window.contentView?.addSubview(status)
        start=NSButton(title:"开始单轮",target:self,action:#selector(begin));start.frame=NSRect(x:20,y:20,width:180,height:32);start.isEnabled=false;window.contentView?.addSubview(start)
        let cancel=NSButton(title:"取消并关闭",target:self,action:#selector(stop));cancel.frame=NSRect(x:220,y:20,width:180,height:32);window.contentView?.addSubview(cancel);cancelButton=cancel
        if !production { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
        watchdog=Timer(timeInterval:0.25,repeats:true){[weak self] _ in MainActor.assumeIsolated {
            guard let self,!self.quitting else{return}
            if !self.used,ProcessInfo.processInfo.systemUptime>=self.readyDeadline {self.stop()}
        }};RunLoop.main.add(watchdog!,forMode:.common)
        task=Task {do {
            try Task.checkCancellation();guard !cancelled,!quitting else{throw IceBaselineError.cancelled}
            try mark("package");_ = try IceSelectedSession.verifyPackage();try IceSelectedSession.requireNoOtherWorker()
            guard CGPreflightPostEventAccess(),CGPreflightListenEventAccess(),AXIsProcessTrusted() else{throw IceBaselineError.source}
            try Task.checkCancellation();guard !cancelled,!quitting else{throw IceBaselineError.cancelled}
            try mark("anchor-create")
            UserDefaults.standard.set(0,forKey:"NSStatusItem Preferred Position "+anchorKey)
            let a=NSStatusBar.system.statusItem(withLength:0);a.autosaveName=anchorKey;a.button?.title="A";a.button?.toolTip="本轮自有可见锚点";a.length=NSStatusItem.variableLength;anchor=a
            if prepared.selfOwned {try await launchFixture()}
            try Task.checkCancellation();guard !cancelled,!quitting else{throw IceBaselineError.cancelled}
            try mark("ready");start.isEnabled=true;status.stringValue="已就绪；只运行一次，按 Ice 邻居边缘归位；完整队列仅诊断。"
            try save("ready.json",["nonce":prepared.nonce.uuidString,"pid":ProcessInfo.processInfo.processIdentifier,"fixturePID":fixturePID as Any? ?? NSNull(),"strictANYRequired":false,"hitTestRequired":false,"nativePosts":0,"windowNumber":window.windowNumber,"windowVisible":window.isVisible,"productionMode":production,"automaticStart":production,"windowKey":window.isKeyWindow,"frontPID":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1])
            if CommandLine.arguments.contains("--owned-entry-cancel-check") {cancelButton.performClick(nil)}
            else if autoOwned || production {begin()}
        } catch {await finish(["realClosedLoopVerified":false,"posts":0,"stage":stage,"failure":String(describing:error)])}}
    }
    func owner() throws -> [String:Any] {
        let bytes=try Data(contentsOf:directory.appendingPathComponent("owner-state/latest.json"))
        guard bytes.count<256000,let d=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],d["nonce"] as? String==prepared.nonce.uuidString,
              d["pid"] as? Int32==fixturePID,let at=d["atUnix"] as? Double,(0...1).contains(Date().timeIntervalSince1970-at),
              d["phase"] as? String=="timer",d["bundlePath"] as? String==IceSelectedSession.packageRoot.appendingPathComponent("Ice Selected Fixture.app").path else{throw IceBaselineError.identity}
        return d
    }
    func lifetime(_ action:String) async throws {
        guard let pid=fixturePID else{throw IceBaselineError.identity}
        let id=UUID().uuidString
        try save("owner-state/lifetime-request.json",["nonce":prepared.nonce.uuidString,"fixturePID":pid,"controllerPID":ProcessInfo.processInfo.processIdentifier,"atUnix":Date().timeIntervalSince1970,"request":id,"action":action])
        let until=ProcessInfo.processInfo.systemUptime+2
        while ProcessInfo.processInfo.systemUptime<until {
            if let d=try? owner(),let c=d["menuControl"] as? [String:Any],let state=c["lifetime"] as? [String:Any],state["acknowledgment"] as? String==id {return}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw IceBaselineError.timeout
    }
    func launchFixture() async throws {
        try mark("fixture-launch")
        try FileManager.default.createDirectory(at:directory.appendingPathComponent("owner-state"),withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let p=Process();p.executableURL=IceSelectedSession.packageRoot.appendingPathComponent("Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture")
        if (CommandLine.arguments.contains("--self-owned-window-run") || CommandLine.arguments.contains("--owned-window-session")) {var env=ProcessInfo.processInfo.environment;env["MAC_TOOLS_OWNED_ORDINARY_INTERFACE"]="1";p.environment=env}
        p.arguments=["--diagnostic-directory",directory.appendingPathComponent("owner-state").path,"--diagnostic-nonce",prepared.nonce.uuidString]
        for (name,key) in [("fixture.stdout",true),("fixture.stderr",false)] {
            let u=directory.appendingPathComponent(name);FileManager.default.createFile(atPath:u.path,contents:nil)
            let h=try FileHandle(forWritingTo:u);if key{p.standardOutput=h}else{p.standardError=h}
        }
        try Task.checkCancellation();guard !cancelled,!quitting else{throw IceBaselineError.cancelled}
        try p.run();fixture=p;fixturePID=p.processIdentifier
        let until=ProcessInfo.processInfo.systemUptime+5
        while (try? owner())==nil {
            guard p.isRunning,ProcessInfo.processInfo.systemUptime<until,!cancelled else{throw IceBaselineError.identity}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let manifest=try IceSelectedSession.verifyPackage(),proof=try MenuBarProcessSignature.read(p.processIdentifier)
        guard proof.identifier=="com.ryanai.mactools.nativetargets",proof.team=="58TJ64422P",proof.sha256==manifest["fixtureSHA256"] as? String,proof.executable==p.executableURL?.path else{throw IceBaselineError.identity}
        try await lifetime("ready")
    }
    func selectedTarget() throws -> MenuBarIceSelectedTarget {
        let screens=NSScreen.screens
        try? save("scope-directory-entry.json",["nonce":prepared.nonce.uuidString,"stage":stage,"atUptime":ProcessInfo.processInfo.systemUptime,
            "screens":screens.map{["display":($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,"frame":NSStringFromRect($0.frame)]},
            "preparedDisplay":prepared.selected?.display as Any? ?? NSNull(),"preparedSpace":prepared.selected?.space as Any? ?? NSNull()])
        let d:MenuBarIceSelectedTarget.Directory
        do{d=try MenuBarIceSelectedTarget.readDirectory()}catch{
            try? save("scope-directory-rejected.json",["error":String(describing:error),"errorType":String(reflecting:type(of:error)),"atUptime":ProcessInfo.processInfo.systemUptime]);throw error
        }
        if let old=prepared.selected {
            let proof=try MenuBarProcessSignature.read(old.owner.pid)
            try save("scope-guard-current.json",["nonce":old.nonce.uuidString,"atUptime":ProcessInfo.processInfo.systemUptime,
                "expectedDisplay":old.display,"actualDisplay":d.display,"expectedSpace":old.space,"actualSpace":d.space,
                "ownerMatches":proof==old.owner,"displayMatches":old.display==d.display,"spaceMatches":old.space==d.space,
                "windowID":old.windowID,"matchedRows":d.rows.filter{$0.id==old.windowID}.map{["id":$0.id,"pid":$0.pid,"frame":NSStringFromRect($0.frame)]}])
            let row=try old.validate(directory:d,owner:proof)
            // Own anchor construction precedes operation baseline. Same exact
            // window/launch/nonce is retained; setup reflow is recorded separately.
            return try .init(row:row,directory:d,owner:old.owner,nonce:old.nonce)
        }
        let state=try owner()
        guard let before=state["modelsBefore"] as? [[String:Any]],let after=state["modelsAfter"] as? [[String:Any]],
              let t=after.first(where:{$0["title"] as? String=="T"}),let id=t["windowNumber"] as? UInt32,
              let instance=t["itemInstance"] as? String,UUID(uuidString:instance) != nil,
              before.contains(where:{$0["windowNumber"] as? UInt32==id && $0["itemInstance"] as? String==instance}),
              let row=d.rows.first(where:{$0.id==id && $0.pid==fixturePID}) else{throw IceBaselineError.identity}
        return try .init(row:row,directory:d,owner:MenuBarProcessSignature.read(row.pid),nonce:prepared.nonce)
    }
    @objc func begin() {
        guard !used,!cancelled,start.isEnabled else{return};used=true;running=true;start.isEnabled=false
        task=Task {do {
            try mark("plan")
            guard let id=anchor?.button?.window?.windowNumber,id>0 else{throw IceBaselineError.geometry}
            let windows=try IceBaselineWindows(),first=try selectedTarget()
            try await Task.sleep(nanoseconds:150_000_000)
            let second=try selectedTarget();guard first==second else{throw IceBaselineError.geometry}
            let plan=try IceSelectedPlan(selected:second,anchorID:UInt32(id),windows:windows,quick:true,diagnostics:{name,facts in try? self.save("plan-"+name+".json",facts)})
            try save("plan.json",try JSONSerialization.jsonObject(with:JSONEncoder().encode(plan.binding)))
            try save("setup.json",["selectionBeforeAnchor":prepared.selected.map{try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0))} as Any? ?? NSNull(),"activeBaseline":try JSONSerialization.jsonObject(with:JSONEncoder().encode(second)),"inputPolicy":"iceMouseTracking","strictANYRequired":false,"hitTestRequired":false])
            if prepared.selfOwned {try await lifetime("begin")}
            guard !cancelled else{throw IceBaselineError.cancelled}
            try save("action-consumed.json",["nonce":prepared.nonce.uuidString,"atUnix":Date().timeIntervalSince1970,"selfOwned":prepared.selfOwned]);try mark("execute")
            status.stringValue=prepared.selfOwned ? "正在验证自建 T 闭环…" : "正在搬出图标；界面出现后请关闭或切换至其他应用。"
            let close:(() async throws -> Void)? = prepared.selfOwned ? { [self] in
                if (CommandLine.arguments.contains("--self-owned-window-run") || CommandLine.arguments.contains("--owned-window-session")) {
                    // Only this owned fixture test explicitly hands focus back to
                    // its own controller before closing the last regular window.
                    // Otherwise macOS can reactivate a previous fullscreen app.
                    window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                    let focusLimit=ProcessInfo.processInfo.systemUptime+2
                    while NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier || !window.isKeyWindow {
                        guard !cancelled,ProcessInfo.processInfo.systemUptime<focusLimit else{throw IceBaselineError.identity}
                        try await Task.sleep(nanoseconds:50_000_000)
                    }
                    try save("owned-window-focus-handoff.json",["nonce":prepared.nonce.uuidString,"controllerPID":ProcessInfo.processInfo.processIdentifier,"windowID":window.windowNumber,"frontmostPID":NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull(),"nativePosts":0])
                }
                let until=ProcessInfo.processInfo.systemUptime+2
                while ProcessInfo.processInfo.systemUptime<until {
                    if let state=try? owner(),let c=state["menuControl"] as? [String:Any],let g=c["generation"] as? Int,c["openKey"] as? String=="mactools_native_acceptance_T",let pid=fixturePID {
                        try save("owner-state/cancel-request.json",["nonce":prepared.nonce.uuidString,"pid":pid,"atUnix":Date().timeIntervalSince1970,"request":UUID().uuidString,"generation":g,"itemKey":"mactools_native_acceptance_T"]);return
                    }
                    try await Task.sleep(nanoseconds:100_000_000)
                };throw IceBaselineError.menu
            } : nil
            beginEscObservation()
            let result=try await IceSelectedWorkflow.runNative(plan,journal:journal,onCoordinator:{self.operation=$0},quick:true,selfOwnedConsumerDelay:CommandLine.arguments.contains("--self-owned-receiver-lag-run") && prepared.selfOwned,onMenuObservation:{[weak self] kind,facts in self?.menuObservation(kind,facts)},afterMenuOpened:close)
            await finish(result)
        } catch {await finish(["realClosedLoopVerified":false,"posts":0,"stage":stage,"failure":String(describing:error)])}}
    }
    @objc func verifyManualRecovery() {
        guard recoveryPending,!quitting else{return};start.isEnabled=false
        Task {do {
            guard let record=try journal.inspect() else{throw IceSelectedFailure.binding}
            guard IceSelectedManualRecovery.eligible(record) else {
                status.stringValue="本轮已结束；恢复记录已保留，此记录不支持旧版人工归位核销。"
                start.title="本轮已结束";start.isEnabled=false;return
            }
            let receipt=try await IceSelectedManualRecovery.archive(journal,nonce:record.binding.nonce,expectedHash:IceSelectedOwnedRecovery.digest(record))
            try save("manual-recovery.json",try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt)))
            recoveryPending=false;quitting=true;await cleanup()
        } catch {status.stringValue="尚未确认原相对位置或菜单/按钮状态；记录保留。";start.isEnabled=true}}
    }
    @objc func stop() {
        guard !quitting else{return}
        if recoveryPending {quitting=true;task?.cancel();Task{await cleanup()};return};cancelled=true;start.isEnabled=false;operation?.cancel();task?.cancel()
        if !running {Task{await finish(["realClosedLoopVerified":false,"posts":0,"stage":stage,"failure":"cancelledBeforeStart"])}}
    }
    func finish(_ result:[String:Any]) async {
        var value=result;value["nonce"]=prepared.nonce.uuidString;value["diagnosticUserEscObservations"]=escObservations
        guard !quitting else{return};running=false;watchdog?.invalidate()
        if !prepared.selfOwned,let record=try? journal.inspect(),record.phase == .stopped {
            try? save("result.json",value);recoveryPending=true;task=nil
            status.stringValue=record.needsRelease ? "投递配对未确认；已停止并保留责任，不能自动清除。" : "已停止。正常关闭菜单、松开鼠标；按Command仅拖回选定图标至原邻居同一侧，再确认归位。"
            if [.ordinaryIceQuickV4, .ordinaryIceInterfaceV9].contains(record.contract) {
                status.stringValue=record.needsRelease ? "本轮已停止，投递配对未确认；原始记录已保留。" : "本轮已停止，未完成Ice归位；原始记录已保留。"
                start.title="本轮已结束";start.isEnabled=false
            } else {
                start.title="确认人工归位";start.action=#selector(verifyManualRecovery);start.isEnabled = !record.needsRelease
            }
            if production { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
            return
        }
        quitting=true
        do{try save("result.json",value)}catch{fputs("result save failed: \(error)\n",stderr)}
        // Cleanup runs in its own uncancelled task; a cancelled operation cannot
        // spin the main run loop or prevent the fixture's bounded cleanup.
        await Task { @MainActor in await self.cleanup() }.value
    }
    func cleanup() async {
        // Cleanup does not issue input or clear a pending responsibility record.
        if let escGlobal{NSEvent.removeMonitor(escGlobal)};if let escLocal{NSEvent.removeMonitor(escLocal)}
        escGlobal=nil;escLocal=nil
        if let pid=fixturePID {
            try? await lifetime("terminal")
            try? save("owner-state/quit-request.json",["nonce":prepared.nonce.uuidString,"pid":pid,"atUnix":Date().timeIntervalSince1970,"request":UUID().uuidString])
            let until=ProcessInfo.processInfo.systemUptime+16
            while fixture?.isRunning==true,ProcessInfo.processInfo.systemUptime<until {try? await Task.sleep(nanoseconds:100_000_000)}
        }
        if let anchor{NSStatusBar.system.removeStatusItem(anchor)}
        UserDefaults.standard.removeObject(forKey:"NSStatusItem Preferred Position "+anchorKey)
        var cleanup:[String:Any]=["fixtureExited":fixture?.isRunning != true,"installedSHA256":(try? IceSelectedSession.hash(URL(fileURLWithPath:"/Applications/MacTools.app/Contents/MacOS/MacTools"))) ?? "unknown","atUnix":Date().timeIntervalSince1970]
        do {cleanup["journalPending"]=try journal.inspect() != nil}
        catch {cleanup["journalPending"]=NSNull();cleanup["journalInspectError"]=String(describing:error)}
        try? save("cleanup.json",cleanup)
        window?.orderOut(nil);shutdownApplication()
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {stop();return false}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {if quitting{return .terminateNow};stop();return .terminateCancel}
}
@main struct IceSelectedControllerMain {
    @MainActor static func emit(_ value:Any) throws {print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))}
    @MainActor static func main() {
        let args=CommandLine.arguments
        if args.contains("--product-stop-ui-checks") {
            Task { @MainActor in do { _ = try IceSelectedSession.verifyPackage();try emit(try await IceProductStopChecks.run());exit(0) }
                catch {fputs("product stop checks failed: \(error)\n",stderr);exit(1)} }
            RunLoop.main.run();return
        }
        if args.contains("--native-interface-tests") {
            Task { @MainActor in do {try emit(try await IceInterfaceNativeChecks.run());exit(0)}catch{fputs("native interface checks failed: \(error)\n",stderr);exit(1)}}
            RunLoop.main.run();return
        }
        if args.contains("--rehide-delay-tests") {
            Task { @MainActor in do { try emit(try await IceRehideDelayChecks.run()); exit(0) }
                catch { fputs("rehide delay checks failed: \(error)\n", stderr); exit(1) } }
            RunLoop.main.run(); return
        }
        if args.contains("--dispatch-validation-tests") {
            Task { @MainActor in do { try emit(try await IceDispatchValidationChecks.run()); exit(0) }
                catch { fputs("dispatch validation checks failed: \(error)\n", stderr); exit(1) } }
            RunLoop.main.run(); return
        }
        if args.contains("--offline-tests") {
            Task{@MainActor in do{try emit(try await IceSelectedOfflineChecks.runAll());exit(0)}catch{fputs("offline failed: \(error)\n",stderr);exit(1)}}
            RunLoop.main.run();return
        }
        do {
            if args.count==2,args[1]=="--receiver-zero-input-checks" {
                Task{@MainActor in do{try emit(try await IceReceiverChecks.zeroInput());exit(0)}catch{fputs("receiver checks refused: \(error)\n",stderr);exit(1)}}
                RunLoop.main.run();return
            }
            if args.count==2,args[1]=="--tap-lifecycle-observation" {
                _ = try IceSelectedSession.verifyPackage()
                Task{@MainActor in do{try emit(try await IceTapLifecycleObservation.run());exit(0)}catch{fputs("tap lifecycle refused: \(error)\n",stderr);exit(1)}}
                RunLoop.main.run();return
            }
            if args.contains("--permissions") {try emit(["post":CGPreflightPostEventAccess(),"listen":CGPreflightListenEventAccess(),"ax":AXIsProcessTrusted(),"permissionRequests":0]);return}
            if args.contains("--inspect-recovery") {
                let record=try IceSelectedSession.journal.inspect()
                try emit(["journalPending":record != nil,"nonce":record?.binding.nonce.uuidString as Any? ?? NSNull(),"recordSHA256":try record.map{try IceSelectedOwnedRecovery.digest($0)} as Any? ?? NSNull(),"unconfirmedDown":record?.needsRelease ?? false]);return
            }
            if args.count==4,args[1]=="--confirm-manual-return",let nonce=UUID(uuidString:args[2]),IceSelectedBinding.validHash(args[3]) {
                _ = try IceSelectedSession.verifyPackage()
                Task{@MainActor in do {
                    let receipt=try await IceSelectedManualRecovery.archive(IceSelectedSession.journal,nonce:nonce,expectedHash:args[3])
                    try emit(try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt)));exit(0)
                }catch{fputs("manual recovery refused: \(error)\n",stderr);exit(1)}}
                RunLoop.main.run();return
            }
            if args.count==4,args[1]=="--retire-owned-departed",let nonce=UUID(uuidString:args[2]),IceSelectedBinding.validHash(args[3]) {
                _ = try IceSelectedSession.verifyPackage()
                Task{@MainActor in do {
                    let receipt=try await IceSelectedOwnedRecovery.retire(IceSelectedSession.journal,nonce:nonce,expectedHash:args[3])
                    try emit(try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt)));exit(0)
                } catch {fputs("owned retirement refused: \(error)\n",stderr);exit(1)}}
                RunLoop.main.run();return
            }
            if args.contains("--directory") {let d=try MenuBarIceSelectedTarget.readDirectory();try emit(["display":d.display,"space":d.space,"rows":d.rows.map{["id":$0.id,"pid":$0.pid,"title":$0.title,"x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height]}]);return}
            if args.count==3,args[1]=="--prepare-target",let id=UInt32(args[2]) {try emit(["session":try IceSelectedSession.prepare(windowID:id).path,"posts":0]);return}
            if args.count==2,args[1]=="--prepare-owned" {try emit(["session":try IceSelectedSession.prepare(windowID:nil).path,"posts":0]);return}
            let autoOwned=args.count==2 && ["--self-owned-run","--self-owned-receiver-lag-run","--self-owned-window-run"].contains(args[1])
            let directory:URL
            if autoOwned {directory=try IceSelectedSession.prepare(windowID:nil)}
            else if (args.count==3 || (args.count==4 && ["--owned-entry-cancel-check","--owned-window-session","--production-session"].contains(args[3]))),args[1]=="--session" {directory=URL(fileURLWithPath:args[2])}
            else{throw IceSelectedFailure.policy}
            let prepared=try IceSelectedSession.load(directory)
            guard !args.contains("--production-session") || (!prepared.selfOwned && prepared.selected != nil) else{throw IceSelectedFailure.policy}
            guard !autoOwned || prepared.selfOwned else{throw IceSelectedFailure.policy}
            guard !args.contains("--owned-window-session") || prepared.selfOwned else{throw IceSelectedFailure.policy}
            if args.contains("--owned-entry-cancel-check"),!prepared.selfOwned {
                let m=try IceSelectedSession.verifyPackage()
                guard let target=prepared.selected,target.owner.identifier=="com.ryanai.mactools.producttargets",target.owner.team=="58TJ64422P",
                      target.owner.executable==IceSelectedSession.packageRoot.appendingPathComponent("Ice Product Targets.app/Contents/MacOS/IceProductTargets").path,
                      target.owner.sha256==m["productTargetSHA256"] as? String else{throw IceSelectedFailure.policy}
            }
            try emit(["session":directory.path,"selfOwned":prepared.selfOwned,"autoStart":autoOwned])
            let app=NSApplication.shared;app.setActivationPolicy(args.contains("--production-session") ? .accessory : .regular)
            let delegate=IceSelectedController(directory:directory,prepared:prepared,autoOwned:autoOwned);app.delegate=delegate
            withExtendedLifetime(delegate){app.run()}
        }catch{fputs("selected candidate: \(error)\n",stderr);exit(1)}
    }
}
