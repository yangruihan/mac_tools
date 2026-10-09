// Ice-derived isolated transport, GPL-3.0. No product ANY policy imports.
import AppKit
import CryptoKit
import Darwin

@MainActor protocol IceBaselineTapControl {
    var isEnabled: Bool { get }
    func enable()
    func disable()
    var endpoint: UUID? { get }
    var rawReceipt: IceReceiverReceipt? { get }
    var receiverClosed: Bool { get }
    func arm(_ admission: IceReceiverAdmission, _ fence: IceSelectedFence, _ expired: @escaping () -> Void)
    func markPosted(_ event: CGEvent, at: Double)
    func close()
}
extension IceBaselineTapControl {
    var endpoint:UUID? { nil }
    var rawReceipt:IceReceiverReceipt? { nil }
    var receiverClosed:Bool { true }
    func arm(_ admission:IceReceiverAdmission,_ fence:IceSelectedFence,_ expired:@escaping()->Void) {}
    func markPosted(_ event:CGEvent,at:Double) {}
    func close(){disable()}
}
extension EventTap: IceBaselineTapControl {}
extension EventTap.Proxy: IceBaselineTapControl {}

@MainActor
final class IceBaselineWindows {
    // Only the six already authorized read-only CGS symbols are used.
    typealias Connection = @convention(c) () -> Int32
    typealias Count = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int32>) -> Int32
    typealias List = @convention(c) (Int32, Int32, Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<Int32>) -> Int32
    typealias Frame = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    typealias ActiveSpace = @convention(c) (Int32) -> UInt
    typealias WindowSpaces = @convention(c) (Int32, UInt32, CFArray) -> Unmanaged<CFArray>?
    let handle: UnsafeMutableRawPointer, connection: Connection, count: Count, list: List, getFrame: Frame
    let activeSpace: ActiveSpace, windowSpaces: WindowSpaces
    init() throws {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL) else { throw IceBaselineError.source }
        func resolve<T>(_ name: String, _: T.Type) throws -> T {
            guard let p = dlsym(h, name) else { throw IceBaselineError.source }; return unsafeBitCast(p, to: T.self)
        }
        do {
            connection = try resolve("CGSMainConnectionID", Connection.self)
            count = try resolve("CGSGetWindowCount", Count.self)
            list = try resolve("CGSGetProcessMenuBarWindowList", List.self)
            getFrame = try resolve("CGSGetScreenRectForWindow", Frame.self)
            activeSpace = try resolve("CGSGetActiveSpace", ActiveSpace.self)
            windowSpaces = try resolve("CGSCopySpacesForWindows", WindowSpaces.self)
            handle = h
        } catch { dlclose(h); throw error }
    }
    deinit { dlclose(handle) }
    static func rows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.statusWindow)) }
    }
    func frame(_ item: IceBaselineItem) throws -> CGRect {
        let cid = connection(); var n: Int32 = 0
        guard cid > 0, count(cid, 0, &n) == 0, n > 0, n < 4096 else { throw IceBaselineError.source }
        let space = activeSpace(cid)
        guard space > 0 else { throw IceBaselineError.identity }
        var ids = [UInt32](repeating: 0, count: Int(n) + 1), actual: Int32 = 0
        let result = ids.withUnsafeMutableBufferPointer { list(cid, 0, Int32($0.count), $0.baseAddress!, &actual) }
        guard result == 0, actual > 0, actual < ids.count,
              ids.prefix(Int(actual)).contains(item.windowID),
              Self.rows().contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == item.windowID
                  && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == item.pid }) else { throw IceBaselineError.identity }
        var f = CGRect.zero
        guard getFrame(cid, item.windowID, &f) == 0, !f.isNull, !f.isInfinite,
              [f.minX, f.minY, f.width, f.height].allSatisfy({ $0.isFinite }), f.width > 0, f.height > 0 else { throw IceBaselineError.geometry }
        guard let value = windowSpaces(cid, 7, [item.windowID] as CFArray),
              let spaces = value.takeRetainedValue() as? [NSNumber],
              spaces.contains(where: { $0.uintValue == space }), activeSpace(cid) == space else { throw IceBaselineError.identity }
        return f
    }
}

