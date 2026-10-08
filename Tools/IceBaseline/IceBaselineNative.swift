// Ice-derived isolated transport, GPL-3.0. No product ANY policy imports.
import AppKit
import CryptoKit
import Darwin

@MainActor protocol IceBaselineTapControl {
    var isEnabled: Bool { get }
    func enable()
    func disable()
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
final class IceBaselineNative: IceBaselineEffects {
    typealias TapCallback = @MainActor (any IceBaselineTapControl, CGEventType, CGEvent) -> CGEvent?
    typealias TapFactory = @MainActor (CGEventTapOptions, EventTap.Location, [CGEventType], @escaping TapCallback) -> any IceBaselineTapControl
    let windows: IceBaselineWindows?
    let ownedPID: Int32
    let identity: () throws -> Void
    private var globalMonitor: Any?, localMonitor: Any?
    private var candidate: IceBaselineCandidateCoordinator?
    private let offline:Bool
    private var cursorHides = 0
    func bindCandidate(_ value: IceBaselineCandidateCoordinator) throws {
        guard candidate == nil, value.binding.fixture.pid == ownedPID else { throw IceCandidateFailure.binding }
        if let bridge=value.anyBridge,bridge.provenance == .isolatedReplay,!offline {throw IceCandidateFailure.policy}
        try value.check(); candidate = value
    }
    func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent {
        guard pid==ownedPID else{throw IceCandidateFailure.binding}
        if let bridge=candidate?.anyBridge{return try bridge.packet(type,move:move,point:point,item:item,marker:marker)}
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
    private let clock: () -> Double, sleep: (Double) async throws -> Void
    private let permission: () -> Bool, send: (CGEvent, EventTap.Location) throws -> Void
    private let makeTap: TapFactory
    private var preparedPIDTap: (any IceBaselineTapControl)?, preparedSessionTap: (any IceBaselineTapControl)?
    private var pidHandler: TapCallback?, sessionHandler: TapCallback?
    var time: Double { clock() }
    var mouseButtonDown: Bool { NSEvent.pressedMouseButtons != 0 }
    init(windows: IceBaselineWindows?, pid: Int32, identity: @escaping () throws -> Void,
         offline: Bool = false,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         permission: @escaping () -> Bool = { CGPreflightPostEventAccess() },
         send: @escaping (CGEvent, EventTap.Location) throws -> Void = { event, location in
             switch location { case .pid(let pid): event.postToPid(pid)
             case .sessionEventTap: event.post(tap: .cgSessionEventTap)
             default: throw IceBaselineError.identity }
         },
         makeTap: @escaping TapFactory = { options, location, types, callback in
             EventTap(options: options, location: location, place: .tailAppendEventTap, types: types) {
                 callback($0, $1, $2)
             }
         }) {
        self.windows = windows; ownedPID = pid; self.identity = identity; self.clock = clock; self.sleep = sleep;self.offline=offline
        self.permission = permission; self.send = send; self.makeTap = makeTap
        // Ice uses global + local mouse tracking. No ANY, keyboard scan or remote start receipt.
        if !offline {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.lastMouseMove = self?.time }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in self?.lastMouseMove = self?.time; return event }
        }
    }
    func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        preparedPIDTap?.disable(); preparedSessionTap?.disable()
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
        let first = try createTap(.defaultTap, .pid(ownedPID), [.null]) { [weak self] proxy, type, received in
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
        try candidate?.check()
        if let candidate, let windows {
            guard windows.activeSpace(windows.connection()) == candidate.binding.space else { throw IceCandidateFailure.binding }
        }
        do { try identity() } catch { terminalError = error; throw error }
        guard permission() else { terminalError = IceBaselineError.source; throw IceBaselineError.source }
    }
    func frame(_ item: IceBaselineItem) throws -> CGRect { try checkRuntime(); guard let windows else { throw IceBaselineError.source }; return try windows.frame(item) }
    func pause(_ seconds: Double) async throws { try await sleep(seconds) }
    func cursor() throws -> CGPoint { guard let p = MouseCursor.location(in: .coreGraphics) else { throw IceBaselineError.geometry }; return p }
    func hideCursor() {
        let body = { self.note("cursor-hide",[:]);MouseCursor.hide();self.cursorHides += 1 }
        if let candidate { do { try candidate.performAux("cursor-hide",body) } catch { terminalError=error } }
        else { body() }
    }
    func showCursor() {
        // Balance only this instance's successful hides even after stop.
        guard cursorHides>0 else{return};cursorHides-=1;note("cursor-show",[:]);MouseCursor.show()
    }
    func warp(_ point: CGPoint) {
        let body = { self.note("cursor-warp",["x":point.x,"y":point.y]);MouseCursor.warp(to:point) }
        if let candidate { do { try candidate.performAux("cursor-warp",body) } catch { terminalError=error } }
        else { body() }
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
        try check(); try checkRuntime()
        guard posts < 200 else { terminalError = IceBaselineError.budget; throw IceBaselineError.budget }
        if event.type != .null {
            guard event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(ownedPID),
                  [.leftMouseDown, .leftMouseUp].contains(event.type) else { throw IceBaselineError.identity }
        }
        if case .pid(let pid) = location { guard pid == ownedPID else { throw IceBaselineError.identity } }
        var row = IceBaselinePacket.summary(event); row["route"] = location.logString
        try check() // Identity/permission reads above may cross the route deadline.
        func body() throws {
            try check()
            // OS posting can annotate the dispatched CGEvent (v3.3 observed
            // nonCoalesced flags). Keep durable intent/original immutable;
            // each bound dispatch is a field-identical copy, never normalized.
            let dispatched:CGEvent
            if self.candidate != nil {
                guard let copy=event.copy(),IceCandidatePacket(copy) == IceCandidatePacket(event) else { throw IceCandidateFailure.packet }
                dispatched=copy
            } else { dispatched=event }
            self.note("post-intent",row);self.posts += 1
            try self.send(dispatched,location)
        }
        if let candidate { try candidate.performRoute(event,destination:location.logString,body) } else { try body() }
    }
    private func noteANYReceipt(_ expected:CGEvent,_ received:CGEvent) {
        guard let bridge=candidate?.anyBridge,bridge.provenance == .nativeRealWorker,
              received.type==expected.type,
              received.getIntegerValueField(.eventSourceUserData)==expected.getIntegerValueField(.eventSourceUserData),
              received.getIntegerValueField(.eventSourceUnixProcessID)==Int64(bridge.senderPID) else{return}
        let encoder=JSONEncoder()
        guard let a=try? JSONSerialization.jsonObject(with:encoder.encode(IceCandidatePacket(expected))),
              let b=try? JSONSerialization.jsonObject(with:encoder.encode(IceCandidatePacket(received))) else{return}
        note("owned-any-received-envelope",["expected":a,"received":b,"exact":IceCandidatePacket(expected)==IceCandidatePacket(received)])
    }
    func scromble(_ event: CGEvent, pid: Int32, check: @escaping () throws -> Void) async throws {
        guard !inProgress, pid == ownedPID, let null = CGEvent(source: nil) else { throw IceBaselineError.identity }
        inProgress = true; defer { inProgress = false }
        null.setIntegerValueField(.eventSourceUserData, value: IceBaselinePacket.nullMarker)
        if let candidate {
            do { try await candidate.prepareRoute(event,null:null) }
            catch { candidate.routeFailed();throw error }
        }
        var delivered = false
        defer { if !delivered { candidate?.routeFailed() } }
        var completed = false, failure: Error?
        let limit = time + 0.05
        note("route-start", ["kind":"scromble","marker":event.getIntegerValueField(.eventSourceUserData),"deadlineUptime":limit,"prepared":preparedPIDTap != nil])
        func checkRoute() throws {
            try check()
            guard self.time < limit else { self.note("route-deadline-rejected", ["deadlineUptime":limit]); throw IceBaselineError.timeout }
        }
        let firstCallback: TapCallback = { proxy, type, received in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "pid-null"]) }
                catch { failure = error; proxy.disable() }; return nil
            }
            // Preserve Ice: PID null tap consumes its null-type events.
            guard received.getIntegerValueField(.eventSourceUserData) == IceBaselinePacket.nullMarker else { return nil }
            proxy.disable(); self.note("null-received", ["pid": pid])
            do { try self.post(event, to: .sessionEventTap, check: checkRoute) } catch { failure = error }
            return nil
        }
        let secondCallback: TapCallback = { proxy, type, received in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "session-real"]) }
                catch { failure = error; proxy.disable() }; return nil
            }
            self.noteANYReceipt(event,received)
            guard IceBaselinePacket.matches(received, event), proxy.isEnabled else { return nil }
            proxy.disable(); self.note("session-received", IceBaselinePacket.summary(received))
            do { try self.post(event, to: .pid(pid), check: checkRoute); completed = true } catch { failure = error }
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
        try enableTaps([first,second])
        note("route-taps-enabled", ["deadlineUptime":limit])
        defer { first.disable(); second.disable(); pidHandler = nil; sessionHandler = nil }
        guard first.isEnabled && second.isEnabled else { throw IceBaselineError.tap }
        try post(null, to: .pid(pid), check: checkRoute)
        while !completed && failure == nil && time < limit { try check(); try await pause(0.001) }
        if let failure { throw failure }; guard completed && time < limit else { throw IceBaselineError.timeout }
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
        var completed = false, failure: Error?
        let limit = time + 0.05
        note("route-start", ["kind":"click","marker":event.getIntegerValueField(.eventSourceUserData),"deadlineUptime":limit,"prepared":preparedSessionTap != nil])
        func checkRoute() throws {
            try check()
            guard self.time < limit else { self.note("route-deadline-rejected", ["deadlineUptime":limit]); throw IceBaselineError.timeout }
        }
        let callback: TapCallback = { proxy, type, received in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                do { try checkRoute();try self.enableTaps([proxy]); self.note("ice-tap-reenabled", ["route": "session-click"]) }
                catch { failure = error; proxy.disable() }; return nil
            }
            self.noteANYReceipt(event,received)
            guard IceBaselinePacket.matches(received, event), proxy.isEnabled else { return nil }
            do { try checkRoute(); completed = true } catch { failure = error }
            proxy.disable(); self.note("click-session-received", IceBaselinePacket.summary(received)); return nil
        }
        let tap: any IceBaselineTapControl
        if let prepared = preparedSessionTap {
            sessionHandler = callback; tap = prepared
            preparedPIDTap?.disable(); preparedPIDTap = nil; preparedSessionTap = nil
        }
        else { tap = try createTap(.listenOnly, .sessionEventTap, [event.type], callback) }
        try enableTaps([tap]); note("route-taps-enabled", ["deadlineUptime":limit])
        defer { tap.disable(); sessionHandler = nil }
        guard tap.isEnabled else { throw IceBaselineError.tap }
        try post(event, to: .sessionEventTap, check: checkRoute)
        while !completed && failure == nil && time < limit { try check(); try await pause(0.001) }
        if let failure { throw failure }; guard completed && time < limit else { throw IceBaselineError.timeout }
        if let candidate { try await candidate.routeReturned(event) }
        delivered = true
    }
}
