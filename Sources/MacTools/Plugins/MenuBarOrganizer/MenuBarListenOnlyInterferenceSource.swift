// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import ApplicationServices
import Darwin

/// Standalone explicit opt-in only. It never alters or suppresses input.
/// Tap loss permanently ends the continuity; no automatic re-enable/fallback.
final class MenuBarListenOnlyInterferenceSource: MenuBarHiddenInterferenceSource {
    typealias I = MenuBarMoveInterference
    enum Policy {
        case disabled, isolatedListenOnly, isolatedLocalAcceptance
        var location: CGEventTapLocation? {
            switch self {
            case .disabled: return nil
            case .isolatedListenOnly: return .cgSessionEventTap
            case .isolatedLocalAcceptance: return .cgAnnotatedSessionEventTap
            }
        }
    }
    enum ReadCause: String, Codable {
        case notStarted, stopped, wrongThread, missingPort, invalidPort, disabledPort, permissionMissing
        case callbackTimeout, callbackDisabledByUserInput, queueOverflow, waitingObservationInvalid
        case activityDuringRead, warmupOrRecentActivity, invalidAnyInputType, invalidActivityAge, ready
        var monitoringHealthy: Bool {
            [.activityDuringRead, .warmupOrRecentActivity, .ready].contains(self)
        }
        var activityRefusal: Bool { [.activityDuringRead, .warmupOrRecentActivity].contains(self) }
    }
    struct Diagnostics: Codable {
        let created: Bool, mainThread: Bool, portPresent: Bool, portValid: Bool, tapEnabled: Bool, listenPermission: Bool
        let readCause: ReadCause, terminalCause: ReadCause?
        let readCount: Int, readyCount: Int, activityDuringReadCount: Int, quietRefusalCount: Int
        let observedEventCount: Int, timeoutCallbacks: Int, disabledByUserCallbacks: Int, overflowCount: Int, queuedEventCount: Int
        let originCounts: [String: Int]
        let privateSourceState: Int32
        let tapLocation: UInt32?
        var waitingConsumption: WaitingConsumption? = nil
        var monitoringHealthy: Bool {
            mainThread && portPresent && portValid && tapEnabled && listenPermission && terminalCause == nil && readCause.monitoringHealthy
        }
    }
    var diagnosticToolPIDs: Set<Int32> = []
    private var originCounts: [String: Int] = [:]
    private var lastReadCause: ReadCause = .notStarted
    private var terminalCause: ReadCause?
    private var readCount = 0, readyCount = 0, activityDuringReadCount = 0, quietRefusalCount = 0
    private var timeoutCallbacks = 0, disabledByUserCallbacks = 0, overflowCount = 0
    func diagnostics() -> Diagnostics {
        lock.lock(); defer { lock.unlock() }
        return Diagnostics(created: created, mainThread: Thread.isMainThread,
            portPresent: tap != nil, portValid: tap.map(CFMachPortIsValid) ?? false,
            tapEnabled: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false, listenPermission: CGPreflightListenEventAccess(),
            readCause: lastReadCause, terminalCause: terminalCause,
            readCount: readCount, readyCount: readyCount, activityDuringReadCount: activityDuringReadCount,
            quietRefusalCount: quietRefusalCount, observedEventCount: observedEventCount,
            timeoutCallbacks: timeoutCallbacks, disabledByUserCallbacks: disabledByUserCallbacks,
            overflowCount: overflowCount, queuedEventCount: eventBuffer.events.count, originCounts: originCounts, privateSourceState: privateEventSource.sourceStateID.rawValue,
            tapLocation: activeTapLocation?.rawValue, waitingConsumption: eventBuffer.waitingConsumption)
    }
    // Readiness and monitor health are distinct. Normal user activity refuses
    // admission without declaring a dead listener. Existing generic gate still
    // receives unavailable, so no activity is converted into an idle snapshot.
    static func refusal(for cause: ReadCause) -> I.Unavailable {
        cause.activityRefusal || cause == .notStarted ? .notConnected : .sourceLost
    }
    private func refuse(_ cause: ReadCause) -> I.Availability {
        operationStop?.request(cause.activityRefusal ? .interference : .monitorLost)
        lastReadCause = cause
        if cause == .activityDuringRead { activityDuringReadCount += 1 }
        if cause == .warmupOrRecentActivity { quietRefusalCount += 1 }
        return .unavailable(Self.refusal(for: cause))
    }
    private let lock = NSLock()
    private var operationStop: MenuBarOperationStop?
    func bindOperationStop(_ stop: MenuBarOperationStop?) {
        lock.lock(); defer { lock.unlock() }; operationStop = stop
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activeTapLocation: CGEventTapLocation?
    private var reason: I.Unavailable = .notConnected
    private var continuity = UUID(), externalEpoch = UUID()
    private var sequence: UInt64 = 0
    private var startedAt: UInt64 = 0
    private var lastPhysicalActivityAt: Double?
    // .privateState is an allocation request (-1); Quartz returns a unique
    // positive state ID. Bind the registry to our actual allocated source.
    let privateEventSource = CGEventSource(stateID: .privateState)!
    private lazy var registry = MenuBarInputAttribution.Registry(senderPID: getpid(),
        privateSourceState: Int64(privateEventSource.sourceStateID.rawValue))
    struct Ticket { let marker: Int64; let epoch: UUID }
    struct StartFence: Codable, Equatable {
        let continuity: UUID, epoch: UUID
        let eventCount: Int
    }
    /// Same live session tap, including the local click. This never resets its
    /// epoch, drains an event, registers an exemption or grants an idle lease.
    func startFence() throws -> StartFence {
        _ = read()
        guard diagnostics().monitoringHealthy else { throw I.Failure.unavailable(.sourceLost) }
        lock.lock(); defer { lock.unlock() }
        guard registry.pending == nil, reason != .sourceLost, !eventBuffer.waiting else { throw I.Failure.interference }
        return .init(continuity: continuity, epoch: externalEpoch, eventCount: observedEventCount)
    }
    enum Receipt { case pending, matched, interrupted }
    private var matchedMarker: Int64?
    struct WaitingConsumption: Codable, Equatable {
        let continuity: UUID, beganAtMilliseconds: UInt64
        var lastBatchAtMilliseconds: UInt64, lastEpoch: UUID
        var batchCount = 0, consumedEventCount = 0
        var lastSourceEventCount: Int
        var firstEventSequence: UInt64?, lastEventSequence: UInt64?, lastEventAtMilliseconds: UInt64?
        var endedAtMilliseconds: UInt64?
    }
    /// Content-free waiting consumption. All counts/epochs stay in the source;
    /// only batches already observed before begin can leave this bounded queue.
    /// After begin, every event remains queued for the existing fence/Gate.
    struct EventBuffer {
        private(set) var events: [I.Event] = []
        private(set) var waitingConsumption: WaitingConsumption?
        private(set) var lost = false
        private(set) var capacityOverflow = false
        var waiting: Bool { waitingConsumption != nil && waitingConsumption?.endedAtMilliseconds == nil }
        mutating func append(_ event: I.Event) -> Bool {
            guard !lost else { return false }
            events.append(event)
            if events.count > 512 { lost = true; capacityOverflow = true; return false }
            return true
        }
        mutating func beginWaiting(continuity: UUID, epoch: UUID, count: Int, at now: UInt64) -> Bool {
            guard !lost, waitingConsumption == nil, count >= events.count else { return false }
            waitingConsumption = .init(continuity: continuity, beganAtMilliseconds: now,
                lastBatchAtMilliseconds: now, lastEpoch: epoch, lastSourceEventCount: count - events.count)
            return consumeWaiting(continuity: continuity, epoch: epoch, count: count, at: now)
        }
        mutating func consumeWaiting(continuity: UUID, epoch: UUID, count: Int, at now: UInt64) -> Bool {
            guard !lost, waiting, var record = waitingConsumption, record.continuity == continuity,
                  now >= record.lastBatchAtMilliseconds, count >= record.lastSourceEventCount,
                  count - record.lastSourceEventCount == events.count else { lost = true; return false }
            var previousSequence = record.lastEventSequence, previousTime = record.lastEventAtMilliseconds
            for event in events {
                guard event.continuity == continuity, event.uptimeMilliseconds <= now,
                      previousSequence.map({ event.sequence > $0 }) ?? true,
                      previousTime.map({ event.uptimeMilliseconds >= $0 }) ?? true else { lost = true; return false }
                if case .ownGesture = event.attribution { lost = true; return false }
                previousSequence = event.sequence; previousTime = event.uptimeMilliseconds
            }
            if record.firstEventSequence == nil { record.firstEventSequence = events.first?.sequence }
            record.lastEventSequence = previousSequence; record.lastEventAtMilliseconds = previousTime
            record.consumedEventCount += events.count; record.batchCount += 1
            record.lastSourceEventCount = count; record.lastEpoch = epoch; record.lastBatchAtMilliseconds = now
            waitingConsumption = record; events.removeAll(keepingCapacity: true)
            return true
        }
        mutating func endWaiting(at now: UInt64) -> Bool {
            guard !lost, waiting, let record = waitingConsumption, events.isEmpty,
                  now >= record.lastBatchAtMilliseconds else { lost = true; return false }
            waitingConsumption?.endedAtMilliseconds = now
            return true
        }
        mutating func drain() -> [I.Event] {
            let value = events; events.removeAll(keepingCapacity: true); return value
        }
    }
    private var eventBuffer = EventBuffer()
    func beginWaitingObservation() throws {
        _ = read()
        guard diagnostics().monitoringHealthy else { throw I.Failure.unavailable(.sourceLost) }
        lock.lock(); defer { lock.unlock() }
        guard registry.pending == nil, reason != .sourceLost,
              eventBuffer.beginWaiting(continuity: continuity, epoch: externalEpoch, count: observedEventCount, at: Self.now())
        else { rejectWaitingObservation(); throw I.Failure.unavailable(.sourceLost) }
    }
    func consumeWaitingObservation() throws {
        _ = read()
        guard diagnostics().monitoringHealthy else { throw I.Failure.unavailable(.sourceLost) }
        lock.lock(); defer { lock.unlock() }
        guard registry.pending == nil, reason != .sourceLost,
              eventBuffer.consumeWaiting(continuity: continuity, epoch: externalEpoch, count: observedEventCount, at: Self.now())
        else { rejectWaitingObservation(); throw I.Failure.unavailable(.sourceLost) }
    }
    func endWaitingObservation() throws {
        try consumeWaitingObservation()
        lock.lock(); defer { lock.unlock() }
        guard eventBuffer.endWaiting(at: Self.now()) else {
            rejectWaitingObservation(); throw I.Failure.unavailable(.sourceLost)
        }
    }
    private func rejectWaitingObservation() {
        if terminalCause == nil { terminalCause = .waitingObservationInvalid }
        reason = .sourceLost; registry.abandon()
    }
    private(set) var observedEventCount = 0
    private(set) var created = false
    private(set) var attributionFailures = 0
    private var localStart: MenuBarLocalStartReceipt?
    private var localMatchFacts: [String: Bool] = [:]
    struct LocalTrace: Codable {
        let tapLocation: UInt32?, configuredWindow: Int
        let appKitObservedAt: UInt64, claimAt: UInt64
        let callbackRunLoopMode: String?, appKitRunLoopMode: String
        let callbackCountBeforeRead: Int, callbackCountAfterRead: Int
        let captureBeforeRead: MenuBarLocalStartReceipt.CaptureDiagnostics
        let captureAfterRead: MenuBarLocalStartReceipt.CaptureDiagnostics
        let comparison: MenuBarLocalStartReceipt.Comparison
        let publicActivityDeltaMilliseconds: Double?
        let publicActivityComparison: MenuBarLocalStartReceipt.ActivityComparison
    }
    private var localTraces: [LocalTrace] = []
    private var lastLocalCallbackMode: String?
    func localStartTraces() -> [LocalTrace] { lock.lock(); defer { lock.unlock() }; return localTraces }
    func localStartMatchFacts() -> [String: Bool] { lock.lock(); defer { lock.unlock() }; return localMatchFacts }
    struct LocalBoundary {
        let proof: MenuBarLocalAcceptanceGate.StartProof, virtual: Bool
        fileprivate let continuity: UUID, epoch: UUID
    }
    enum LocalFailure: Error { case noExactStartReceipt, unexplainedActivity, interrupted }
    func configureLocalStart(window: Int) {
        lock.lock(); defer { lock.unlock() }
        localStart = .init(window: window, pid: getpid())
        localTraces = []; localMatchFacts = [:]; lastLocalCallbackMode = nil
    }
    // Virtual AppKit联调 only. Does not post CGEvent or forge a real tap receipt.
    func recordVirtualLocalStart(_ event: CGEvent) {
        lock.lock(); defer { lock.unlock() }
        localStart?.observed(.init(event), eventCount: observedEventCount, now: Self.now(), virtual: true)
    }
    func beginLocalCountdown(event: CGEvent, appKitTimestamp: Double, session: UUID, allowVirtual: Bool = false,
                             appKitObservedAt: UInt64? = nil, appKitRunLoopMode: String? = nil) throws -> LocalBoundary {
        let enteredAt = appKitObservedAt ?? Self.now(), uiMode = appKitRunLoopMode ?? Self.currentRunLoopMode()
        lock.lock()
        let beforeCount = observedEventCount, beforeCapture = localStart?.capture ?? .init()
        lock.unlock()
        _ = read() // Synchronize the public activity-age ledger before the boundary.
        guard diagnostics().monitoringHealthy else { throw LocalFailure.interrupted }
        lock.lock(); defer { lock.unlock() }
        if let localStart, localTraces.count < 4 {
            let now = Self.now()
            localTraces.append(.init(tapLocation: activeTapLocation?.rawValue, configuredWindow: localStart.window,
                appKitObservedAt: enteredAt, claimAt: now, callbackRunLoopMode: lastLocalCallbackMode, appKitRunLoopMode: uiMode,
                callbackCountBeforeRead: beforeCount, callbackCountAfterRead: observedEventCount,
                captureBeforeRead: beforeCapture, captureAfterRead: localStart.capture,
                comparison: localStart.comparison(.init(event), eventCount: observedEventCount, now: now),
                publicActivityDeltaMilliseconds: lastPhysicalActivityAt.flatMap { let delta = ($0 - appKitTimestamp) * 1000; return delta.isFinite ? delta : nil },
                publicActivityComparison: .init(hidActivity: lastPhysicalActivityAt, upTimestamp: appKitTimestamp)))
        }
        localMatchFacts = localStart?.matchFacts(.init(event), eventCount: observedEventCount, now: Self.now()) ?? [:]
        if let appKitObservedAt {
            let now = Self.now()
            guard now >= appKitObservedAt, now - appKitObservedAt <= 250 else { throw LocalFailure.noExactStartReceipt }
        }
        guard let (proof, virtual) = localStart?.claim(.init(event), eventCount: observedEventCount, now: Self.now(), session: session),
              !virtual || allowVirtual else { throw LocalFailure.noExactStartReceipt }
        // Any later tap event already prevents claim. The content-free age
        // signal must also be attributable to this exact up, not a later media key.
        if !virtual {
            let comparison = MenuBarLocalStartReceipt.ActivityComparison(hidActivity: lastPhysicalActivityAt, upTimestamp: appKitTimestamp)
            localMatchFacts["publicActivityMatchesExactUp"] = comparison.matchesExactUp
            guard comparison.matchesExactUp else { throw LocalFailure.unexplainedActivity }
        }
        localMatchFacts["bound"] = true
        return .init(proof: proof, virtual: virtual, continuity: continuity, epoch: externalEpoch)
    }
    func localCountdownUnchanged(_ boundary: LocalBoundary) -> Bool {
        _ = read()
        guard diagnostics().monitoringHealthy else { return false }
        lock.lock(); defer { lock.unlock() }
        return boundary.continuity == continuity && boundary.epoch == externalEpoch && reason != .sourceLost
    }
    func start(_ policy: Policy = .disabled) throws {
        guard let location = policy.location else { throw I.Failure.unavailable(.notConnected) }
        guard Thread.isMainThread, tap == nil else { throw I.Failure.busy }
        guard CGPreflightListenEventAccess() else {
            lastReadCause = .permissionMissing; throw I.Failure.unavailable(.permissionRequired)
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .keyDown, .keyUp, .flagsChanged, .scrollWheel, .tabletPointer, .tabletProximity]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // Window-addressed local receipts require the annotated application
        // stage. The real move transport keeps its original session-stage tap.
        activeTapLocation = location
        guard let port = CGEvent.tapCreate(tap: location, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                Unmanaged<MenuBarListenOnlyInterferenceSource>.fromOpaque(context).takeUnretainedValue().receive(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runSource = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            lastReadCause = .missingPort; throw I.Failure.unavailable(.sourceLost)
        }
        tap = port; source = runSource; created = true
        startedAt = Self.now()
        lastPhysicalActivityAt = nil
        continuity = UUID(); externalEpoch = UUID(); reason = .notConnected; terminalCause = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            terminalCause = .disabledPort; lastReadCause = .disabledPort
            stop(); throw I.Failure.unavailable(.sourceLost)
        }
    }
    func stop() {
        operationStop?.request(.monitorLost)
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        lock.lock(); reason = .sourceLost; terminalCause = terminalCause ?? .stopped; registry.abandon(); lock.unlock()
    }
    deinit { stop() }
    private static func now() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }
    static func currentRunLoopMode() -> String {
        guard let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) else { return "none" }
        if mode == .defaultMode { return "default" }
        switch mode.rawValue as String {
        case "NSEventTrackingRunLoopMode": return "eventTracking"
        case "NSModalPanelRunLoopMode": return "modalPanel"
        default: return "other"
        }
    }
    static func envelope(_ event: CGEvent) -> MenuBarInputAttribution.Envelope {
        .init(type: event.type.rawValue, timestamp: event.timestamp,
            sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceState: event.getIntegerValueField(.eventSourceStateID),
            targetPID: event.getIntegerValueField(.eventTargetUnixProcessID),
            marker: event.getIntegerValueField(.eventSourceUserData),
            window: event.getIntegerValueField(.mouseEventWindowUnderMousePointer),
            handlingWindow: event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent),
            privateWindow: event.getIntegerValueField(CGEventField(rawValue: 0x33)!),
            number: event.getIntegerValueField(.mouseEventNumber), flags: event.flags.rawValue, point: event.location)
    }
    func register(_ event: CGEvent, gesture: UUID) throws {
        _ = try registerForReceipt(event, gesture: gesture)
    }
    func registerForReceipt(_ event: CGEvent, gesture: UUID, expectedEpoch: UUID? = nil, expectedContinuity: UUID? = nil) throws -> Ticket {
        lock.lock(); defer { lock.unlock() }
        guard tap != nil, reason != .sourceLost else { throw I.Failure.unavailable(.sourceLost) }
        guard expectedEpoch.map({ $0 == externalEpoch }) ?? true,
              expectedContinuity.map({ $0 == continuity }) ?? true else { throw I.Failure.interference }
        try registry.register(Self.envelope(event), gesture: gesture, now: Self.now())
        matchedMarker = nil
        return Ticket(marker: event.getIntegerValueField(.eventSourceUserData), epoch: externalEpoch)
    }
    func receipt(_ ticket: Ticket) -> Receipt {
        lock.lock(); defer { lock.unlock() }
        guard reason != .sourceLost, ticket.epoch == externalEpoch else { return .interrupted }
        return matchedMarker == ticket.marker ? .matched : .pending
    }
    func abandonReceipt() {
        lock.lock(); defer { lock.unlock() }; registry.abandon(); matchedMarker = nil
    }
    func receive(_ type: CGEventType, _ event: CGEvent) {
        lock.lock(); defer { lock.unlock() }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            operationStop?.request(.monitorLost)
            if type == .tapDisabledByTimeout { timeoutCallbacks += 1; terminalCause = .callbackTimeout }
            else { disabledByUserCallbacks += 1; terminalCause = .callbackDisabledByUserInput }
            reason = .sourceLost; externalEpoch = UUID(); registry.abandon(); return
        }
        sequence += 1; observedEventCount += 1
        let time = Self.now()
        if type == .leftMouseUp, localStart != nil {
            lastLocalCallbackMode = Self.currentRunLoopMode()
            localStart?.observeMouseUp(type: type.rawValue,
                pointerWindow: event.getIntegerValueField(.mouseEventWindowUnderMousePointer),
                handlingWindow: event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent),
                packet: .init(event), eventCount: observedEventCount, now: time)
        }
        var attribution: I.Attribution = .unknown
        // Inspect packet details only for a pre-registered own mouse emission.
        // All other input is just activity: no text, keycode, app or coordinates.
        if let pending = registry.pending,
           [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(type),
           event.getIntegerValueField(.eventSourceUserData) == pending.envelope.marker,
           event.getIntegerValueField(.eventSourceUnixProcessID) == pending.envelope.sourcePID {
            attribution = registry.consume(Self.envelope(event), now: time)
            if case .ownGesture = attribution { matchedMarker = pending.envelope.marker }
        }
        let origin: MenuBarInputAttribution.Origin
        if case .ownGesture = attribution { origin = .registeredOwn }
        else {
            // Two scalar fields only; retain coarse counters, never PID, text,
            // keycode, cursor coordinates or application attribution.
            origin = MenuBarInputAttribution.origin(sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
                state: event.getIntegerValueField(.eventSourceStateID), selfPID: getpid(), tools: diagnosticToolPIDs)
            externalEpoch = UUID(); attributionFailures += 1
            operationStop?.request(.externalInput)
        }
        originCounts[origin.rawValue, default: 0] += 1
        if !eventBuffer.append(.init(sequence: sequence, uptimeMilliseconds: time, continuity: continuity, attribution: attribution)) {
            operationStop?.request(.monitorLost)
            if eventBuffer.capacityOverflow { overflowCount += 1 }
            if terminalCause == nil { terminalCause = eventBuffer.capacityOverflow ? .queueOverflow : .waitingObservationInvalid }
            reason = .sourceLost; registry.abandon()
        }
    }
    func drainEvents() -> [I.Event] {
        lock.lock(); defer { lock.unlock() }
        return eventBuffer.drain()
    }
    func read() -> I.Availability {
        readCount += 1
        guard Thread.isMainThread else { return refuse(.wrongThread) }
        guard let tap else { return refuse(created ? .stopped : .notStarted) }
        guard CFMachPortIsValid(tap) else { return refuse(.invalidPort) }
        guard CGEvent.tapIsEnabled(tap: tap) else { return refuse(terminalCause ?? .disabledPort) }
        guard CGPreflightListenEventAccess() else { return refuse(.permissionMissing) }
        // Drain the main-run-loop tap before a boundary. Every unknown event
        // changes the epoch, including moves/scrolls and unregistered injection.
        _ = CFRunLoopRunInMode(.defaultMode, 0.002, true)
        lock.lock(); let epochBefore = externalEpoch; let lost = reason == .sourceLost; lock.unlock()
        guard !lost else { return refuse(terminalCause ?? .invalidPort) }
        var buttons: Set<UInt16> = []
        // Coverage is the public mouse gesture domain, not an assertion that
        // every device button/key is released. Other-button/keyboard activity
        // during the lease always invalidates it; key contents are never read.
        for button in [CGMouseButton.left, .right, .center] {
            if CGEventSource.buttonState(.hidSystemState, button: button) { buttons.insert(UInt16(button.rawValue)) }
        }
        let gestureModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
        let modifiers = CGEventSource.flagsState(.hidSystemState).intersection(gestureModifiers).rawValue
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return refuse(.invalidAnyInputType) }
        let age = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        let activitySampleTime = ProcessInfo.processInfo.systemUptime
        _ = CFRunLoopRunInMode(.defaultMode, 0.002, true)
        lock.lock(); defer { lock.unlock() }
        guard reason != .sourceLost else { return refuse(terminalCause ?? .invalidPort) }
        guard epochBefore == externalEpoch else { return refuse(.activityDuringRead) }
        guard age.isFinite, age >= 0 else { return refuse(.invalidActivityAge) }
        // This content-free signal also covers keyboard activity which Quartz
        // does not deliver as keyDown/keyUp (SDK explicitly notes media keys).
        // A later quiet period cannot erase activity during an armed lease.
        if Self.physicalActivityChanged(previous: lastPhysicalActivityAt, now: activitySampleTime, age: age) {
            externalEpoch = UUID()
            operationStop?.request(.interference)
        }
        lastPhysicalActivityAt = activitySampleTime - age
        guard Self.initialQuiet(now: Self.now(), startedAt: startedAt, age: age) else { return refuse(.warmupOrRecentActivity) }
        lastReadCause = .ready; readyCount += 1
        sequence += 1
        return .available(.init(sequence: sequence, uptimeMilliseconds: Self.now(), continuity: continuity,
            externalEpoch: externalEpoch, coverage: I.requiredCoverage, buttons: buttons, keys: [], modifiers: modifiers))
    }
    static func initialQuiet(now: UInt64, startedAt: UInt64, age: Double) -> Bool {
        now >= startedAt && now - startedAt >= 250 && age.isFinite && age >= 0.25
    }
    static func physicalActivityChanged(previous: Double?, now: Double, age: Double) -> Bool {
        guard let previous else { return false }
        // Allow 2ms call/clock jitter; a qualified prior boundary was already
        // >=250ms quiet, so a new activity is separated by much more than this.
        return now - age > previous + 0.002
    }
}
