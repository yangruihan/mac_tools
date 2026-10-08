// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import ApplicationServices
import AppKit

/// Independent annotated listen-only adapter. It never links an event sender,
/// changes permission, suppresses an event, or re-enables a lost tap.
final class MenuBarLocalStartInput {
    typealias L = MenuBarLocalContinuityLedger
    struct Reads {
        let now: () -> UInt64, counter: () -> UInt32?, age: () -> Double?
        let buttons: () -> UInt64, modifiers: () -> UInt64, healthy: () -> Bool, pump: () -> Void
    }
    struct Diagnostics: Codable {
        let native, mainThread, portValid, tapEnabled, listenPermission, monitoringHealthy: Bool
        let tapLocation: UInt32
        let observedEventCount, sampleCount: Int
        let state, startupStage: String
    }
    struct Evidence: Codable {
        let scope: String, continuity: UUID, state: String
        let proof: L.Proof?, finalSampleSequence: UInt64?
        let nodes: [L.Node]
        let firstFailure: L.FirstFailure?
        let startupFailure: StartupFailure?
        var requestBoundary: L.RequestBoundary? = nil
        var startPolicy: L.StartPolicy? = nil
        var startHistoryBoundary: L.StartHistoryBoundary? = nil
    }
    struct StartupFailure: Codable {
        let rejectedStage: String, diagnosticsBeforeCleanup: Diagnostics
    }
    private(set) var ledger: L
    private let reads: Reads?
    private var tap: CFMachPort?, source: CFRunLoopSource?
    private var measuring = false, closed = false
    private var sampleCount = 0
    private var startupStage = "notAttempted"
    private var startupFailure: StartupFailure?
    static var observationRunLoopModes: [CFRunLoopMode] {
        [.commonModes, CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString)]
    }
    init(session: UUID, pid: Int32, purpose: L.Purpose = .noMove, startPolicy: L.StartPolicy = .preUpContinuity) {
        ledger = L(session: session, pid: pid, purpose: purpose, startPolicy: startPolicy); reads = nil
    }
    /// Tests exercise this same adapter with recorded public reads, no native tap.
    init(session: UUID, pid: Int32, isolatedReads: Reads, purpose: L.Purpose = .noMove, startPolicy: L.StartPolicy = .preUpContinuity) {
        ledger = L(session: session, pid: pid, purpose: purpose, startPolicy: startPolicy); reads = isolatedReads
    }
    var now: UInt64 { reads?.now() ?? DispatchTime.now().uptimeNanoseconds }
    var state: L.State { ledger.state }
    func configureLocalStart(window: Int) { ledger.configure(window: window); poll() }
    func start() throws {
        startupStage = "policyCheck"
        guard reads == nil, tap == nil, !closed, Thread.isMainThread, CGPreflightListenEventAccess() else { throw startupRejected() }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
            .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .keyDown, .keyUp, .flagsChanged, .scrollWheel, .tabletPointer, .tabletProximity]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        startupStage = "tapCreation"
        guard let port = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context { Unmanaged<MenuBarLocalStartInput>.fromOpaque(context).takeUnretainedValue().receive(type, event: event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw startupRejected() }
        startupStage = "runLoopSourceCreation"
        guard let runSource = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            let failure = startupRejected(); CFMachPortInvalidate(port); throw failure
        }
        tap = port; source = runSource
        for mode in Self.observationRunLoopModes { CFRunLoopAddSource(CFRunLoopGetMain(), runSource, mode) }
        CGEvent.tapEnable(tap: port, enable: true)
        startupStage = "enabledHealthCheck"
        guard healthy() else { let failure = startupRejected(); stop(); throw failure }
        startupStage = "initialSample"
        _ = measure()
        startupStage = ledger.stopped ? "initialSampleRejected" : "started"
    }
    func stop() {
        guard !closed else { return }; closed = true
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { for mode in Self.observationRunLoopModes { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, mode) } }
        tap = nil; source = nil
    }
    deinit { stop() }
    func beginStart(_ packet: MenuBarLocalStartReceipt.Packet, virtual: Bool = false) {
        if virtual { ledger.fail(.virtualUnsupported); return }
        ledger.begin(packet, at: now)
    }
    func matchStart() { poll(); ledger.claim(at: now) }
    func startRequestWarmup() { ledger.startRequestWarmup(at: now) }
    func cancel() { ledger.fail(.cancelled) }
    func sessionContinuityLost() { ledger.lost(at: now) }
    func injectActivityForVirtualCheck() { ledger.fail(.laterInput) }
    func poll() {
        guard !closed, !ledger.stopped, state != .validatedNoMove else { return }
        pump(); _ = measure(); pump(); _ = measure()
        if state == .awaitingRequestQuiet {
            let first = measure(); pump(); _ = measure()
            ledger.completeRequestQuiet(firstNewSequence: first, at: now)
        }
        if state == .awaitingFreshQuiet {
            // A separate new scan starts AFTER the deadline. Timer expiry alone
            // cannot complete this round; both samples retain the same journal.
            let first = measure(); pump(); _ = measure()
            ledger.complete(firstNewSequence: first, at: now)
        }
    }
    func diagnostics() -> Diagnostics {
        let permission = reads == nil ? CGPreflightListenEventAccess() : reads!.healthy()
        let valid = tap.map(CFMachPortIsValid) ?? (reads != nil && !closed)
        let enabled = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? (reads != nil && !closed)
        return .init(native: reads == nil, mainThread: Thread.isMainThread, portValid: valid,
            tapEnabled: enabled, listenPermission: permission, monitoringHealthy: healthy(),
            tapLocation: CGEventTapLocation.cgAnnotatedSessionEventTap.rawValue,
            observedEventCount: ledger.tapCount, sampleCount: sampleCount, state: String(describing: state), startupStage: startupStage)
    }
    func evidence() -> Evidence {
        .init(scope: ledger.purpose == .noMove ? (reads == nil ? "nativeReadObservations" : "isolatedInjectedNativeAdapter")
                : (reads == nil ? "nativeRealStartReadObservations" : "isolatedRealStartAdapter"),
            continuity: ledger.continuity, state: String(describing: state), proof: ledger.proof,
            finalSampleSequence: ledger.finalSampleSequence, nodes: ledger.nodes, firstFailure: ledger.firstFailure,
            startupFailure: startupFailure, requestBoundary: ledger.requestBoundary,
            startPolicy: ledger.startPolicy == .preUpContinuity ? nil : ledger.startPolicy,
            startHistoryBoundary: ledger.startHistoryBoundary)
    }
    private func startupRejected() -> L.Cause {
        if startupFailure == nil { startupFailure = .init(rejectedStage: startupStage, diagnosticsBeforeCleanup: diagnostics()) }
        return .monitorLost
    }
    func matchFacts() -> [String: Bool] { ledger.matchFacts(at: now) }
    private func healthy() -> Bool {
        guard !closed, Thread.isMainThread else { return false }
        if let reads { return reads.healthy() }
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) && CGPreflightListenEventAccess()
    }
    private func pump() {
        if let reads { reads.pump() }
        else { _ = CFRunLoopRunInMode(.defaultMode, 0.002, false) }
    }
    private func counter() -> UInt32? {
        if let reads { return reads.counter() }
        guard let any = CGEventType(rawValue: UInt32.max) else { return nil }
        return CGEventSource.counterForEventType(.hidSystemState, eventType: any)
    }
    private func age() -> Double? {
        if let reads { return reads.age() }
        guard let any = CGEventType(rawValue: UInt32.max) else { return nil }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
    }
    private func buttons() -> UInt64 {
        if let reads { return reads.buttons() }
        let hid = [CGMouseButton.left, .right, .center].reduce(UInt64(0)) {
            CGEventSource.buttonState(.hidSystemState, button: $1) ? $0 | UInt64(1) << $1.rawValue : $0
        }
        // Instantaneous admission/held-state only, never event tracking or
        // attribution. AppKit exposes all currently pressed button bits.
        return ledger.startPolicy.usesRequestQuiet ? hid | UInt64(truncatingIfNeeded: NSEvent.pressedMouseButtons) : hid
    }
    private func modifiers() -> UInt64 {
        if let reads { return reads.modifiers() }
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
        return CGEventSource.flagsState(.hidSystemState).intersection(mask).rawValue
    }
    @discardableResult private func measure() -> UInt64 {
        guard !measuring else { ledger.fail(.boundaryGap); return ledger.lastSequence }
        measuring = true; defer { measuring = false }
        let rawReads = reads ?? Reads(now: { self.now }, counter: { self.counter() }, age: { self.age() },
            buttons: { self.buttons() }, modifiers: { self.modifiers() }, healthy: { self.healthy() }, pump: {})
        let sample = Self.readRawSample(using: rawReads)
        sampleCount += 1; ledger.sampled(sample)
        return ledger.lastSequence
    }
    /// Reused by the no-action timing probe. Raw reads alone do not configure a
    /// window, start a tap, form a ledger proof or authorize any operation.
    static func readRawSample(using reads: Reads) -> L.Sample {
        let began = reads.now(), beforeHealth = reads.healthy(), beforeCount = reads.counter()
        let ageBegan = reads.now(), rawAge = reads.age(), ageEnded = reads.now()
        let buttons = reads.buttons(), modifiers = reads.modifiers()
        let afterCount = reads.counter(), afterHealth = reads.healthy(), ended = reads.now()
        let finiteAge = rawAge.flatMap { $0.isFinite ? $0 : nil }
        return .init(began: began, ended: ended, counterBefore: beforeCount, counterAfter: afterCount,
            age: finiteAge, buttons: buttons, modifiers: modifiers, healthyBefore: beforeHealth, healthyAfter: afterHealth,
            ageReadBegan: ageBegan, ageReadEnded: ageEnded)
    }
    func receive(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { ledger.lost(at: now); return }
        let own = type == .leftMouseUp && ledger.window > 0 &&
            (event.getIntegerValueField(.mouseEventWindowUnderMousePointer) == Int64(ledger.window) ||
             event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == Int64(ledger.window))
        receiveOwnedOrActivity(ownPacket: own ? .init(event) : nil,
            activity: own ? nil : .init(type: type.rawValue, timestamp: event.timestamp))
    }
    private func receiveOwnedOrActivity(ownPacket: MenuBarLocalStartReceipt.Packet?, activity: L.Activity?) {
        guard !closed else { return }
        guard healthy() else { ledger.lost(at: now); return }
        if measuring { ledger.fail(.boundaryGap); return }
        ledger.event(ownPacket: ownPacket, at: now, activity: activity)
        _ = measure() // Receipt predecessor/first post-receipt guard, on the same serial adapter.
    }
}
// Existing no-sender entry keeps the default purpose and has no real permit API.
typealias MenuBarLocalNoMoveInput = MenuBarLocalStartInput
