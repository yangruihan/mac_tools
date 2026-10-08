// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

final class MenuBarAcceptanceStopNoticeTests: XCTestCase {
    typealias N = MenuBarAcceptanceStopNotice
    func testReadingRequiresSavedReceiptAndBothInputsStopped() {
        for receipt in [false, true] { for stopped in [false, true] {
            var n = N()
            XCTAssertEqual(n.begin(at: 1, receiptWritten: receipt, inputsStopped: stopped), receipt && stopped)
            XCTAssertEqual(n.state, receipt && stopped ? .showing : .closed)
            if !receipt || !stopped {
                XCTAssertNil(n.deadline)
                XCTAssertFalse(n.begin(at: 2, receiptWritten: true, inputsStopped: true))
            }
        } }
    }
    func testReadingHasFixedExpiryAndCannotRestartAfterClose() {
        var n = N()
        XCTAssertTrue(n.begin(at: 1_000, receiptWritten: true, inputsStopped: true))
        let end = 1_000 + N.readDuration
        XCTAssertEqual(n.deadline, end)
        XCTAssertFalse(n.begin(at: 2_000, receiptWritten: true, inputsStopped: true))
        XCTAssertEqual(n.deadline, end)
        XCTAssertFalse(n.expire(at: end - 1)); XCTAssertTrue(n.expire(at: end))
        XCTAssertEqual(n.state, .closed)
        XCTAssertFalse(n.begin(at: end, receiptWritten: true, inputsStopped: true))
    }
    func testNoticeCannotExtendWorkerDeadlineOrSurviveInvalidClock() {
        var n = N()
        XCTAssertTrue(n.begin(at: 1_000, receiptWritten: true, inputsStopped: true, notAfter: 2_000))
        XCTAssertEqual(n.deadline, 2_000); XCTAssertTrue(n.expire(at: 2_000))
        for invalid in [UInt64.max, UInt64.max - N.readDuration + 1] {
            var n = N(); XCTAssertFalse(n.begin(at: invalid, receiptWritten: true, inputsStopped: true))
            XCTAssertEqual(n.state, .closed)
        }
        n = N(); XCTAssertTrue(n.begin(at: 100, receiptWritten: true, inputsStopped: true))
        XCTAssertTrue(n.expire(at: 99)); XCTAssertEqual(n.state, .closed)
        n = N(); XCTAssertFalse(n.begin(at: 100, receiptWritten: true, inputsStopped: true, notAfter: 100))
    }
    func testLaterInputMessagePreservesUnknownAttributionAndZeroEmission() {
        let message = N.message(cause: .laterInput, cancelled: false, expired: false,
            fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false)
        XCTAssertTrue(message.contains("保护停止")); XCTAssertTrue(message.contains("来源尚未确定"))
        XCTAssertTrue(message.contains("未发送鼠标事件")); XCTAssertTrue(message.contains("没有待恢复责任"))
        XCTAssertFalse(message.contains("用户")); XCTAssertFalse(message.contains("崩溃"))
    }
    func testUnknownEmissionRecoveryAndContradictorySuccessNeverClaimFullReturn() {
        for count in [nil, Optional(-1)] {
            let message = N.message(cause: nil, cancelled: false, expired: false,
                fullCyclePassed: true, sessionPosts: count, pidPosts: 0, pendingRecovery: nil)
            XCTAssertTrue(message.contains("发送状态未能确认")); XCTAssertTrue(message.contains("恢复状态未能确认"))
            XCTAssertFalse(message.contains("已完成移动")); XCTAssertFalse(message.contains("未发送鼠标事件"))
        }
        let pending = N.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: true, sessionPosts: 4, pidPosts: 0, pendingRecovery: true)
        XCTAssertTrue(pending.contains("恢复责任仍保留")); XCTAssertFalse(pending.contains("已完成移动"))
        let zero = N.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: true, sessionPosts: 0, pidPosts: 0, pendingRecovery: false)
        XCTAssertFalse(zero.contains("已完成移动"))
        XCTAssertTrue(N.message(cause: nil, cancelled: false, expired: false,
            fullCyclePassed: true, sessionPosts: 10, pidPosts: 0, pendingRecovery: false).contains("已完成移动"))
    }
    func testCancelExpiryAndMonitorLossHaveReadableReasons() {
        for (cause, cancel, expiry, expected) in [(Optional<MenuBarLocalContinuityLedger.Cause>.none, true, false, "已取消"),
            (nil, false, true, "已超时"), (.monitorLost, false, false, "监听失效"),
            (.hidActivityUnproven, false, false, "时间范围"), (.overflow, false, false, "安全容量")] {
            XCTAssertTrue(N.message(cause: cause, cancelled: cancel, expired: expiry,
                fullCyclePassed: false, sessionPosts: 0, pidPosts: 0, pendingRecovery: false).contains(expected))
        }
    }
    func testRecordedHardwareRoundStillRefusesCounterChangeInBothCallbackOrders() throws {
        struct Result: Decodable { let localStartTerminal: MenuBarRealLocalAuthorization.Terminal }
        typealias L = MenuBarLocalContinuityLedger
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("docs/evidence/menu-bar-hid-queue-repaired-live-2026-10-07")
        let data = try Data(contentsOf: dir.appendingPathComponent("session/result.json"))
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: dir.appendingPathComponent("session-sha256.json")))
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hashes["result.json"])
        let t = try JSONDecoder().decode(Result.self, from: data).localStartTerminal
        let request = try XCTUnwrap(t.input.requestBoundary), proof = try XCTUnwrap(t.input.proof)
        let anchor = try XCTUnwrap(t.input.nodes.first), offset = anchor.sequence - 1
        for first in [true, false] {
            var l = L(session: t.binding.nonce, pid: t.binding.controllerPID, purpose: .realStart, startPolicy: .requestQuietReal)
            l.configure(window: proof.window); var warmed = false
            for node in t.input.nodes {
                if !warmed, let start = request.warmupStartedAt, (node.sample?.began ?? node.observedAt) >= start {
                    l.startRequestWarmup(at: start); warmed = true
                }
                if first, node.sequence == request.upSequence { l.begin(request.packet, at: request.packet.timestamp) }
                switch node.kind {
                case .sample: l.sampled(try XCTUnwrap(node.sample))
                case .ownUp: l.event(ownPacket: node.packet, at: node.observedAt)
                case .activity: l.event(ownPacket: nil, at: node.observedAt)
                case .loss: l.lost(at: node.observedAt)
                }
                if !first, node.sequence == request.guardSequence { l.begin(request.packet, at: node.observedAt) }
                if node.sequence == request.matchSequence { l.claim(at: request.matchedAt) }
                if node.sequence == proof.matchSequence {
                    l.completeRequestQuiet(firstNewSequence: node.sequence - offset - 1, at: proof.matchedAt)
                    XCTAssertEqual(l.state, .countdown)
                }
            }
            XCTAssertEqual(l.state, .stopped(.laterInput)); XCTAssertEqual(l.matchedStartCount, 1)
            XCTAssertEqual(l.validationCount, 0); XCTAssertNil(l.finalSampleSequence)
            XCTAssertEqual(l.requestBoundary?.hidCounter, 29803933)
            let bad = try XCTUnwrap(l.lastSample)
            XCTAssertEqual(bad.counterBefore, 29803935); XCTAssertEqual(bad.counterAfter, 29803935)
            XCTAssertEqual(bad.ageReadEnded! - bad.ageReadBegan!, 583)
            XCTAssertEqual(l.firstFailure?.previousState, "countdown")
        }
    }
}