@MainActor
final class IceSelectedNative: IceBaselineEffects {
    typealias TapCallback = @MainActor (any IceBaselineTapControl, CGEventType, CGEvent) -> CGEvent?
    typealias TapFactory = @MainActor (CGEventTapOptions, EventTap.Location, [CGEventType], @escaping TapCallback) -> any IceBaselineTapControl
    let windows: IceBaselineWindows?
    let targetPID: Int32
    let identity: () throws -> Void
    private var globalMonitor: Any?, localMonitor: Any?
    private var candidate: IceSelectedCoordinator?
    private let offline:Bool
    private var cursorHides = 0
    func bindCandidate(_ value: IceSelectedCoordinator) throws {
        guard candidate == nil, value.binding.owner.pid == targetPID else { throw IceSelectedFailure.binding }
        try value.check(); candidate = value
    }
    func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent {
        guard pid==targetPID else{throw IceSelectedFailure.binding}
        return try IceBaselinePacket.make(type,move:move,point:point,item:item,pid:pid,marker:marker)
    }
    func beginGesture(down:CGEvent,up:CGEvent) async throws {
        if let candidate {
            if candidate.retained?.phase == .opening || candidate.retained?.phase == .restoring {
                try candidate.requireMenuLease(nativeRequired:!offline,restoring:candidate.retained?.phase == .restoring)
            }
            try await candidate.beginGesture(down:down,up:up)
        }
    }
    private(set) var lastMouseMove: Double?
    private(set) var events: [[String: Any]] = []
    private(set) var posts = 0
    private var inProgress = false
    private var terminalError: Error?
    private var synchronousPostValidation = false
    private(set) var transportFailure: String?
    private let clock: () -> Double, sleep: (Double) async throws -> Void
    private let permission: () -> Bool, send: (CGEvent, EventTap.Location) throws -> Void
    private let withDispatchValidation: ((() throws -> Void) throws -> Void)?
    private let waitReceiptDeadline: ((Double) async throws -> Void)?
    private let makeTap: TapFactory
    private var preparedPIDTap: (any IceBaselineTapControl)?, preparedSessionTap: (any IceBaselineTapControl)?
    private var pidHandler: TapCallback?, sessionHandler: TapCallback?
    private var activeReceivers:[(any IceBaselineTapControl,String)]=[]
    // Test-only delay is set only by the self-owned CLI, never ordinary sessions.
    var selfOwnedMainConsumerDelay=false
    var time: Double { clock() }
    var mouseButtonDown: Bool { NSEvent.pressedMouseButtons != 0 }
    init(windows: IceBaselineWindows?, pid: Int32, identity: @escaping () throws -> Void,
         offline: Bool = false,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         waitReceiptDeadline: ((Double) async throws -> Void)? = nil,
         withDispatchValidation: ((() throws -> Void) throws -> Void)? = nil,
         permission: @escaping () -> Bool = { CGPreflightPostEventAccess() },
         send: @escaping (CGEvent, EventTap.Location) throws -> Void = { event, location in
             switch location { case .pid(let pid): event.postToPid(pid)
             case .sessionEventTap: event.post(tap: .cgSessionEventTap)
             default: throw IceBaselineError.identity }
         },
         makeTap: @escaping TapFactory = { options, location, types, callback in
             IceNativeReceiverTap(options,location,types,callback)
         }) {
        self.windows = windows; targetPID = pid; self.identity = identity; self.clock = clock; self.sleep = sleep;self.offline=offline
        self.withDispatchValidation = withDispatchValidation
        self.permission = permission; self.send = send; self.makeTap = makeTap;self.waitReceiptDeadline=waitReceiptDeadline
        // Ice uses global + local mouse tracking. No ANY, keyboard scan or remote start receipt.
        if !offline {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.lastMouseMove = self?.time }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in self?.lastMouseMove = self?.time; return event }
        }
    }
    func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        preparedPIDTap?.close(); preparedSessionTap?.close()
        for (tap,_) in activeReceivers{tap.close()}
        activeReceivers=[]
        preparedPIDTap = nil; preparedSessionTap = nil; pidHandler = nil; sessionHandler = nil
    }
    private func createTap(_ options:CGEventTapOptions,_ location:EventTap.Location,_ types:[CGEventType],_ callback:@escaping TapCallback)throws->any IceBaselineTapControl {
        if let candidate { return try candidate.performAux("tap-create"){makeTap(options,location,types,callback)} }
        return makeTap(options,location,types,callback)
    }
    private func enableTaps(_ taps:[any IceBaselineTapControl])throws {
        if let candidate { try candidate.performAux("tap-enable"){for tap in taps{tap.enable()}} }
        else { for tap in taps{tap.enable()} }
    }
    // Prepare fresh disabled, owned taps before each route. Route deadlines and
    // every send/callback check remain unchanged; no creation IPC inside 50ms.
    func prepareRoutingTaps(check: () throws -> Void) throws {
        guard !inProgress, preparedPIDTap == nil, preparedSessionTap == nil else { throw IceBaselineError.identity }
        let started = time, deadline = started + 0.5
        func validate() throws {
            try check(); try checkRuntime()
            guard time < deadline else { throw IceBaselineError.timeout }
        }
        try validate(); note("routing-taps-prepare-start", [:])
        let first = try createTap(.defaultTap, .pid(targetPID), [.null]) { [weak self] proxy, type, received in
            self?.pidHandler?(proxy, type, received)
        }
        first.disable()
        defer { first.disable() }
        try validate()
        let second = try createTap(.listenOnly, .sessionEventTap, [.leftMouseDown, .leftMouseUp]) { [weak self] proxy, type, received in
            self?.sessionHandler?(proxy, type, received) ?? received
        }
        second.disable()
        defer { second.disable() }
        try validate()
        preparedPIDTap = first; preparedSessionTap = second
        note("routing-taps-prepared-disabled", ["elapsedMS":(time-started)*1000,"nativePosts":posts])
    }
    func checkRuntime() throws {
        if let terminalError { throw terminalError }
        guard let candidate else { throw IceSelectedFailure.policy }; try candidate.check()
        // Waiting/callback checks are local stop/deadline checks. Identity()
        // performs fresh Space/display/window ownership and signature checks
        // before every actual dispatch; outside routes those checks remain here.
        // Repeating synchronous WindowServer Space IPC while waiting can block
        // the very mach-port callback we need to receive. No dispatch lease or
        // identity result is cached across posts/awaits.
        if !synchronousPostValidation && !inProgress { try validateIdentity() }
    }
    private func validateIdentity() throws {
        let start=time
        do { try identity() } catch {terminalError=error;note("identity-rejected",["elapsedMS":(time-start)*1000]);throw error}
        note("identity-validated",["elapsedMS":(time-start)*1000,"synchronousPost":synchronousPostValidation])
        guard permission() else { terminalError = IceBaselineError.source; throw IceBaselineError.source }
    }
    func frame(_ item: IceBaselineItem) throws -> CGRect { try checkRuntime(); guard let windows else { throw IceBaselineError.source }; return try windows.frame(item) }
    func pause(_ seconds: Double) async throws { try await sleep(seconds) }
    func cursor() throws -> CGPoint { guard let p = MouseCursor.location(in: .coreGraphics) else { throw IceBaselineError.geometry }; return p }
    func hideCursor() {
        let body = { () throws -> Void in
            guard CGDisplayHideCursor(CGMainDisplayID()) == .success else { throw IceBaselineError.source }
            self.note("cursor-hide",[:]);self.cursorHides += 1
        }
        if let candidate { do { try candidate.performAux("cursor-hide",body) } catch { terminalError=error } }
        else { do { try body() } catch { terminalError=error } }
    }
    func showCursor() {
        // Balance only this instance's successful hides even after stop.
        guard cursorHides>0 else{return}
        if CGDisplayShowCursor(CGMainDisplayID()) == .success { cursorHides-=1;note("cursor-show",[:]) }
        else { terminalError=IceBaselineError.source;candidate?.routeFailed();note("cursor-show-failed",[:]) }
    }
    func warp(_ point: CGPoint) {
        let body = { () throws -> Void in
            guard CGWarpMouseCursorPosition(point) == .success else { throw IceBaselineError.source }
            self.note("cursor-warp",["x":point.x,"y":point.y])
        }
        if let candidate { do { try candidate.performAux("cursor-warp",body) } catch { terminalError=error } }
        else { do { try body() } catch { terminalError=error } }
    }
    func note(_ phase: String, _ values: [String: Any]) {
        var row = values; row["phase"] = phase; row["uptime"] = time; events.append(row)
    }
    func configureSuppression() throws {
        try checkRuntime()
        let body = {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { throw IceBaselineError.source }
            let all: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
            for state in [CGEventSuppressionState.eventSuppressionStateRemoteMouseDrag, .eventSuppressionStateSuppressionInterval] {
                source.setLocalEventsFilterDuringSuppressionState(all, state: state)
            }
            source.localEventsSuppressionInterval = 0
            self.note("ice-permit-all-zero-suppression",[:])
        }
        if let candidate { try candidate.performAux("suppression-config",body) } else { try body() }
    }
    private func post(_ event: CGEvent, to location: EventTap.Location, check: () throws -> Void) throws {
        // One synchronous post has one fresh signature/owner/permission read,
        // immediately before dispatch. Recursive engine/transport checks retain
        // stop, scope and deadline checks without repeating that same expensive
        // read four times. No lease/cache is shared across posts or awaits.
        guard !synchronousPostValidation else { throw IceBaselineError.identity }
        synchronousPostValidation = true; defer { synchronousPostValidation = false }
        try check(); try checkRuntime()
        guard posts < 200 else { terminalError = IceBaselineError.budget; throw IceBaselineError.budget }
        if event.type != .null {
            guard event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(targetPID),
                  [.leftMouseDown, .leftMouseUp].contains(event.type) else { throw IceBaselineError.identity }
        }
        if case .pid(let pid) = location { guard pid == targetPID else { throw IceBaselineError.identity } }
        var row = IceBaselinePacket.summary(event); row["route"] = location.logString
        try check() // Identity/permission reads above may cross the route deadline.
        func body() throws {
            try self.validateIdentity()
            try check() // Recheck deadline/stop after the fresh identity read.
            // OS posting can annotate the dispatched CGEvent (v3.3 observed
            // nonCoalesced flags). Keep durable intent/original immutable;
            // each bound dispatch is a field-identical copy, never normalized.
            let dispatched:CGEvent
            if self.candidate != nil {
                guard let copy=event.copy(),IceSelectedPacket(copy) == IceSelectedPacket(event) else { throw IceSelectedFailure.packet }
                dispatched=copy
            } else { dispatched=event }
            self.note("post-intent",row);self.posts += 1
            let entered=self.time
            var returnedNormally=false
            self.note("post-call-enter",["marker":event.getIntegerValueField(.eventSourceUserData),"type":event.type.rawValue,"route":location.logString])
            defer {self.note("post-call-exit",["marker":event.getIntegerValueField(.eventSourceUserData),"elapsedMS":(self.time-entered)*1000,"returnedNormally":returnedNormally])}
            for (tap,destination) in self.activeReceivers where destination == location.logString {tap.markPosted(dispatched,at:self.time)}
            try self.send(dispatched,location)
            returnedNormally=true
        }
        func dispatch() throws {
            if let candidate { try candidate.performRoute(event,destination:location.logString,body) } else { try body() }
        }
        // Only this synchronous actual dispatch shares its complete runtime sample.
        // The wrapper clears it before returning, including every failure path.
        if let withDispatchValidation { try withDispatchValidation(dispatch) }
        else { try dispatch() }
        if selfOwnedMainConsumerDelay && posts == 8 {
            let start=time;note("self-only-main-consumer-delay-enter",[:]);usleep(90_000)
            note("self-only-main-consumer-delay-exit",["elapsedMS":(time-start)*1000])
        }
    }
    private func awaitReceipt(_ waiter:IceSelectedReceiptWait,check:@escaping () throws -> Void,start:()throws->Void) async throws {
        let fence=candidate?.fence
        var dispatchFailure:Error?
        try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                waiter.install(continuation)
                if self.offline {
                let timer=Task { @MainActor in
                    let before=self.time,requested=max(0,waiter.deadline-before)
                    do {
                        if let injected=self.waitReceiptDeadline {try await injected(waiter.deadline)}
                        else {try await self.pause(requested)}
                        guard !Task.isCancelled,waiter.pending else{return}
                        self.note("route-deadline-task-woke",["requestedMS":requested*1000,"actualMS":(self.time-before)*1000,"remainingMS":(waiter.deadline-self.time)*1000])
                        try check()
                        self.note("route-receipt-timeout",["deadlineUptime":waiter.deadline,"completed":false])
                        waiter.fail(IceBaselineError.timeout)
                    } catch {if !Task.isCancelled {waiter.fail(error)}}
                }
                waiter.setTimeout(timer)
                }
                do {try start()} catch {dispatchFailure=error;waiter.fail(error)}
            }
            if let dispatchFailure{throw dispatchFailure}
            try Task.checkCancellation();try check()
            self.note("route-receipt-continuation-resumed",["acceptedAtUptime":waiter.acceptedAt ?? -1,"resumedAfterDeadline":self.time>=waiter.deadline,"settlementCount":waiter.settlementCount])
        },onCancel:{fence?.cancel();Task { @MainActor in waiter.fail(CancellationError()) }})
    }
    private func arm(_ tap:any IceBaselineTapControl,_ event:CGEvent,_ limit:Double,_ waiter:IceSelectedReceiptWait,_ route:UUID)throws->IceReceiverAdmission? {
        guard !offline else{return nil}
        guard let endpoint=tap.endpoint,let candidate,let record=candidate.retained else{throw IceBaselineError.tap}
        let a=IceReceiverAdmission(endpoint:endpoint,route:route,nonce:candidate.binding.nonce,transaction:record.transaction,
                                   generation:candidate.fence.stop.generation,pid:targetPID,key:IceReceiverKey(event),deadline:limit)
        tap.arm(a,candidate.fence){[weak self] in self?.note("raw-receiver-expired",["deadlineUptime":limit]);waiter.fail(IceBaselineError.timeout)}
        return a
    }
    private func validateReceipt(_ proxy:any IceBaselineTapControl,_ expected:IceReceiverAdmission?)throws->Double {
        if offline && expected == nil {return proxy.rawReceipt?.receivedAt ?? time}
        guard let expected,let receipt=proxy.rawReceipt,receipt.matches(expected),proxy.endpoint == expected.endpoint else{throw IceSelectedFailure.binding}
        try candidate?.check()
        note("raw-receipt-bound",["receivedAtUptime":receipt.receivedAt,"postedAtUptime":receipt.postedAt,
                                 "rawPostMS":(receipt.receivedAt-receipt.postedAt)*1000,"consumerDelayMS":(time-receipt.receivedAt)*1000,
                                 "deadlineUptime":expected.deadline,"endpoint":expected.endpoint.uuidString,"routeToken":expected.route.uuidString])
        return receipt.receivedAt
    }
    private func closeRoute(_ taps:[any IceBaselineTapControl])throws {
        for tap in taps {tap.close();note("receiver-closed",["closed":tap.receiverClosed]);guard tap.receiverClosed else{throw IceBaselineError.tap}}
        activeReceivers=[]
    }
    func scromble(_ event: CGEvent, pid: Int32, check: @escaping () throws -> Void) async throws {
        guard !inProgress, pid == targetPID, let null = CGEvent(source: nil) else { throw IceBaselineError.identity }
        inProgress = true; defer { inProgress = false }
        null.setIntegerValueField(.eventSourceUserData, value: IceBaselinePacket.nullMarker)
        if let candidate {
            do { try await candidate.prepareRoute(event,null:null) }
            catch { candidate.routeFailed();throw error }
        }
        var delivered = false
        defer { if !delivered { candidate?.routeFailed() } }
        let limit = time + 0.05
        let waiter=IceSelectedReceiptWait(deadline:limit,clock:clock)
        note("route-start", ["kind":"scromble","marker":event.getIntegerValueField(.eventSourceUserData),"deadlineUptime":limit,"prepared":preparedPIDTap != nil])
        func checkRoute() throws {
            try check()
            guard self.time < limit else { self.note("route-deadline-rejected", ["deadlineUptime":limit]); throw IceBaselineError.timeout }
        }
        let routeToken=UUID()
        var firstAdmission:IceReceiverAdmission?,secondAdmission:IceReceiverAdmission?
        let firstCallback: TapCallback = { proxy, type, received in
            guard waiter.pending else{return nil}
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                self.note("tap-disable-notice",["route":"pid-null","type":type.rawValue,"reason":type == .tapDisabledByTimeout ? "timeout" : "userInput","marker":event.getIntegerValueField(.eventSourceUserData),"remainingMS":(limit-self.time)*1000,"tapEnabled":proxy.isEnabled])
                if type == .tapDisabledByUserInput && proxy.isEnabled {
                    do{try check();self.note("tap-stale-disable-notice",["route":"pid-null","action":"alreadyEnabledNoop"])}catch{waiter.fail(error);proxy.disable()}
                    return nil
                }
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "pid-null"]) }
                catch { waiter.fail(error); self.note("tap-reenable-refused",["reason":String(describing:error)]);proxy.disable() }; return nil
            }
            // Preserve Ice: PID null tap consumes its null-type events.
            guard type == .null,IceBaselinePacket.matches(received,null),proxy.isEnabled else{return nil}
            do{_ = try self.validateReceipt(proxy,firstAdmission)}catch{waiter.fail(error);return nil}
            proxy.disable(); self.note("null-received", ["pid": pid])
            do { try self.post(event, to: .sessionEventTap, check: checkRoute) } catch { waiter.fail(error) }
            return nil
        }
        let secondCallback: TapCallback = { proxy, type, received in
            guard waiter.pending else{return nil}
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                self.note("tap-disable-notice",["route":"session-real","type":type.rawValue,"reason":type == .tapDisabledByTimeout ? "timeout" : "userInput","marker":event.getIntegerValueField(.eventSourceUserData),"remainingMS":(limit-self.time)*1000,"tapEnabled":proxy.isEnabled])
                if type == .tapDisabledByUserInput && proxy.isEnabled {
                    do{try check();self.note("tap-stale-disable-notice",["route":"session-real","action":"alreadyEnabledNoop"])}catch{waiter.fail(error);proxy.disable()}
                    return nil
                }
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "session-real"]) }
                catch { waiter.fail(error); self.note("tap-reenable-refused",["reason":String(describing:error)]);proxy.disable() }; return nil
            }
            guard type==event.type,received.type==event.type,IceBaselinePacket.matches(received, event), proxy.isEnabled else { return nil }
            proxy.disable(); self.note("session-received", IceBaselinePacket.summary(received))
            do { _ = try self.validateReceipt(proxy,secondAdmission);try self.post(event, to: .pid(pid), check: checkRoute);try checkRoute();waiter.received() } catch { waiter.fail(error) }
            return nil
        }
        let first: any IceBaselineTapControl, second: any IceBaselineTapControl
        if let pidTap = preparedPIDTap, let sessionTap = preparedSessionTap {
            pidHandler = firstCallback; sessionHandler = secondCallback; first = pidTap; second = sessionTap
            preparedPIDTap = nil; preparedSessionTap = nil // A pair is consumed once; never reuse a null queue.
        } else {
            first = try createTap(.defaultTap, .pid(pid), [.null], firstCallback)
            second = try createTap(.listenOnly, .sessionEventTap, [event.type], secondCallback)
        }
        firstAdmission=try arm(first,null,limit,waiter,routeToken);secondAdmission=try arm(second,event,limit,waiter,routeToken)
        activeReceivers=[(first,EventTap.Location.pid(pid).logString),(second,EventTap.Location.sessionEventTap.logString)]
        try enableTaps([first,second])
        note("route-taps-enabled", ["deadlineUptime":limit])
        defer { first.close(); second.close(); activeReceivers=[];pidHandler = nil; sessionHandler = nil }
        guard first.isEnabled && second.isEnabled else { throw IceBaselineError.tap }
        do {try await awaitReceipt(waiter,check:check,start:{try self.post(null,to:.pid(pid),check:checkRoute)})}
        catch {transportFailure=String(describing:error);throw error}
        try closeRoute([first,second])
        if let candidate { try await candidate.routeReturned(event) }
        delivered = true
    }
    func postAndWait(_ event: CGEvent, check: @escaping () throws -> Void) async throws {
        guard !inProgress else { throw IceBaselineError.identity }; inProgress = true; defer { inProgress = false }
        if let candidate {
            do { try await candidate.prepareRoute(event,null:nil) }
            catch { candidate.routeFailed();throw error }
        }
        var delivered = false
        defer { if !delivered { candidate?.routeFailed() } }
        preparedPIDTap?.close();preparedPIDTap=nil
        let limit = time + 0.05
        let waiter=IceSelectedReceiptWait(deadline:limit,clock:clock)
        var admission:IceReceiverAdmission?
        note("route-start", ["kind":"click","marker":event.getIntegerValueField(.eventSourceUserData),"deadlineUptime":limit,"prepared":preparedSessionTap != nil])
        func checkRoute() throws {
            try check()
            guard self.time < limit else { self.note("route-deadline-rejected", ["deadlineUptime":limit]); throw IceBaselineError.timeout }
        }
        let callback: TapCallback = { proxy, type, received in
            guard waiter.pending else{return nil}
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                self.note("tap-disable-notice",["route":"session-click","type":type.rawValue,"reason":type == .tapDisabledByTimeout ? "timeout" : "userInput","marker":event.getIntegerValueField(.eventSourceUserData),"remainingMS":(limit-self.time)*1000,"tapEnabled":proxy.isEnabled])
                // Our explicit preparation disable produces this notification.
                // If it arrives after enable, it is informational, never an ACK.
                // Avoid another WindowServer enable; absolute receipt deadline
                // and cancellation still apply to all matching packet delivery.
                if type == .tapDisabledByUserInput && proxy.isEnabled {
                    do{try check();self.note("tap-stale-disable-notice",["route":"session-click","action":"alreadyEnabledNoop"])}catch{waiter.fail(error);proxy.disable()}
                    return nil
                }
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "session-click"]) }
                catch { waiter.fail(error); self.note("tap-reenable-refused",["reason":String(describing:error)]);proxy.disable() }; return nil
            }
            if received.getIntegerValueField(.eventSourceUserData)==event.getIntegerValueField(.eventSourceUserData) {
                self.note("own-marker-observed",["type":type.rawValue,"expectedType":event.type.rawValue,"tapEnabled":proxy.isEnabled,"fieldsMatch":IceBaselinePacket.matches(received,event),"fields":IceBaselinePacket.matchFields.map{["field":Int64($0.rawValue),"received":received.getIntegerValueField($0),"expected":event.getIntegerValueField($0)]}])
            }
            // Prepared taps include both mouse types. Ice's original single-type
            // tap cannot ACK a down as an up: preserve that admission here too.
            guard type==event.type,received.type==event.type,IceBaselinePacket.matches(received, event), proxy.isEnabled else { return nil }
            do {
                let raw=try self.validateReceipt(proxy,admission)
                try check()
                if self.offline && proxy.rawReceipt == nil {try checkRoute()}
                else {try self.validateIdentity();try check()}
                waiter.received(at:raw)
            } catch { waiter.fail(error) }
            proxy.disable(); self.note("click-session-received", IceBaselinePacket.summary(received)); return nil
        }
        let tap: any IceBaselineTapControl
        if let prepared = preparedSessionTap {
            sessionHandler = callback; tap = prepared
            preparedPIDTap?.disable(); preparedPIDTap = nil; preparedSessionTap = nil
        }
        else { tap = try createTap(.listenOnly, .sessionEventTap, [event.type], callback) }
        admission=try arm(tap,event,limit,waiter,UUID())
        activeReceivers=[(tap,EventTap.Location.sessionEventTap.logString)]
        try enableTaps([tap]); note("route-taps-enabled", ["deadlineUptime":limit])
        defer { tap.close();activeReceivers=[];sessionHandler = nil }
        guard tap.isEnabled else { throw IceBaselineError.tap }
        do {try await awaitReceipt(waiter,check:check,start:{try self.post(event,to:.sessionEventTap,check:checkRoute)})}
        catch {transportFailure=String(describing:error);throw error}
        try closeRoute([tap])
        if let candidate { try await candidate.routeReturned(event) }
        delivered = true
    }
}
