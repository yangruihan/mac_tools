// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import ApplicationServices
import Darwin
#if REQUEST_WARMUP_DIAGNOSTIC && !REAL_INPUT_DIAGNOSTIC
#error("Request warmup is restricted to the separately linked sender-free diagnostic.")
#endif
#if OWNED_LIVE_CONTROLLER && REAL_INPUT_DIAGNOSTIC
#error("The real worker and sender-free diagnostic must be separate executables.")
#endif

/// A real worker owns this broker and BOTH live monitors for their entire
/// overlap. A no-move result/JSON is never accepted as input to this API.
final class MenuBarRealLocalAuthorization {
    typealias M = MenuBarHiddenMoveModel
    typealias F = MenuBarListenOnlyInterferenceSource.StartFence
    enum Authority: String, Codable { case nativeRealWorker, nativeDiagnostic, isolated, unavailableNative }
    static var nativeAuthority: Authority {
        #if OWNED_LIVE_CONTROLLER
        return .nativeRealWorker
        #elseif REAL_INPUT_DIAGNOSTIC
        return .nativeDiagnostic
        #else
        return .unavailableNative
        #endif
    }
    static var nativeStartPolicy: MenuBarLocalContinuityLedger.StartPolicy {
        #if OWNED_LIVE_CONTROLLER
        return .requestQuietReal
        #elseif REQUEST_WARMUP_DIAGNOSTIC
        return .requestQuietDiagnostic
        #else
        return .preUpContinuity
        #endif
    }
    struct Handoff: Codable {
        let binding: MenuBarDispatchWitness.Binding
        let gesture: UUID, sourceFence: F, input: MenuBarLocalStartInput.Evidence
        let atUptimeNanoseconds: UInt64
    }
    struct HandoffAttempt: Codable {
        let gesture, continuity, externalEpoch: UUID
    }
    struct Terminal: Codable {
        let binding: MenuBarDispatchWitness.Binding
        let atUptimeNanoseconds: UInt64, failure: String?
        let stoppedCause: MenuBarLocalContinuityLedger.Cause?
        let capturedStart: MenuBarLocalStartReceipt.Packet?
        let matchedStartCount, validationCount: Int
        let permitIssued, handedOff: Bool
        let sourceFence: F?, lastObservedSourceFence: F?, handoffAttempt: HandoffAttempt?
        let matchFacts: [String: Bool]
        let diagnostics: MenuBarLocalStartInput.Diagnostics
        let input: MenuBarLocalStartInput.Evidence
        var authority: Authority? = nil // Optional for decoding historical receipts.
        var bindingRejection: BindingRejection? = nil
        var layoutCommit: LayoutCommit? = nil
        var layoutFailure: String? = nil
        var backupContext: MenuBarLocalDiagnosticReceipt.Context {
            .init(nonce: binding.nonce, controllerPID: binding.controllerPID, scope: input.scope, failure: failure,
                state: input.state, startupStage: diagnostics.startupStage, nodeCount: input.nodes.count, firstFailure: input.firstFailure)
        }
    }
    enum Failure: Error {
        case state, expired, binding, interference, used, nonNative
        case stopped(MenuBarLocalContinuityLedger.Cause)
        case layout(String)
    }
    struct BindingRejection: Codable, Equatable {
        enum Check: String, Codable { case processIdentity, inputPlan, requestProof, layoutCommit }
        let check: Check, failedFields: [String]
    }
    static func changedPlanFacts(_ a: M.Snapshot, _ b: M.Snapshot) -> [String] {
        [("scope", a.scope == b.scope), ("owner", a.owner == b.owner), ("items", a.items == b.items),
         ("membershipIDs", a.membershipIDs == b.membershipIDs), ("orderEvidence", a.orderEvidence == b.orderEvidence),
         ("carriers", a.carriers == b.carriers)].filter { !$0.1 }.map { $0.0 }
    }
    /// Startup admission fixes intent, not geometry authorized for an action.
    /// This comparison is used only ONCE during countdown, before any Permit.
    /// After that boundary the existing full sameFacts comparison still applies.
    static func changedLayoutIntent(_ prepared: M.Plan, _ action: M.Plan) -> [String] {
        let a = prepared.original, b = action.original
        var fields = [("scope", a.scope == b.scope), ("owner", a.owner == b.owner),
            ("anchor", prepared.anchor == action.anchor), ("membershipIDs", a.membershipIDs == b.membershipIDs),
            ("orderEvidence", a.orderEvidence == b.orderEvidence), ("carriers", a.carriers == b.carriers),
            ("itemIdentities", a.items.map(\.identity) == b.items.map(\.identity))]
        let pairs = Array(zip(a.items, b.items))
        fields.append(("itemStates", a.items.count == b.items.count && pairs.allSatisfy { x, y in
            x.listedOnScreen == y.listedOnScreen && x.onScreen == y.onScreen && x.alpha == y.alpha
                && x.spaces == y.spaces && x.ownerOcclusionVisible == y.ownerOcclusionVisible
                && x.frame.minY == y.frame.minY && x.frame.height == y.frame.height
        }))
        // A peer's width may change before authorization. Our own T/N widths
        // are fixed by this fixture; changing them cannot pass as the same intent.
        fields.append(("ownedItemSizes", pairs.filter { $0.0.identity.pid == a.owner.target.pid }
            .allSatisfy { $0.0.frame.size == $0.1.frame.size }))
        return fields.filter { !$0.1 }.map { $0.0 }
    }
    struct LayoutCommit: Codable {
        let prepared, action: M.Plan
        let request: MenuBarLocalContinuityLedger.RequestBoundary
        let beganAt, committedAt, countdownStartedAt, countdownDeadline: UInt64
        let sourceFence: F
    }
    final class Permit {
        fileprivate let owner: MenuBarRealLocalAuthorization
        private(set) var consumed = false
        var handedOff: Bool { consumed && owner.handedOff }
        var diagnosticOnly: Bool { owner.authority == .nativeDiagnostic || owner.monitor.ledger.startPolicy == .requestQuietDiagnostic }
        var authority: Authority { owner.authority }
        fileprivate init(_ owner: MenuBarRealLocalAuthorization) { self.owner = owner }
        /// A process-local capability only. Neither a decoded proof nor an
        /// isolated broker may account for a real action, even with real policy.
        func checkForRealAction(binding expected: MenuBarDispatchWitness.Binding) throws {
            guard !consumed else { throw Failure.used }
            guard owner.authority == .nativeRealWorker, !diagnosticOnly,
                  owner.nativeRequired, owner.monitor.diagnostics().native,
                  owner.monitor.ledger.startPolicy == .requestQuietReal else { throw Failure.nonNative }
            guard expected == owner.binding, expected.controllerPID == getpid() else {
                owner.recordBindingRejection(.processIdentity, fields: [
                    ("expectedBinding", expected == owner.binding), ("controllerPID", expected.controllerPID == getpid())])
                throw Failure.binding
            }
            let identity = try MenuBarProcessSignature.read(getpid())
            guard identity.launch == expected.controllerLaunch, identity.sha256 == expected.controllerSHA256 else {
                owner.recordBindingRejection(.processIdentity, fields: [
                    ("controllerLaunch", identity.launch == expected.controllerLaunch),
                    ("controllerSHA256", identity.sha256 == expected.controllerSHA256)])
                throw Failure.binding
            }
            // Re-poll both monitors AFTER reading our identity; even this read
            // cannot introduce an unobserved gap before action consumption.
            try owner.check(owner.plan)
        }
        func check(_ plan: M.Plan) throws {
            guard !consumed else { throw Failure.used }
            try owner.check(plan)
        }
        func handoff(_ plan: M.Plan, lease: MenuBarMoveInterference.Lease) throws {
            guard !consumed else { throw Failure.used }; consumed = true
            owner.handoffAttempt = .init(gesture: lease.gesture, continuity: lease.continuity, externalEpoch: lease.externalEpoch)
            try owner.check(plan)
            guard let fence = owner.fence, fence.continuity == lease.continuity, fence.epoch == lease.externalEpoch else { throw Failure.interference }
            try owner.evidence?.append("real-local-handoff", Handoff(binding: owner.binding, gesture: lease.gesture,
                sourceFence: fence, input: owner.monitor.evidence(), atUptimeNanoseconds: owner.monitor.now))
            // The real Gate is ALREADY armed on the continuously running
            // session source. Stop only the overlapping annotated monitor.
            owner.handedOff = true; owner.monitor.stop()
        }
    }
    /// Shared by the native coordinator and the sender-free diagnostic build.
    /// Keep the same ordering: permit check, fresh idle read, pre-lease drain,
    /// Gate arm, durable handoff. No diagnostic snapshot can replace a Permit.
    static func armAndHandoff(_ plan: M.Plan, permit: Permit?, input: any MenuBarHiddenInterferenceSource,
                              gate: inout MenuBarMoveInterference.Gate, now: () -> UInt64) throws {
        try checkGateEntry(plan, permit: permit)
        let initialInput = input.read()
        _ = input.drainEvents() // These precede the idle snapshot/lease baseline.
        _ = try gate.begin(initialInput, now: now())
        try permit?.handoff(plan, lease: gate.lease!)
    }
    /// Also used before the durable action-attempt marker. Real builds reject
    /// nil, old-policy, diagnostic and injected Permits before any idle read.
    static func checkGateEntry(_ plan: M.Plan, permit: Permit?) throws {
        #if OWNED_LIVE_CONTROLLER
        guard let permit else { throw Failure.nonNative }
        try permit.checkForRealAction(binding: permit.owner.binding)
        try permit.check(plan)
        #else
        #if !REAL_INPUT_DIAGNOSTIC
        guard permit?.diagnosticOnly != true else { throw Failure.nonNative }
        #endif
        if let permit, permit.owner.monitor.ledger.startPolicy == .requestQuietReal {
            try permit.checkForRealAction(binding: permit.owner.binding)
        }
        try permit?.check(plan)
        #endif
    }
    let binding: MenuBarDispatchWitness.Binding
    private let preparedPlan: M.Plan
    var plan: M.Plan { layoutCommit?.action ?? preparedPlan }
    let monitor: MenuBarLocalStartInput
    let authority: Authority
    private let readFence: () throws -> F
    struct WaitingHooks {
        let poll: () throws -> Void, end: () throws -> Void
    }
    private let waiting: WaitingHooks
    private let expires: UInt64, evidence: MenuBarMoveStageRecorder?
    private var fence: F?, issued = false, polling = false, handedOff = false
    private var lastObservedFence: F?, handoffAttempt: HandoffAttempt?
    private var capturedStart: MenuBarLocalStartReceipt.Packet?
    private(set) var terminalEvidence: Terminal?
    private(set) var bindingRejection: BindingRejection?
    private func recordBindingRejection(_ check: BindingRejection.Check, fields: [(String, Bool)]) {
        guard bindingRejection == nil else { return }
        bindingRejection = .init(check: check, failedFields: fields.filter { !$0.1 }.map { $0.0 })
    }
    private(set) var terminalEvidenceFailure: String?
    private(set) var terminalBackupFailure: String?, terminalBackupWritten = false
    private let terminalBackupURL: URL?
    private let nativeRequired: Bool
    private let captureActionLayout: (() throws -> M.Plan)?
    private var layoutAttempted = false
    private(set) var layoutCommit: LayoutCommit?
    private(set) var layoutFailure: String?
    init(binding: MenuBarDispatchWitness.Binding, plan: M.Plan, input: MenuBarListenOnlyInterferenceSource,
         expires: UInt64, evidence: MenuBarMoveStageRecorder?, captureActionLayout: (() throws -> M.Plan)? = nil) throws {
        guard Self.nativeAuthority != .nativeRealWorker || captureActionLayout != nil else { throw Failure.layout("providerUnavailable") }
        self.binding = binding; preparedPlan = plan; self.expires = expires; self.evidence = evidence
        self.captureActionLayout = captureActionLayout
        terminalBackupURL = evidence?.directory.deletingLastPathComponent().appendingPathComponent("local-input-terminal.json")
        authority = Self.nativeAuthority
        monitor = .init(session: binding.nonce, pid: binding.controllerPID, purpose: .realStart, startPolicy: Self.nativeStartPolicy)
        readFence = { try input.startFence() }; nativeRequired = true
        waiting = .init(poll: { try input.consumeWaitingObservation() }, end: { try input.endWaitingObservation() })
        try input.beginWaitingObservation()
    }
    /// Offline-only dependency injection: it can exercise the same broker, but
    /// cannot create a native tap or enter the native window/controller path.
    init(binding: MenuBarDispatchWitness.Binding, plan: M.Plan, reads: MenuBarLocalStartInput.Reads,
         fence: @escaping () throws -> F, expires: UInt64, evidence: MenuBarMoveStageRecorder? = nil, terminalBackupURL: URL? = nil,
         startPolicy: MenuBarLocalContinuityLedger.StartPolicy = .preUpContinuity,
         waiting: WaitingHooks = .init(poll: {}, end: {}), captureActionLayout: (() throws -> M.Plan)? = nil) {
        self.binding = binding; preparedPlan = plan; self.expires = expires; self.evidence = evidence
        self.captureActionLayout = captureActionLayout
        authority = .isolated // Caller cannot override provenance by selecting a policy.
        self.terminalBackupURL = terminalBackupURL
        monitor = .init(session: binding.nonce, pid: binding.controllerPID, isolatedReads: reads, purpose: .realStart, startPolicy: startPolicy)
        readFence = fence; nativeRequired = false
        self.waiting = waiting
    }
    func begin(_ event: CGEvent) {
        let packet = MenuBarLocalStartReceipt.Packet(event)
        if capturedStart == nil { capturedStart = packet }
        guard monitor.state == .ready else { return }
        do { try waiting.end() }
        catch { monitor.sessionContinuityLost(); return }
        monitor.beginStart(packet); monitor.matchStart()
    }
    func cancel() { monitor.cancel() }
    /// Snapshot before UI cleanup changes the state or stops the annotated tap.
    /// This is diagnostic only: it never polls, resets a fence, or grants a permit.
    /// Retain the first snapshot even when its durable write is uncertain; no retry.
    func recordTerminal(_ error: Error?) throws {
        guard terminalEvidence == nil else { return }
        let cause: MenuBarLocalContinuityLedger.Cause?
        if case .stopped(let value) = monitor.state { cause = value } else { cause = nil }
        let snapshot = Terminal(binding: binding, atUptimeNanoseconds: monitor.now,
            failure: error.map { String(describing: $0) }, stoppedCause: cause, capturedStart: capturedStart,
            matchedStartCount: monitor.ledger.matchedStartCount, validationCount: monitor.ledger.validationCount,
            permitIssued: issued, handedOff: handedOff, sourceFence: fence,
            lastObservedSourceFence: lastObservedFence, handoffAttempt: handoffAttempt, matchFacts: monitor.matchFacts(),
            diagnostics: monitor.diagnostics(), input: monitor.evidence(), authority: authority,
            bindingRejection: bindingRejection, layoutCommit: layoutCommit, layoutFailure: layoutFailure)
        terminalEvidence = snapshot
        var primaryFailure: Error?
        do { try evidence?.append("real-local-ui-terminal", snapshot) }
        catch { terminalEvidenceFailure = String(describing: error); primaryFailure = error }
        // Independent O_EXCL/fsync peer is attempted even after a poisoned or
        // uncertain stage write. It never overwrites either receipt or grants
        // permission to continue after the original stage failure.
        if let terminalBackupURL {
            do {
                let bytes = try MenuBarLocalDiagnosticReceipt.encode(snapshot, context: snapshot.backupContext,
                    primaryWriteFailure: terminalEvidenceFailure)
                try MenuBarDispatchWitness.writeNew(bytes, to: terminalBackupURL)
                terminalBackupWritten = true
            } catch { terminalBackupFailure = String(describing: error) }
        }
        if let primaryFailure { throw primaryFailure }
    }
    func poll() throws {
        guard !handedOff, !polling else { return }
        if let layoutFailure { throw Failure.layout(layoutFailure) }
        polling = true; defer { polling = false }
        guard monitor.now <= expires else { monitor.cancel(); throw Failure.expired }
        if monitor.state == .ready {
            do { try waiting.poll() }
            catch { monitor.sessionContinuityLost(); throw error }
        }
        if [.awaitingReceipt, .awaitingRequestReceipt].contains(monitor.state) { monitor.matchStart() } else { monitor.poll() }
        if case .stopped(let cause) = monitor.state { throw Failure.stopped(cause) }
        if [.requestMatched, .warmingRequest, .awaitingRequestQuiet, .countdown, .awaitingFreshQuiet, .validatedRealInput].contains(monitor.state) {
            let fresh: F
            do { fresh = try readFence() }
            catch { monitor.cancel(); throw error }
            lastObservedFence = fresh
            if let fence { guard fence == fresh else { monitor.cancel(); throw Failure.interference } }
            else { fence = fresh }
            // readFence pumps the other native tap; the annotated monitor must
            // also prove that no event/HID activity was hidden in that interval.
            monitor.poll()
            if case .stopped(let cause) = monitor.state { throw Failure.stopped(cause) }
            if monitor.state == .requestMatched {
                monitor.startRequestWarmup()
                if case .stopped(let cause) = monitor.state { throw Failure.stopped(cause) }
            }
            if captureActionLayout != nil, monitor.state == .countdown, !layoutAttempted {
                try commitActionLayout()
            }
        }
    }
    private func commitActionLayout() throws {
        // No loop, retry, later quiet rebase or update after a Permit. The scan
        // occupies the existing fixed countdown; it does not start a new one.
        layoutAttempted = true
        do {
            guard !issued, !handedOff, monitor.ledger.startPolicy == .requestQuietReal,
                  let captureActionLayout, let proof = monitor.ledger.proof,
                  let request = monitor.ledger.requestBoundary, let fence,
                  monitor.state == .countdown else { throw Failure.layout("phase") }
            let began = monitor.now
            guard began >= proof.matchedAt, began < proof.deadline else { throw Failure.layout("countdownBoundary") }
            let action = try captureActionLayout()
            try action.validateStructure()
            let differences = Self.changedLayoutIntent(preparedPlan, action)
            if !differences.isEmpty {
                recordBindingRejection(.layoutCommit, fields: differences.map { ("layout." + $0, false) })
                throw Failure.layout("intentChanged")
            }
            let now = monitor.now, first = action.first, last = action.original
            guard first.sequence > preparedPlan.original.sequence,
                  first.uptimeMilliseconds > preparedPlan.original.uptimeMilliseconds,
                  first.uptimeMilliseconds >= began / 1_000_000,
                  now >= began, now <= expires, now < proof.deadline,
                  last.uptimeMilliseconds <= now / 1_000_000,
                  now / 1_000_000 - last.uptimeMilliseconds <= 250 else { throw Failure.layout("staleOrLate") }
            // Sampling/admission pumps native run loops. Both taps and the fixed
            // HID boundary must still agree after this work, before committing.
            let fresh = try readFence(); lastObservedFence = fresh
            guard fresh == fence else { throw Failure.interference }
            monitor.poll()
            if case .stopped(let cause) = monitor.state { throw Failure.stopped(cause) }
            guard monitor.state == .countdown, !issued, monitor.now <= expires,
                  monitor.now < proof.deadline,
                  last.uptimeMilliseconds <= monitor.now / 1_000_000,
                  monitor.now / 1_000_000 - last.uptimeMilliseconds <= 250,
                  monitor.ledger.requestBoundary == request,
                  monitor.ledger.proof?.matchedAt == proof.matchedAt,
                  monitor.ledger.proof?.deadline == proof.deadline else { throw Failure.layout("phaseChanged") }
            let commit = LayoutCommit(prepared: preparedPlan, action: action, request: request,
                beganAt: began, committedAt: monitor.now, countdownStartedAt: proof.matchedAt,
                countdownDeadline: proof.deadline, sourceFence: fresh)
            try evidence?.append("real-local-layout-commit", commit)
            layoutCommit = commit
        } catch {
            layoutFailure = String(describing: error)
            recordBindingRejection(.layoutCommit, fields: [("layout.captureOrContinuity", false)])
            throw error
        }
    }
    func permit() throws -> Permit {
        guard !issued else { throw Failure.used }
        try check(plan); issued = true
        try evidence?.append("real-local-input", monitor.evidence())
        return Permit(self)
    }
    private func check(_ current: M.Plan) throws {
        guard !handedOff else { throw Failure.used }
        guard !polling else { throw Failure.state }
        try poll()
        guard !(nativeRequired && authority == .nativeRealWorker) || layoutCommit != nil else { throw Failure.layout("notCommitted") }
        guard captureActionLayout == nil || layoutCommit != nil else { throw Failure.layout("notCommitted") }
        guard monitor.ledger.purpose == .realStart, monitor.state == .validatedRealInput,
              let proof = monitor.ledger.proof, monitor.ledger.finalSampleSequence != nil,
              proof.session == binding.nonce, proof.pid == binding.controllerPID,
              current.original.owner.nonce == binding.nonce, current.original.owner.target.pid == binding.targetPID,
              current.original.sameFacts(as: plan.original), fence != nil else {
            let proof = monitor.ledger.proof
            let differences = Self.changedPlanFacts(current.original, plan.original)
            recordBindingRejection(.inputPlan, fields: [
                ("purpose", monitor.ledger.purpose == .realStart), ("inputState", monitor.state == .validatedRealInput),
                ("proof", proof != nil), ("finalSampleSequence", monitor.ledger.finalSampleSequence != nil),
                ("proofSession", proof?.session == binding.nonce), ("proofPID", proof?.pid == binding.controllerPID),
                ("ownerNonce", current.original.owner.nonce == binding.nonce),
                ("targetPID", current.original.owner.target.pid == binding.targetPID), ("sourceFence", fence != nil)
            ] + differences.map { ("plan." + $0, false) })
            throw Failure.binding
        }
        if nativeRequired { guard monitor.diagnostics().native else { throw Failure.nonNative } }
        if monitor.ledger.startPolicy.usesRequestQuiet {
            guard monitor.ledger.requestReceiptHistoryValid,
                  !nativeRequired || monitor.ledger.requestHistorySupportsNativeAuthority else {
                recordBindingRejection(.requestProof, fields: [
                    ("receiptHistory", monitor.ledger.requestReceiptHistoryValid),
                    ("activityTimesComplete", !nativeRequired || monitor.ledger.requestHistorySupportsNativeAuthority)])
                throw Failure.binding
            }
            guard let request = monitor.ledger.requestBoundary, proof.requestBoundary == request,
                  let started = request.warmupStartedAt, let quietEnd = request.quietDeadline,
                  quietEnd >= started, quietEnd - started == 250_000_000,
                  proof.matchedAt >= quietEnd, proof.deadline >= proof.matchedAt,
                  proof.deadline - proof.matchedAt == 3_000_000_000,
                  request.guardSequence == proof.anchorSequence, request.packet == proof.packet,
                  request.hidCounter == proof.hidCounter, request.hidActivityUpperBound == proof.hidActivityUpperBound,
                  monitor.ledger.matchedStartCount == 1, monitor.ledger.validationCount == 1 else {
                let request = monitor.ledger.requestBoundary
                recordBindingRejection(.requestProof, fields: [
                    ("requestBoundary", request != nil), ("proofRequestBoundary", proof.requestBoundary == request),
                    ("warmupStartedAt", request?.warmupStartedAt != nil), ("quietDeadline", request?.quietDeadline != nil),
                    ("quietDuration", request?.warmupStartedAt.flatMap { start in request?.quietDeadline.map { end in end >= start && end - start == 250_000_000 } } == true),
                    ("countdownDuration", proof.deadline >= proof.matchedAt && proof.deadline - proof.matchedAt == 3_000_000_000),
                    ("countdownAfterQuiet", request?.quietDeadline.map { proof.matchedAt >= $0 } == true),
                    ("guardSequence", request?.guardSequence == proof.anchorSequence), ("packet", request?.packet == proof.packet),
                    ("hidCounter", request?.hidCounter == proof.hidCounter), ("hidActivityUpperBound", request?.hidActivityUpperBound == proof.hidActivityUpperBound),
                    ("matchedStartCount", monitor.ledger.matchedStartCount == 1), ("validationCount", monitor.ledger.validationCount == 1)])
                throw Failure.binding
            }
        }
    }
}
