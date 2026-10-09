// Copyright (c) 2026 Ryan.AI. MIT. Own windows/status items only; no mouse/AX actions.
import AppKit
@MainActor enum IceInterfaceNativeChecks {
    enum Failure:Error {case assertion(String)}
    static func run()async throws->[String:Any] {
        let app=NSApplication.shared;app.setActivationPolicy(.regular);app.finishLaunching()
        let proof=try IceSelectedBinding.Process(MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier))
        let runtime=try IceSelectedRuntime([proof]);try runtime.checkFullSignatures()
        let api=try IceBaselineWindows()
        func scope()->(UInt32,UInt) {((NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,api.activeSpace(api.connection()))}
        var items:[NSStatusItem]=[],windows:[NSWindow]=[],records:[[String:Any]]=[],assertions=0
        defer{windows.forEach{$0.orderOut(nil);$0.close()};items.forEach{NSStatusBar.system.removeStatusItem($0)}}
        for title in ["T","N"] {let i=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);i.button?.title=title;items.append(i)}
        func require(_ value:Bool,_ why:String)throws {assertions+=1;guard value else{throw Failure.assertion(why)}}
        func settle()async throws {try await Task.sleep(nanoseconds:160_000_000)}
        func window(_ title:String)->NSWindow {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:180),styleMask:[.titled],backing:.buffered,defer:false)
            w.title=title;w.isReleasedWhenClosed=false;w.center();windows.append(w);return w
        }
        func lease(_ name:String)throws->IceSelectedInterfaceLease {
            let s=scope(),nonce=UUID()
            let l=IceSelectedInterfaceLease.live(owner:proof,nonce:nonce,display:s.0,space:s.1,scope:scope,identity:{(try? runtime.check()) != nil},trace:{kind,facts in var row=facts;row["test"]=name;row["traceKind"]=kind;records.append(row)})
            try l.beginLive();return l
        }
        let hidden=try lease("ordinaryHidden")
        let w=window("MacTools 自建普通窗口 · 隐藏验证");w.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);try await settle()
        try require(hidden.refresh() == .active,"real own ordinary window active")
        w.orderOut(nil);try await settle();try require(hidden.refresh() == .unknown,"first native absent sample")
        try await settle();try require(hidden.refresh() == .inactive,"second native absent sample")
        let hiddenProof=try hidden.confirmation();try require(hiddenProof.kind == .ordinaryWindow && hiddenProof.nativeObservation,"typed native ordinary proof")
        w.close()
        let defocused=try lease("ordinaryDefocused")
        let d=window("MacTools 自建普通窗口 · 失焦验证");d.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);try await settle()
        try require(defocused.refresh() == .active,"ordinary interface initially active")
        let focus=Process(),focusNonce=UUID().uuidString
        let focusFile=URL(fileURLWithPath:"/tmp/ice-interface-focus-"+focusNonce+".json")
        focus.executableURL=IceSelectedSession.packageRoot.appendingPathComponent("Ice Interface Focus.app/Contents/MacOS/IceInterfaceFocus")
        focus.arguments=[focusNonce,focusFile.path];try focus.run()
        defer{if focus.isRunning {focus.terminate()}}
        let focusProof=try MenuBarProcessSignature.read(focus.processIdentifier)
        let manifest=try IceSelectedSession.verifyPackage()
        try require(focusProof.team=="58TJ64422P" && focusProof.executable==focus.executableURL?.path && focusProof.sha256==manifest["focusSHA256"] as? String,"exact owned focus helper signature")
        let until=ProcessInfo.processInfo.systemUptime+3
        var actualFocus=false
        while ProcessInfo.processInfo.systemUptime<until {
            if let bytes=try? Data(contentsOf:focusFile),let row=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
               row["nonce"] as? String==focusNonce,row["pid"] as? Int32==focus.processIdentifier,row["active"] as? Bool==true,
               NSWorkspace.shared.frontmostApplication?.processIdentifier==focus.processIdentifier {actualFocus=true;break}
            try await settle()
        }
        try require(actualFocus && !NSRunningApplication.current.isActive,"second own app actually holds focus")
        try require(defocused.refresh() == .unknown,"first real defocus sample")
        try await settle();try require(defocused.refresh() == .inactive,"still visible ordinary interface inactive after defocus")
        d.orderOut(nil);d.close()
        let multiple=try lease("multipleOwnerWindows")
        let a=window("MacTools 自建窗口 A"),b=window("MacTools 自建窗口 B");a.orderFront(nil);b.orderFront(nil);app.activate(ignoringOtherApps:true);try await settle()
        try require(multiple.refresh() == .active && multiple.diagnostics()["stickyInvalid"] as? Bool==false,"first real same-owner window tracked without extra ambiguity rejection")
        a.orderOut(nil);a.close();b.orderOut(nil);b.close();try await settle()
        let rebuilt=try lease("windowRebuilt")
        let old=window("MacTools 自建原窗口");old.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);try await settle()
        try require(rebuilt.refresh() == .active,"original native window tracked")
        let oldID=UInt32(old.windowNumber)
        old.orderOut(nil);old.close();let replacement=window("MacTools 自建重建窗口");replacement.makeKeyAndOrderFront(nil);try await settle()
        try require(rebuilt.refresh() == .unknown && rebuilt.diagnostics()["stickyInvalid"] as? Bool==false,"absent original tracked window first inactive sample")
        try await settle();try require(rebuilt.refresh() == .inactive && rebuilt.diagnostics()["trackedWindowID"] as? UInt32 == oldID,"replacement cannot replace original tracked ID; original context ends")
        replacement.orderOut(nil);replacement.close()
        let fence=IceSelectedFence();fence.cancel();var admissions=0,denied=false
        do{try fence.perform("cancelled-input-admission"){admissions+=1}}catch{denied=true}
        try require(denied && admissions==0,"cancelled generation cannot admit any input operation")
        try runtime.checkFullSignatures()
        items.forEach{NSStatusBar.system.removeStatusItem($0)};items=[];try await settle()
        return ["scenarios":5,"assertions":assertions,"nativePosts":0,"AXActions":0,"permissionRequests":0,
                "ownedTNCreatingAndRemoving":true,"records":records,"ordinaryHiddenEvidence":try JSONSerialization.jsonObject(with:JSONEncoder().encode(hiddenProof)),"cancelledInputAdmissions":admissions,"thirdPartyActions":0,"focusHelperPID":focus.processIdentifier]
    }
}
