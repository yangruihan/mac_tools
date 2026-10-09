// Copyright (c) 2026 Ryan.AI. MIT. Reused acceptance T/N plus a visible owned anchor.
import AppKit

@MainActor
final class IceSelectedFixture: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var items: [NSStatusItem] = [], anchor: NSStatusItem?, divider: NSStatusItem?, diagnostic: NativeAcceptanceTargetsDiagnostic?
    var openKey: String?, generation = 0, closedGeneration = 0, acknowledged: String?
    var seen: Set<String> = []
    var lifetime = IceBaselineSessionLifetime(now: ProcessInfo.processInfo.systemUptime)
    var originalPositions: [String: Double] = [:]
    var seenLifetimeRequests: Set<String> = []
    var controllerProof: MenuBarProcessSignature.Proof?
    var terminalWritten = false
    let ordinaryMode=ProcessInfo.processInfo.environment["MAC_TOOLS_OWNED_ORDINARY_INTERFACE"]=="1"
    var ordinaryWindow:NSWindow?
    let directory = URL(fileURLWithPath: CommandLine.arguments[2]), nonce = CommandLine.arguments[4]
    var anchorPositionKey: String { "NSStatusItem Preferred Position ice_baseline_H_\(nonce)" }
    var dividerPositionKey: String { "NSStatusItem Preferred Position ice_baseline_D_\(nonce)" }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for title in ["T", "N"] {
            let key = "NSStatusItem Preferred Position mactools_native_acceptance_\(title)"
            if let value = UserDefaults.standard.object(forKey: key) as? Double { originalPositions[key] = value }
        }
        let oldPositions = ["T", "N"].compactMap { UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position mactools_native_acceptance_\($0)") as? Double }
        // Same normal T/N construction, stable autosave names and menu content as
        // MenuBarNativeAcceptanceTargets.swift / the successful original Ice round.
        for title in ["T", "N"] {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.autosaveName = "mactools_native_acceptance_\(title)"; i.button?.title = title
            i.button?.toolTip = "MacTools 自建验收图标 \(title)"
            let menu = NSMenu(title: title); menu.delegate = self
            menu.addItem(NSMenuItem(title: "自建目标 \(title)", action: nil, keyEquivalent: "")); i.menu = menu
            // Keep the established native status-item drag wrapper; the owned T menu transitions to an ordinary window below.
            items.append(i)
        }
        // Ice ControlItem seeds its own visible icon at position 0, obtains its
        // button/window, then sets length. Scope this preference to one new H key
        // in the fixture domain, never formal/third-party or existing T/N keys.
        UserDefaults.standard.set(0, forKey: anchorPositionKey)
        let h = NSStatusBar.system.statusItem(withLength: 0)
        h.autosaveName = "ice_baseline_H_\(nonce)"
        h.button?.title = "H"; h.button?.toolTip = "自建可见锚点 H；不隐藏任何图标"
        h.length = NSStatusItem.variableLength; anchor = h
        // Ice has separate visible and hidden controls. Place our hidden control
        // immediately right of the restored T/N pair; do not toggle formal bars.
        // Missing legacy positions are an explicit setup refusal, never guesses.
        if oldPositions.count == 2, oldPositions.allSatisfy({ $0.isFinite && $0 > 1 && $0 < 100_000 }), let rightmost = oldPositions.min() {
            UserDefaults.standard.set(rightmost - 1, forKey: dividerPositionKey)
            let d = NSStatusBar.system.statusItem(withLength: 0)
            d.autosaveName = "ice_baseline_D_\(nonce)"; d.button?.title = "D"
            d.button?.cell?.isEnabled = false
            d.length = min(10_000, max(500, (NSScreen.screens.map { $0.frame.width }.max() ?? 1728) * 2))
            divider = d
        }
        diagnostic = NativeAcceptanceTargetsDiagnostic.configured { [weak self] in self?.items ?? [] }
        diagnostic?.extraState = { [weak self] in
            guard let self else { return [:] }; return ["openKey": self.openKey as Any? ?? NSNull(),
                "generation": self.generation, "closedGeneration": self.closedGeneration,
                "cancelAcknowledged": self.acknowledged as Any? ?? NSNull(),
                "visibleAnchorModel": self.anchor.map { self.diagnostic?.model($0) ?? [:] } ?? [:],
                "anchorPreferenceKey": self.anchorPositionKey, "anchorPreferenceSeed": 0,
                "dividerModel": self.divider.map { self.diagnostic?.model($0) ?? [:] } ?? [:],
                "dividerPreferenceKey": self.dividerPositionKey,
                "wideSpacerCreated": self.divider != nil,
                "lifetime": self.lifetime.snapshot(now: ProcessInfo.processInfo.systemUptime)]
        }
        diagnostic?.beforeTick = { [weak self] in self?.control() }; diagnostic?.start()
        diagnostic?.budgetReached = { [weak self] in self?.finish(reason: "publisherAbsoluteDeadline") }
    }
    @objc func openOrdinary() {
        guard ordinaryMode,openKey==nil else{return}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="MacTools 自建普通界面 T";window.center();window.isReleasedWhenClosed=false
        ordinaryWindow=window;openKey="mactools_native_acceptance_T";generation+=1
        NSApp.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func menuWillOpen(_ menu: NSMenu) {
        if ordinaryMode && menu.title=="T" {
            DispatchQueue.main.async { [weak self] in
                menu.cancelTrackingWithoutAnimation();self?.openOrdinary()
            }
            return
        }
        openKey = "mactools_native_acceptance_\(menu.title)"; generation += 1 }
    func menuDidClose(_ menu: NSMenu) { openKey = nil; closedGeneration = generation }
    func control() {
        let now = ProcessInfo.processInfo.systemUptime
        lifetime.tick(now: now)
        if lifetime.phase == .finished { finish(reason: lifetime.reason); return }
        let lifecycleFile = directory.appendingPathComponent("lifetime-request.json")
        if let data = try? Data(contentsOf: lifecycleFile), data.count < 8192,
           let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let request = try? IceBaselineSessionLifetime.Request(r, nonce: nonce,
                fixturePID: ProcessInfo.processInfo.processIdentifier, now: Date().timeIntervalSince1970),
           !seenLifetimeRequests.contains(request.id) {
            seenLifetimeRequests.insert(request.id)
            do {
                let root = directory.deletingLastPathComponent().deletingLastPathComponent()
                guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("prepared-build.json"))) as? [String: Any] else { throw IceBaselineSessionLifetime.Failure.phase }
                let proof = try MenuBarProcessSignature.read(request.controllerPID)
                guard proof.identifier == "com.ryanai.mactools", proof.sha256 == manifest["controllerSHA256"] as? String,
                      proof.executable == root.appendingPathComponent("Ice Selected Controller.app/Contents/MacOS/IceSelectedController").resolvingSymlinksInPath().path,
                      controllerProof == nil || controllerProof == proof else { throw IceBaselineSessionLifetime.Failure.phase }
                controllerProof = proof; try lifetime.accept(request.action, request: request.id, now: now)
            } catch { fputs("fixture lifetime request refused: \(error)\n", stderr) }
        }
        let quitFile = directory.appendingPathComponent("quit-request.json")
        if let data = try? Data(contentsOf: quitFile), data.count < 4096,
           let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           r["nonce"] as? String == nonce, r["pid"] as? Int32 == ProcessInfo.processInfo.processIdentifier,
           let at = r["atUnix"] as? Double, (0...1).contains(Date().timeIntervalSince1970 - at),
           let id = r["request"] as? String, UUID(uuidString: id) != nil, openKey == nil {
            finish(reason: "ownedQuitRequest"); return
        }
        let file = directory.appendingPathComponent("cancel-request.json")
        guard lifetime.phase == .active, let data = try? Data(contentsOf: file), data.count < 4096,
              let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              r["nonce"] as? String == nonce, r["pid"] as? Int32 == ProcessInfo.processInfo.processIdentifier,
              let id = r["request"] as? String, UUID(uuidString: id) != nil, !seen.contains(id),
              let at = r["atUnix"] as? Double, (0...1).contains(Date().timeIntervalSince1970 - at),
              r["generation"] as? Int == generation, r["itemKey"] as? String == openKey,
              let i = items.first(where: { $0.autosaveName == openKey }) else { return }
        seen.insert(id)
        if ordinaryMode {ordinaryWindow?.orderOut(nil);ordinaryWindow?.close();ordinaryWindow=nil;openKey=nil;closedGeneration=generation}
        else {i.menu?.cancelTrackingWithoutAnimation()}
        acknowledged = id
    }
    func finish(reason: String) {
        writeTerminal(reason: reason)
        NSApp.terminate(nil)
    }
    func writeTerminal(reason: String) {
        guard !terminalWritten else { return }; terminalWritten = true
        let record: [String: Any] = ["nonce":nonce,"pid":ProcessInfo.processInfo.processIdentifier,
            "reason":reason,"lifetime":lifetime.snapshot(now: ProcessInfo.processInfo.systemUptime),
            "menuOpenKey":openKey as Any? ?? NSNull(),"nativeReturnProven":false,"physicalReleaseProven":false,
            "originalOwnPositionValues":originalPositions]
        do { try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: directory.appendingPathComponent("lifetime-terminal.json"), options: .atomic) }
        catch { fputs("fixture terminal evidence save failed: \(error)\n", stderr) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        writeTerminal(reason: "applicationWillTerminate")
        ordinaryWindow?.orderOut(nil);ordinaryWindow?.close();ordinaryWindow=nil
        diagnostic?.stop(); items.forEach { NSStatusBar.system.removeStatusItem($0) }
        if let anchor { NSStatusBar.system.removeStatusItem(anchor) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        UserDefaults.standard.removeObject(forKey: anchorPositionKey)
        UserDefaults.standard.removeObject(forKey: dividerPositionKey)
        for title in ["T", "N"] {
            let key = "NSStatusItem Preferred Position mactools_native_acceptance_\(title)"
            if let value = originalPositions[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}
@main struct IceSelectedFixtureMain {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--diagnostic-directory",
              CommandLine.arguments[3] == "--diagnostic-nonce", UUID(uuidString: CommandLine.arguments[4]) != nil else { exit(2) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = IceSelectedFixture(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
