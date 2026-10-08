// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

/// Injected observations only: no native window, input read, tap or post.
final class MenuBarActionLayoutCommitTests: XCTestCase {
    typealias A = MenuBarRealLocalAuthorization
    typealias M = MenuBarHiddenMoveModel
    typealias H = MenuBarRequestWarmupTests.Harness
    func shifted(_ f: MenuBarHiddenMoveFixture, by x: Double = 12) -> [M.Item] {
        f.original.items.map { old in .init(identity: old.identity, frame: old.frame.offsetBy(dx: x, dy: 0),
            listedOnScreen: old.listedOnScreen, onScreen: old.onScreen, alpha: old.alpha,
            spaces: old.spaces, ownerOcclusionVisible: old.ownerOcclusionVisible) }
    }
    func fresh(_ h: H, items: [M.Item]? = nil, scope: M.Scope? = nil, owner: M.Owner? = nil,
               membership: [UInt32]? = nil) throws -> M.Plan {
        let t = h.time / 1_000_000
        h.time += 200_000_000
        return try .capture(h.fixture.sample(10, t, items: items, scope: scope, owner: owner, membership: membership),
            h.fixture.sample(11, t + 150, items: items, scope: scope, owner: owner, membership: membership), now: h.time / 1_000_000)
    }
    func testGeometryCommitsOnceInsideOriginalCountdownAndCannotUpgradeIsolatedPermit() throws {
        for appKitFirst in [true, false] {
            let h = try H(startPolicy: .requestQuietReal, capturesLayout: true)
            let initial = h.broker.plan; var calls = 0
            h.layoutHook = { calls += 1; XCTAssertEqual(h.broker.monitor.state, .countdown)
                return try self.fresh(h, items: self.shifted(h.fixture)) }
            try h.request(appKitFirst: appKitFirst)
            let request = try XCTUnwrap(h.broker.monitor.ledger.requestBoundary)
            XCTAssertEqual(calls, 0); XCTAssertEqual(h.broker.plan, initial); XCTAssertNil(h.broker.layoutCommit)
            try h.quietWindow()
            let commit = try XCTUnwrap(h.broker.layoutCommit)
            XCTAssertEqual(calls, 1); XCTAssertEqual(commit.prepared, initial)
            XCTAssertEqual(commit.action, h.broker.plan); XCTAssertFalse(initial.original.sameFacts(as: commit.action.original))
            XCTAssertEqual(commit.request, request)
            XCTAssertEqual(commit.countdownDeadline - commit.countdownStartedAt, 3_000_000_000)
            XCTAssertEqual(request.quietDeadline! - request.warmupStartedAt!, 250_000_000)
            XCTAssertGreaterThanOrEqual(commit.beganAt, commit.countdownStartedAt)
            XCTAssertLessThan(commit.committedAt, commit.countdownDeadline)
            XCTAssertEqual(h.broker.monitor.ledger.validationCount, 0)
            try h.countdown(); XCTAssertEqual(calls, 1)
            XCTAssertEqual(h.broker.monitor.ledger.proof?.deadline, commit.countdownDeadline)
            let permit = try h.broker.permit(); try permit.check(commit.action)
            XCTAssertEqual(permit.authority, .isolated)
            XCTAssertThrowsError(try permit.checkForRealAction(binding: h.broker.binding))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("layout-isolated-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            XCTAssertThrowsError(try MenuBarRealActionConsumption.consumeAuthorized(round: root.appendingPathComponent("round"),
                session: root, binding: h.broker.binding, permit: permit))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            XCTAssertFalse(permit.consumed)
            try h.broker.recordTerminal(nil)
            let decoded = try JSONDecoder().decode(A.Terminal.self, from: JSONEncoder().encode(h.broker.terminalEvidence))
            XCTAssertEqual(decoded.layoutCommit?.action, commit.action); XCTAssertNil(decoded.layoutFailure)
        }
    }
    func testAnyGeometryDriftAfterCommitIsStillExactBindingFailure() throws {
        let h = try H(startPolicy: .requestQuietReal, capturesLayout: true)
        h.layoutHook = { try self.fresh(h, items: self.shifted(h.fixture)) }
        try h.request(); try h.quietWindow(); try h.countdown()
        let locked = h.broker.plan, permit = try h.broker.permit()
        let later = try fresh(h, items: shifted(h.fixture, by: 12.0001))
        XCTAssertThrowsError(try permit.check(later))
        XCTAssertEqual(h.broker.bindingRejection, .init(check: .inputPlan, failedFields: ["plan.items"]))
        XCTAssertEqual(h.broker.plan, locked); XCTAssertFalse(permit.consumed)
    }
    func testIntentChangesPermanentlyRefuseWithoutRetryOrPermit() throws {
        for kind in ["scope", "instance", "nonce", "neighbor", "visibility", "membership", "ownedWidth"] {
            let h = try H(startPolicy: .requestQuietReal, capturesLayout: true); var calls = 0
            h.layoutHook = {
                calls += 1; var items = self.shifted(h.fixture)
                if kind == "neighbor" { items[2] = h.fixture.item(2, frame: items[2].frame, identity: h.fixture.original.items[0].identity)
                    // Also change the left identity so inventory remains valid.
                    items[0] = h.fixture.item(0, frame: items[0].frame, identity: h.fixture.original.items[2].identity) }
                if kind == "visibility" { items[0] = h.fixture.item(0, frame: items[0].frame, listed: true, onScreen: .ordered) }
                if kind == "ownedWidth" { var frame = items[1].frame; frame.size.width = 28
                    items[1] = h.fixture.item(1, frame: frame) }
                return try self.fresh(h, items: items, scope: kind == "scope" ? h.fixture.scope(scale: 3) : nil,
                    owner: kind == "instance" ? h.fixture.owner(instance: UUID()) : (kind == "nonce" ? h.fixture.owner(nonce: UUID()) : nil),
                    membership: kind == "membership" ? [2, 1, 3] : nil)
            }
            try h.request(); XCTAssertThrowsError(try h.quietWindow(), kind)
            XCTAssertNil(h.broker.layoutCommit); XCTAssertNotNil(h.broker.layoutFailure)
            XCTAssertEqual(h.broker.bindingRejection?.check, .layoutCommit)
            h.layoutHook = { calls += 1; return try self.fresh(h) }
            XCTAssertThrowsError(try h.broker.poll()); XCTAssertThrowsError(try h.broker.permit())
            XCTAssertEqual(calls, 1); XCTAssertEqual(h.broker.plan, try h.fixture.plan())
            try h.broker.recordTerminal(A.Failure.binding)
            XCTAssertFalse(try XCTUnwrap(h.broker.terminalEvidence).permitIssued)
        }
    }
    func testInputAndSourceLossDuringScanCannotBecomeLayoutCommit() throws {
        for kind in ["counter", "age", "tap", "held", "health", "fence", "fenceLoss", "gap", "cancel"] {
            let h = try H(startPolicy: .requestQuietReal, capturesLayout: true); var calls = 0
            h.layoutHook = {
                calls += 1; let p = try self.fresh(h)
                switch kind {
                case "counter": h.count += 1
                case "age": h.hid = h.time
                case "tap": h.broker.monitor.receive(.mouseMoved, event: h.event())
                case "held": h.buttons = 1
                case "health": h.healthy = false
                case "fence": h.eventCount += 1
                case "fenceLoss": h.fenceHealthy = false
                case "gap": h.time += 400_000_000
                default: h.broker.cancel()
                }
                return p
            }
            try h.request(); XCTAssertThrowsError(try h.quietWindow(), kind)
            let first = h.broker.layoutFailure
            h.healthy = true; h.fenceHealthy = true; h.buttons = 0
            XCTAssertThrowsError(try h.broker.poll()); XCTAssertThrowsError(try h.broker.permit())
            XCTAssertEqual(h.broker.layoutFailure, first); XCTAssertEqual(calls, 1); XCTAssertNil(h.broker.layoutCommit)
            let proof = try XCTUnwrap(h.broker.monitor.ledger.proof)
            XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
        }
    }
    func testOldPairUnstablePairProviderFailureAndLateScanStayUncommitted() throws {
        for kind in ["old", "unstable", "provider", "late"] {
            let h = try H(startPolicy: .requestQuietReal, capturesLayout: true); var calls = 0
            h.layoutHook = {
                calls += 1
                if kind == "provider" { throw A.Failure.layout("testProviderFailure") }
                if kind == "old" { return try h.fixture.plan() }
                if kind == "unstable" {
                    let t = h.time / 1_000_000
                    return M.Plan(first: h.fixture.sample(10, t), original: h.fixture.sample(11, t + 150, items: self.shifted(h.fixture)),
                        anchor: try h.fixture.plan().anchor)
                }
                let p = try self.fresh(h); h.time += 3_000_000_000; return p
            }
            try h.request(); XCTAssertThrowsError(try h.quietWindow(), kind)
            XCTAssertNil(h.broker.layoutCommit); XCTAssertThrowsError(try h.broker.poll())
            XCTAssertThrowsError(try h.broker.permit()); XCTAssertEqual(calls, 1)
        }
    }
    func testFenceReadCannotCommitAPlanThatBecameStaleWhileInputStayedQuiet() throws {
        let h = try H(startPolicy: .requestQuietReal, capturesLayout: true)
        h.layoutHook = {
            let p = try self.fresh(h)
            h.fenceHook = { h.time += 250_000_000; h.fenceHook = nil }
            return p
        }
        try h.request(); XCTAssertThrowsError(try h.quietWindow())
        XCTAssertFalse(h.broker.monitor.ledger.stopped) // 450ms gap is within the unchanged input limit.
        XCTAssertNil(h.broker.layoutCommit); XCTAssertNotNil(h.broker.layoutFailure)
        XCTAssertThrowsError(try h.broker.permit())
    }
    func testDiagnosticPolicyCannotUseRealLayoutCommitPhase() throws {
        let h = try H(capturesLayout: true); var calls = 0
        h.layoutHook = { calls += 1; return try self.fresh(h) }
        try h.request(); XCTAssertThrowsError(try h.quietWindow())
        XCTAssertEqual(calls, 0); XCTAssertNil(h.broker.layoutCommit); XCTAssertThrowsError(try h.broker.permit())
    }
    func testRecordedTwelvePixelShiftChangesGeometryButPreservesIntentAndOldRejection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("docs/evidence/menu-bar-post-notice-real-live-2026-10-07")
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: dir.appendingPathComponent("session-sha256.json")))
        struct Envelope: Decodable { let payload: Data }
        struct Pair: Decodable { let first, second: M.Snapshot }
        func payload(_ name: String) throws -> Data {
            let bytes = try Data(contentsOf: dir.appendingPathComponent("session/" + name))
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), hashes[name])
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            return envelope.payload
        }
        let decoder = JSONDecoder()
        let pair = try decoder.decode(Pair.self, from: payload("stages/0003-observation-pair.json"))
        let old = try M.Plan.capture(pair.first, pair.second, now: pair.second.uptimeMilliseconds)
        let newer = try decoder.decode(M.Plan.self, from: payload("stages/0009-original-plan.json"))
        XCTAssertTrue(A.changedLayoutIntent(old, newer).isEmpty)
        XCTAssertFalse(old.original.sameFacts(as: newer.original))
        XCTAssertEqual(A.changedPlanFacts(old.original, newer.original), ["items"])
        // This is comparison of stored observations, never a native commit or
        // retrofit to the old round (whose correct binding rejection remains).
    }
    func testLayoutFailureNoticeShowsActualReasonWithoutClaimingMovement() {
        let text = MenuBarAcceptanceStopNotice.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false,
            operationFailure: "layout(staleOrLate)", bindingRejection: .init(check: .layoutCommit, failedFields: ["layout.captureOrContinuity"]))
        XCTAssertTrue(text.contains("许可前")); XCTAssertTrue(text.contains("staleOrLate"))
        XCTAssertTrue(text.contains("未发送鼠标事件"))
    }
    #if OWNED_LIVE_CONTROLLER
    func testNativeRealConstructorRequiresLayoutProviderBeforeOpeningInput() throws {
        let h = try H(), input = MenuBarListenOnlyInterferenceSource()
        XCTAssertThrowsError(try A(binding: h.broker.binding, plan: h.fixture.plan(), input: input,
            expires: .max, evidence: nil)) { XCTAssertEqual(String(describing: $0), "layout(\"providerUnavailable\")") }
        XCTAssertFalse(input.diagnostics().monitoringHealthy)
    }
    #endif
}
