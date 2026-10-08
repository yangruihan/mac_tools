// Offline checks run shared engine and actual transport with injected tap/post seams.
import AppKit

@MainActor enum IceBaselineOffline {
    enum Failure: Error { case assertion(String) }
    static var assertions = 0
    static func require(_ value: Bool, _ name: String) throws { if !value { throw Failure.assertion(name) }; assertions += 1 }
    @MainActor final class Tap: IceBaselineTapControl {
        var isEnabled = false
        let options: CGEventTapOptions, location: EventTap.Location, types: [CGEventType], callback: IceBaselineNative.TapCallback
        init(_ o: CGEventTapOptions, _ l: EventTap.Location, _ t: [CGEventType], _ c: @escaping IceBaselineNative.TapCallback) { options = o; location = l; types = t; callback = c }
        func enable() { isEnabled = true }; func disable() { isEnabled = false }
    }
    @MainActor final class TransportHarness {
        var time = 1.0, taps: [Tap] = [], routes: [String] = []
        var permissionLatency = 0.0
        var tapCreationLatency = 0.0
        var onTapCreated: (() -> Void)?, onPause: (() -> Void)?, pauseError: Error?
        var cancel = false, drop = false, onSend: ((CGEvent, EventTap.Location) -> Void)?
        var deferredDelivery = false, permissionAllowed = true, identityError: Error?
        private var deliveries: [(CGEvent, EventTap.Location)] = []
        func deliver(_ event: CGEvent, _ location: EventTap.Location) {
            for tap in taps where tap.isEnabled && tap.types.contains(event.type) && tap.location.logString == location.logString {
                _ = tap.callback(tap, event.type, event)
            }
        }
        func pump() { let batch = deliveries; deliveries = []; for (event, location) in batch { deliver(event, location) } }
        lazy var transport = IceBaselineNative(windows: nil, pid: 123, identity: { if let error = self.identityError { throw error } }, offline: true,
            clock: { self.time }, sleep: { self.time += $0; self.onPause?(); if let error = self.pauseError { throw error }; self.pump() }, permission: { self.time += self.permissionLatency; return self.permissionAllowed },
            send: { event, location in
                self.routes.append("\(event.type.rawValue):\(location.logString)"); self.onSend?(event, location)
                if !self.drop {
                    if self.deferredDelivery { self.deliveries.append((event, location)) } else { self.deliver(event, location) }
                }
            }, makeTap: { o, l, t, c in self.time += self.tapCreationLatency; let tap = Tap(o, l, t, c); self.taps.append(tap); self.onTapCreated?(); return tap })
        func check() throws { if cancel { throw IceBaselineError.cancelled } }
    }
    // Run the shared engine through the actual Native routing implementation.
    // Frames, taps and sends are injected; all OS cursor/window/post calls stay off.
    @MainActor final class RoutedEffects: IceBaselineEffects {
        let harness = TransportHarness()
        var time: Double { harness.time }
        var lastMouseMove: Double?, mouseButtonDown = false
        var frames: [UInt32: CGRect] = [1: .init(x:0,y:0,width:20,height:30),2: .init(x:100,y:0,width:30,height:30)]
        var warps=0, hides=0, shows=0
        var afterSend: ((CGEvent, EventTap.Location) -> Void)?
        init() {
            harness.onSend = { [weak self] event, location in
                guard let self else { return }
                if location.logString == "PID 123", event.type == .leftMouseDown { self.frames[1]!.origin.x += 1 }
                if location.logString == "PID 123", event.type == .leftMouseUp,
                   event.getIntegerValueField(CGEventField(rawValue:0x33)!) == 2 { self.frames[1]!.origin.x = 80 }
                self.afterSend?(event,location)
            }
        }
        func checkRuntime() throws { try harness.check(); try harness.transport.checkRuntime() }
        func frame(_ item: IceBaselineItem) throws -> CGRect { frames[item.windowID]! }
        func pause(_ seconds: Double) async throws { try await harness.transport.pause(seconds) }
        func cursor() throws -> CGPoint { .init(x:1,y:2) }
        func hideCursor() { hides += 1 }; func showCursor() { shows += 1 }
        func warp(_ point: CGPoint) { warps += 1 }
        func configureSuppression() throws {}
        func prepareRoutingTaps(check: () throws -> Void) throws { try harness.transport.prepareRoutingTaps(check:check) }
        func scromble(_ event: CGEvent, pid: Int32, check: @escaping () throws -> Void) async throws { try await harness.transport.scromble(event,pid:pid,check:check) }
        func postAndWait(_ event: CGEvent, check: @escaping () throws -> Void) async throws { try await harness.transport.postAndWait(event,check:check) }
        func note(_ phase: String, _ values: [String:Any]) { harness.transport.note(phase,values) }
    }
    @MainActor final class Effects: IceBaselineEffects {
        var time = 1.0, lastMouseMove: Double?, mouseButtonDown = false
        var frames: [UInt32: CGRect] = [1: .init(x: 0, y: 0, width: 20, height: 30), 2: .init(x: 100, y: 0, width: 30, height: 30)]
        var packets: [CGEvent] = [], fallback = 0, wake = 0, attempts = 0, warps = 0, hides = 0, shows = 0, suppressions = 0
        var failMoves = 0, onPacket: (() -> Void)?, onPause: (() -> Void)?
        var terminal: Error?
        var runtimeCheck: (() throws -> Void)?
        func checkRuntime() throws { if let terminal { throw terminal }; try runtimeCheck?() }
        func frame(_ item: IceBaselineItem) throws -> CGRect { frames[item.windowID]! }
        func pause(_ seconds: Double) async throws { time += seconds; onPause?() }
        func cursor() throws -> CGPoint { .init(x: 1, y: 2) }
        func hideCursor() { hides += 1 }; func showCursor() { shows += 1 }; func warp(_ point: CGPoint) { warps += 1 }
        func configureSuppression() throws { suppressions += 1 }
        func note(_ phase: String, _ values: [String: Any]) {
            if phase == "move-attempt" { attempts += 1 }; if phase == "wake-up" { wake += 1 }
        }
        func scromble(_ e: CGEvent, pid: Int32, check: @escaping () throws -> Void) async throws {
            try check(); packets.append(e); onPacket?(); try check()
            if e.type == .leftMouseDown && e.location.x == 20_000 {
                if failMoves > 0 { failMoves -= 1; throw IceBaselineError.timeout }
                frames[1]!.origin.x += 1
            } else if e.type == .leftMouseUp && e.location.x == 100 {
                frames[1]!.origin.x = 80
            }
        }
        func postAndWait(_ e: CGEvent, check: @escaping () throws -> Void) async throws {
            try check(); packets.append(e); onPacket?(); try check()
            if e.getIntegerValueField(.mouseEventClickState) != 1 { fallback += 1 }
        }
    }
    static func run() async throws {
        assertions = 0
        let target = IceBaselineItem(windowID: 1, pid: 123, key: "T"), neighbor = IceBaselineItem(windowID: 2, pid: 123, key: "N")
        let down = try IceBaselinePacket.make(.leftMouseDown, move: true, point: .init(x: 20_000, y: 20_000), item: target, pid: 123, marker: 9)
        let up = try IceBaselinePacket.make(.leftMouseUp, move: true, point: .init(x: 100, y: 15), item: neighbor, pid: 123, marker: 10)
        let click = try IceBaselinePacket.make(.leftMouseDown, move: false, point: .zero, item: target, pid: 123, marker: 11)
        try require(down.flags == .maskCommand && up.flags.isEmpty && click.flags.isEmpty, "Ice asymmetric move flags")
        try require(up.getIntegerValueField(.eventTargetUnixProcessID) == 123 && up.getIntegerValueField(CGEventField(rawValue: 0x33)!) == 2, "neighbor window, source PID")
        try require(click.getIntegerValueField(.mouseEventClickState) == 1, "click state")
        let copied = down.copy()!; copied.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: 99)
        try require(!IceBaselinePacket.matches(down, copied), "window mismatch receipt")
        let h = TransportHarness()
        try await h.transport.scromble(down, pid: 123, check: h.check)
        try require(h.routes == ["0:PID 123", "1:session event tap", "1:PID 123"], "actual scromble null PID -> session -> PID")
        try require(h.taps.count == 2 && h.taps[0].options == .defaultTap && h.taps[1].options == .listenOnly && h.taps.allSatisfy { !$0.isEnabled }, "tap modes and final disable")
        let c = TransportHarness(); c.onSend = { _, location in if location.logString == "session event tap" { c.cancel = true } }
        do { try await c.transport.scromble(down, pid: 123, check: c.check); throw Failure.assertion("cancel should throw") } catch is IceBaselineError { }
        try require(c.routes == ["0:PID 123", "1:session event tap"] && c.taps.allSatisfy { !$0.isEnabled }, "cancel in callback prevents PID forwarding")
        let t = TransportHarness(); t.drop = true
        do { try await t.transport.scromble(down, pid: 123, check: t.check); throw Failure.assertion("timeout should throw") } catch is IceBaselineError { }
        try require(t.routes.count == 1 && t.time >= 1.05 && t.time < 1.052 && t.taps.allSatisfy { !$0.isEnabled }, "50ms timeout without leaked tap")
        let s = TransportHarness(); try await s.transport.postAndWait(click, check: s.check)
        try require(s.routes == ["1:session event tap"] && s.taps.count == 1, "click uses session only")
        let late = TransportHarness(); late.onSend = { _, _ in late.time += 0.06 }
        do { try await late.transport.scromble(down, pid: 123, check: late.check); throw Failure.assertion("late null must fail") } catch is IceBaselineError { }
        try require(late.routes == ["0:PID 123"] && late.taps.allSatisfy { !$0.isEnabled }, "late callback cannot forward after 50ms")
        let slowRead = TransportHarness(); slowRead.permissionLatency = 0.06
        do { try await slowRead.transport.scromble(down, pid: 123, check: slowRead.check); throw Failure.assertion("slow permission read must fail") } catch is IceBaselineError { }
        try require(slowRead.routes.isEmpty && slowRead.transport.posts == 0 && slowRead.taps.allSatisfy { !$0.isEnabled }, "permission read crossing deadline prevents first post")
        let cap = TransportHarness()
        for _ in 0..<200 { try await cap.transport.postAndWait(click, check: cap.check) }
        do { try await cap.transport.postAndWait(click, check: cap.check); throw Failure.assertion("post cap must fail") } catch is IceBaselineError { }
        var latched = false
        do { try cap.transport.checkRuntime() } catch { latched = true }
        try require(cap.routes.count == 200 && cap.transport.posts == 200 && latched && cap.taps.allSatisfy { !$0.isEnabled }, "200 post cap is sticky and leaks no tap")
        let e = Effects(), op = IceBaselineEngine(e)
        try await op.move(target, to: .left(neighbor)); try await op.click(target)
        try require(e.attempts == 1 && e.wake == 0 && e.suppressions == 2 && e.hides == 2 && e.shows == 2 && e.warps == 2, "normal engine move and click")
        let retry = Effects(); retry.failMoves = 4; let r = IceBaselineEngine(retry)
        try await r.move(target, to: .left(neighbor))
        try require(retry.attempts == 5 && retry.wake == 4 && retry.fallback == 4, "Ice finite wake and fallback retries")
        let allFail = Effects(); allFail.failMoves = 5
        do { try await IceBaselineEngine(allFail).move(target, to: .left(neighbor)); throw Failure.assertion("fifth attempt must fail") } catch is IceBaselineError { }
        try require(allFail.attempts == 5 && allFail.wake == 4, "five attempt limit")
        let interrupted = Effects(), cancelOp = IceBaselineEngine(interrupted)
        interrupted.onPacket = { cancelOp.cancel() }
        do { try await cancelOp.move(target, to: .left(neighbor)); throw Failure.assertion("engine cancel must fail") } catch is IceBaselineError { }
        try require(interrupted.packets.count == 1 && interrupted.fallback == 0 && interrupted.wake == 0 && interrupted.warps == 0 && interrupted.shows == 1 && cancelOp.possibleDown, "cancel retains possible down and skips cleanup/warp")
        let budget = Effects(), budgetOp = IceBaselineEngine(budget)
        budget.onPacket = { budget.terminal = IceBaselineError.budget }
        do { try await budgetOp.move(target, to: .left(neighbor)); throw Failure.assertion("terminal effects must fail") } catch is IceBaselineError { }
        try require(budgetOp.cancelled && budget.packets.count == 1 && budget.fallback == 0 && budget.wake == 0 && budget.warps == 0 && budget.shows == 1, "terminal transport failure stops fallback wake and warp")
        let quiet = Effects(); quiet.lastMouseMove = quiet.time
        try await IceBaselineEngine(quiet).waitMouse()
        try require(quiet.time >= 1.1 && quiet.time < 1.12, "100ms mouse quiet, no ANY")
        let timer = Effects(), timerOp = IceBaselineEngine(timer); var checks = 0
        try await timerOp.rehide(target, to: .left(neighbor), interfaceOpen: { checks += 1; return checks == 1 })
        try require(timer.time >= 19 && checks == 2, "15s rehide and 3s menu deferral")
        // Exercise the real engine with the same lifetime gate used before native posts.
        let lateEffects = Effects(); lateEffects.time = 114.4
        var lifetime = IceBaselineSessionLifetime(now: 0)
        try lifetime.accept(.ready, request: "ready", now: 1)
        try lifetime.accept(.begin, request: "operation", now: lateEffects.time)
        var state = lifetime.snapshot(now: lateEffects.time)
        lateEffects.onPause = { lifetime.tick(now: lateEffects.time); state = lifetime.snapshot(now: lateEffects.time) }
        lateEffects.runtimeCheck = {
            guard IceBaselineSessionLifetime.permitsEffects(state, operation: "operation", now: lateEffects.time) else { throw IceBaselineError.identity }
        }
        try await IceBaselineEngine(lateEffects).rehide(target, to: .left(neighbor), interfaceOpen: { false })
        try require(lateEffects.time >= 129.4 && lateEffects.packets.count == 2 && lifetime.phase == .active,
                    "114s late start retains fresh publication through actual engine 15s rehide")
        let cancelEffects = Effects(); cancelEffects.time = 114.4
        var cancelledLifetime = IceBaselineSessionLifetime(now: 0)
        try cancelledLifetime.accept(.ready, request: "ready", now: 1)
        try cancelledLifetime.accept(.begin, request: "operation", now: cancelEffects.time)
        cancelEffects.runtimeCheck = {
            guard cancelledLifetime.allowsEffects(operation: "operation", now: cancelEffects.time) else { throw IceBaselineError.cancelled }
        }
        cancelEffects.onPause = { try! cancelledLifetime.accept(.cancel, request: "cancel", now: cancelEffects.time) }
        do { try await IceBaselineEngine(cancelEffects).rehide(target, to: .left(neighbor), interfaceOpen: { false }); throw Failure.assertion("lifetime cancel must stop rehide") }
        catch is IceBaselineError { }
        try require(cancelEffects.packets.isEmpty && cancelEffects.warps == 0 && cancelledLifetime.phase == .cleaning,
                    "lifetime cancel during rehide forbids restore and cursor warp")
        let stale = Effects(); stale.time = 131
        stale.runtimeCheck = {
            guard IceBaselineSessionLifetime.permitsEffects(state, operation: "operation", now: stale.time) else { throw IceBaselineError.identity }
        }
        do { try await IceBaselineEngine(stale).move(target, to: .left(neighbor)); throw Failure.assertion("stale publisher must reject") }
        catch is IceBaselineError { }
        try require(stale.packets.isEmpty && stale.warps == 0, "freshness is still <=1s; longer lifetime cannot admit stale owner")
        let cold = TransportHarness(); cold.tapCreationLatency = 0.04
        do { try await cold.transport.scromble(down, pid: 123, check: cold.check); throw Failure.assertion("cold tap preparation crosses route deadline") }
        catch is IceBaselineError { }
        try require(cold.routes.isEmpty && cold.taps.allSatisfy { !$0.isEnabled }, "cold 80ms tap setup rejects before first post")
        let warm = TransportHarness(); warm.tapCreationLatency = 0.04
        try warm.transport.prepareRoutingTaps(check: warm.check)
        try require(warm.time > 1.05 && warm.routes.isEmpty && warm.taps.count == 2 && warm.taps.allSatisfy { !$0.isEnabled }, "bounded preparation keeps all taps disabled and sends nothing")
        try await warm.transport.scromble(down, pid: 123, check: warm.check)
        try warm.transport.prepareRoutingTaps(check: warm.check)
        try await warm.transport.scromble(up, pid: 123, check: warm.check)
        try warm.transport.prepareRoutingTaps(check: warm.check)
        try await warm.transport.postAndWait(click, check: warm.check)
        try require(warm.routes.count == 7 && warm.taps.count == 6 && warm.taps.allSatisfy { !$0.isEnabled }, "shared actual transport consumes fresh pairs for down up click without reusing null queues")
        let warmLate = TransportHarness(); try warmLate.transport.prepareRoutingTaps(check: warmLate.check)
        warmLate.onSend = { _, _ in warmLate.time += 0.06 }
        do { try await warmLate.transport.scromble(down, pid: 123, check: warmLate.check); throw Failure.assertion("prepared late route must still fail") }
        catch is IceBaselineError { }
        try require(warmLate.routes == ["0:PID 123"] && warmLate.taps.allSatisfy { !$0.isEnabled }, "prepared route preserves original 50ms callback rejection")
        let warmCancel = TransportHarness(); try warmCancel.transport.prepareRoutingTaps(check: warmCancel.check)
        warmCancel.onSend = { _, location in if location.logString == "session event tap" { warmCancel.cancel = true } }
        do { try await warmCancel.transport.scromble(down, pid: 123, check: warmCancel.check); throw Failure.assertion("prepared route cancellation must fail") }
        catch is IceBaselineError { }
        try require(warmCancel.routes == ["0:PID 123", "1:session event tap"] && warmCancel.taps.allSatisfy { !$0.isEnabled }, "prepared callback cancel still blocks PID forwarding")
        let prepLate = TransportHarness(); prepLate.tapCreationLatency = 0.3
        do { try prepLate.transport.prepareRoutingTaps(check: prepLate.check); throw Failure.assertion("preparation deadline must fail") }
        catch is IceBaselineError { }
        try require(prepLate.routes.isEmpty && prepLate.taps.allSatisfy { !$0.isEnabled }, "500ms preparation cap rejects without effects or active taps")
        warm.transport.stopMonitoring()
        try require(warm.taps.allSatisfy { !$0.isEnabled }, "prepared taps disabled at terminal shutdown")
        // Actual engine + actual routing: stop at each admitted route boundary.
        let stages: [(String,CGEventType,Int,Bool)] = [("PID 123",.null,1,true),
            ("session event tap",.leftMouseDown,2,true),("PID 123",.leftMouseDown,3,true),
            ("session event tap",.leftMouseUp,5,true),("PID 123",.leftMouseUp,6,false)]
        for (route,type,expected,downPending) in stages {
            let effects=RoutedEffects(), engine=IceBaselineEngine(effects)
            var stopped=false
            effects.afterSend = { event,location in
                if !stopped && location.logString==route && event.type==type { stopped=true; engine.cancel() }
            }
            do { try await engine.move(target,to:.left(neighbor)); throw Failure.assertion("integrated stop must throw") }
            catch IceBaselineError.cancelled {}
            try require(stopped && effects.harness.transport.posts==expected && engine.possibleDown==downPending,
                        "integrated boundary \(route)/\(type.rawValue): exact admitted effects and conservative down")
            do { try await engine.click(target); throw Failure.assertion("stopped engine cannot be reused") }
            catch IceBaselineError.cancelled {}
            try require(effects.harness.transport.posts==expected && effects.warps==0 && effects.hides==effects.shows && effects.harness.taps.allSatisfy{ !$0.isEnabled },
                        "integrated stop forbids reuse/fallback/warp and disables taps")
        }
        let prepEffects=RoutedEffects(), prepEngine=IceBaselineEngine(prepEffects)
        prepEffects.harness.onTapCreated={ prepEngine.cancel() }
        do { try await prepEngine.move(target,to:.left(neighbor)); throw Failure.assertion("cancel during preparation must throw") }
        catch IceBaselineError.cancelled {}
        try require(prepEffects.harness.transport.posts==0 && !prepEngine.possibleDown && prepEffects.harness.taps.count==1 && prepEffects.harness.taps.allSatisfy{ !$0.isEnabled } && prepEffects.warps==0,
                    "integrated preparation cancellation admits no down and leaks no disabled tap")
        let clickEffects=RoutedEffects(), clickEngine=IceBaselineEngine(clickEffects)
        clickEffects.afterSend={ event,_ in if event.type == .leftMouseDown { clickEngine.cancel() } }
        do { try await clickEngine.click(target); throw Failure.assertion("click down cancellation must throw") }
        catch IceBaselineError.cancelled {}
        try require(clickEffects.harness.transport.posts==1 && clickEngine.possibleDown && clickEffects.warps==0 && clickEffects.hides==clickEffects.shows && clickEffects.harness.taps.allSatisfy{ !$0.isEnabled },
                    "actual click transport cancel after down keeps responsibility without up/fallback")
        let waitEffects=RoutedEffects(), waitEngine=IceBaselineEngine(waitEffects)
        try await waitEngine.move(target,to:.left(neighbor));try await waitEngine.click(target)
        let beforeWait=waitEffects.harness.transport.posts, warpsBefore=waitEffects.warps
        waitEffects.harness.onPause={ waitEngine.cancel() }
        do { try await waitEngine.rehide(target,to:.left(neighbor),interfaceOpen:{false});throw Failure.assertion("rehide wait stop must throw") }
        catch IceBaselineError.cancelled {}
        try require(beforeWait==8 && waitEffects.harness.transport.posts==8 && waitEffects.warps==warpsBefore && !waitEngine.possibleDown,
                    "shared engine/native integration matches live eight-post wait cancellation")
        let awaitEffects=RoutedEffects(), awaitEngine=IceBaselineEngine(awaitEffects)
        awaitEffects.harness.pauseError=CancellationError()
        do { try await awaitEngine.rehide(target,to:.left(neighbor),interfaceOpen:{false});throw Failure.assertion("cancelled await must throw") }
        catch is CancellationError {}
        try require(awaitEngine.cancelled && awaitEffects.harness.transport.posts==0,"await cancellation permanently stops engine")
        awaitEffects.harness.pauseError=nil
        do { try await awaitEngine.move(target,to:.left(neighbor));throw Failure.assertion("another caller cannot rearm cancelled await") }
        catch IceBaselineError.cancelled {}
        try require(awaitEffects.harness.transport.posts==0 && awaitEffects.hides==0,"new caller after cancelled await cannot admit effects")
        let taskEffects=RoutedEffects(), taskEngine=IceBaselineEngine(taskEffects)
        let cancelledTask=Task { () -> Bool in
            await Task.yield()
            do { try taskEngine.check();return false } catch { return true }
        }
        cancelledTask.cancel()
        let rejected=await cancelledTask.value
        try require(rejected && taskEngine.cancelled,"Task cancellation locks stop beyond caller task lifetime")
        do { try await taskEngine.click(target);throw Failure.assertion("new task cannot reuse stopped engine") }
        catch IceBaselineError.cancelled {}
        try require(taskEffects.harness.transport.posts==0 && taskEffects.hides==0,"later task retains zero effects")
        print("\(assertions) focused offline assertions; shared engine/native routing seams; no native send, tap, monitor, cursor or suppression calls")
    }
}
