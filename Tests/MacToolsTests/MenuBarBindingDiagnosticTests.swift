// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

final class MenuBarBindingDiagnosticTests: XCTestCase {
    typealias A = MenuBarRealLocalAuthorization
    typealias M = MenuBarHiddenMoveModel
    func testChangedFactsDistinguishLayoutEnvironmentIdentityAndIgnoreSampleClock() {
        let f = MenuBarHiddenMoveFixture(), a = f.sample(1, 1000)
        XCTAssertTrue(A.changedPlanFacts(a, f.sample(2, 1200)).isEmpty)
        XCTAssertEqual(A.changedPlanFacts(a, f.sample(2, 1200, scope: f.scope(scale: 3))), ["scope"])
        XCTAssertEqual(A.changedPlanFacts(a, f.sample(2, 1200, owner: f.owner(instance: UUID()))), ["owner"])
        var items = f.original.items; items[1] = f.item(1, frame: items[1].frame.offsetBy(dx: 12, dy: 0))
        XCTAssertEqual(A.changedPlanFacts(a, f.sample(2, 1200, items: items)), ["items"])
        XCTAssertEqual(A.changedPlanFacts(a, f.sample(2, 1200, membership: [2, 1, 3])), ["membershipIDs"])
        XCTAssertEqual(A.changedPlanFacts(a, f.sample(2, 1200, evidence: .unknown)), ["orderEvidence"])
    }
    func testPostValidationLayoutRejectionRetainsFirstDiagnosticWithoutRebinding() throws {
        let h = try MenuBarRealLocalAuthorizationTests.Harness(); try h.start(); try h.finish()
        let permit = try h.broker.permit(), original = h.broker.plan
        let items = h.fixture.original.items.map { item in M.Item(identity: item.identity,
            frame: item.frame.offsetBy(dx: 12, dy: 0), listedOnScreen: item.listedOnScreen,
            onScreen: item.onScreen, alpha: item.alpha, spaces: item.spaces,
            ownerOcclusionVisible: item.ownerOcclusionVisible) }
        let changed = try M.Plan.capture(h.fixture.sample(10, 2000, items: items),
            h.fixture.sample(11, 2100, items: items), now: 2100)
        XCTAssertThrowsError(try permit.check(changed))
        XCTAssertEqual(h.broker.bindingRejection, .init(check: .inputPlan, failedFields: ["plan.items"]))
        XCTAssertEqual(h.broker.plan, original); XCTAssertFalse(permit.consumed)
        XCTAssertEqual(h.broker.monitor.ledger.validationCount, 1)
        let environment = try M.Plan.capture(h.fixture.sample(12, 2200, scope: h.fixture.scope(scale: 3)),
            h.fixture.sample(13, 2300, scope: h.fixture.scope(scale: 3)), now: 2300)
        XCTAssertThrowsError(try permit.check(environment))
        XCTAssertEqual(h.broker.bindingRejection?.failedFields, ["plan.items"]) // First failure remains authoritative.
        try h.broker.recordTerminal(A.Failure.binding)
        let t = try XCTUnwrap(h.broker.terminalEvidence)
        XCTAssertEqual(t.bindingRejection, h.broker.bindingRejection)
        let decoded = try JSONDecoder().decode(A.Terminal.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(decoded.bindingRejection, t.bindingRejection)
        XCTAssertFalse(decoded.handedOff); XCTAssertEqual(decoded.validationCount, 1)
    }
    func testLegacyBindingReasonAndNewSpecificReasonDoNotClaimHIDActivity() {
        let legacy = MenuBarAcceptanceStopNotice.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false, operationFailure: "binding")
        XCTAssertTrue(legacy.contains("绑定检查未通过")); XCTAssertTrue(legacy.contains("未细分字段"))
        XCTAssertFalse(legacy.contains("新输入活动"))
        let layout = MenuBarAcceptanceStopNotice.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false,
            operationFailure: "binding", bindingRejection: .init(check: .inputPlan, failedFields: ["plan.items"]))
        XCTAssertTrue(layout.contains("位置或可见状态已变化")); XCTAssertTrue(layout.contains("未发送鼠标事件"))
        XCTAssertFalse(layout.contains("新输入活动")); XCTAssertFalse(layout.contains("用户"))
        for (check, expected) in [(A.BindingRejection.Check.processIdentity, "进程或签名身份"), (.requestProof, "请求记录")] {
            XCTAssertTrue(MenuBarAcceptanceStopNotice.message(cause: nil, cancelled: false, expired: false,
                fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false,
                operationFailure: "binding", bindingRejection: .init(check: check, failedFields: ["test"])).contains(expected))
        }
    }
    func testOtherFailureRemainsVisibleRatherThanGenericStop() {
        let message = MenuBarAcceptanceStopNotice.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: false, sessionPosts: nil, pidPosts: nil, pendingRecovery: nil,
            operationFailure: "targetHitUnavailable")
        XCTAssertTrue(message.contains("targetHitUnavailable")); XCTAssertTrue(message.contains("发送状态未能确认"))
    }
    func testRealRecordedLayoutMismatchIsItemsOnlyAndOldTerminalHasNoInventedDetail() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("docs/evidence/menu-bar-post-notice-real-live-2026-10-07")
        let manifest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: dir.appendingPathComponent("session-sha256.json")))
        struct Envelope: Decodable { let payload: Data }
        struct Pair: Decodable { let first, second: M.Snapshot }
        func data(_ name: String) throws -> Data {
            let data = try Data(contentsOf: dir.appendingPathComponent("session/" + name))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), manifest[name]); return data
        }
        let decoder = JSONDecoder()
        let old = try decoder.decode(Pair.self, from: decoder.decode(Envelope.self,
            from: data("stages/0003-observation-pair.json")).payload).second
        let new = try decoder.decode(M.Plan.self, from: decoder.decode(Envelope.self,
            from: data("stages/0009-original-plan.json")).payload).original
        XCTAssertEqual(A.changedPlanFacts(old, new), ["items"]); XCTAssertFalse(old.sameFacts(as: new))
        XCTAssertEqual(new.items[2].frame.minX - old.items[2].frame.minX, 12)
        struct Result: Decodable { let localStartTerminal: A.Terminal }
        let terminal = try decoder.decode(Result.self, from: data("result.json")).localStartTerminal
        XCTAssertEqual(terminal.validationCount, 1); XCTAssertTrue(terminal.permitIssued); XCTAssertFalse(terminal.handedOff)
        XCTAssertNil(terminal.stoppedCause); XCTAssertNil(terminal.bindingRejection)
        XCTAssertEqual(terminal.failure, "binding") // Legacy detail is absent, never retroactively filled.
    }
}
