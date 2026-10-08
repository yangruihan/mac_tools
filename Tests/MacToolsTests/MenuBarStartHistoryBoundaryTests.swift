// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

/// Offline ledger/recorded-trace tests only. No window, tap, permission or post.
final class MenuBarStartHistoryBoundaryTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    let up: UInt64 = 40_000_000_000
    let policies: [L.StartPolicy] = [.preUpContinuity, .requestQuietReal, .requestQuietDiagnostic]
    func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    func packet(_ timestamp: UInt64) -> L.R.Packet {
        .init(MenuBarLocalNativeContinuityTests.Harness(configure: false).event(timestamp: timestamp))
    }
    func sample(_ at: UInt64, count: UInt32 = 100, activity: UInt64? = nil) -> L.Sample {
        .init(began: at, ended: at + 1_000, counterBefore: count, counterAfter: count,
            age: activity.map { Double(at - $0) / 1_000_000_000 } ?? 1,
            buttons: 0, modifiers: 0, healthyBefore: true, healthyAfter: true)
    }
    func waiting(_ policy: L.StartPolicy) -> L {
        var l = L(session: UUID(), pid: 123, purpose: .realStart, startPolicy: policy)
        l.configure(window: 7)
        for i in 0..<800 {
            let t = 1_000_000_000 + UInt64(i) * 48_000_000
            if i.isMultiple(of: 2) { l.event(ownPacket: nil, at: t) }
            l.sampled(sample(t + 1_000))
        }
        XCTAssertEqual(l.state, .ready); XCTAssertEqual(l.nodes.count, 512)
        return l
    }
    func start(_ l: inout L, appKitFirst: Bool) throws {
        l.sampled(sample(up - 100_000_000))
        l.event(ownPacket: nil, at: up - 50_000_000)
        l.sampled(sample(up - 49_000_000))
        let p = packet(up)
        if appKitFirst { l.begin(p, at: up) }
        l.event(ownPacket: p, at: up + 1_000_000)
        let count: UInt32 = l.startPolicy.usesRequestQuiet ? 101 : 100
        let activity = l.startPolicy.usesRequestQuiet ? up : up - 1_000_000_000
        l.sampled(sample(up + 2_000_000, count: count, activity: activity))
        if !appKitFirst { l.begin(p, at: up + 3_000_000) }
        l.sampled(sample(up + 4_000_000, count: count, activity: activity))
        l.claim(at: up + 4_001_000)
        XCTAssertEqual(l.matchedStartCount, 1)
    }
    func finish(_ l: inout L) throws {
        var t = up + 5_000_000
        let count: UInt32 = l.startPolicy.usesRequestQuiet ? 101 : 100
        let activity = l.startPolicy.usesRequestQuiet ? up : up - 1_000_000_000
        if l.startPolicy.usesRequestQuiet {
            l.startRequestWarmup(at: t)
            for _ in 0..<3 { t += 100_000_000; l.sampled(sample(t, count: count, activity: activity)) }
            XCTAssertEqual(l.state, .awaitingRequestQuiet)
            let first = l.lastSequence + 1
            t += 10_000; l.sampled(sample(t, count: count, activity: activity))
            t += 10_000; l.sampled(sample(t, count: count, activity: activity))
            l.completeRequestQuiet(firstNewSequence: first, at: t + 1_000)
            let request = try XCTUnwrap(l.requestBoundary)
            XCTAssertEqual(request.quietDeadline! - request.warmupStartedAt!, 250_000_000)
        }
        let proof = try XCTUnwrap(l.proof)
        XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
        XCTAssertEqual(l.validationCount, 0)
        while t < proof.deadline { t += 100_000_000; l.sampled(sample(t, count: count, activity: activity)) }
        XCTAssertEqual(l.state, .awaitingFreshQuiet)
        let first = l.lastSequence + 1
        t += 10_000; l.sampled(sample(t, count: count, activity: activity))
        t += 10_000; l.sampled(sample(t, count: count, activity: activity))
        l.complete(firstNewSequence: first, at: t + 1_000)
        XCTAssertEqual(l.state, .validatedRealInput); XCTAssertEqual(l.validationCount, 1)
    }
    func testLongWaitThenStartPreservesSequenceCountersAndFullProofInBothOrders() throws {
        for policy in policies { for first in [false, true] {
            var l = waiting(policy)
            let continuity = l.continuity, beforeSequence = l.lastSequence, beforeTapCount = l.tapCount
            try start(&l, appKitFirst: first)
            let boundary = try XCTUnwrap(l.startHistoryBoundary)
            XCTAssertGreaterThan(boundary.retiredNodeCount, 0)
            XCTAssertEqual(boundary.earliestRequiredAt, up - 250_000_000)
            XCTAssertEqual(l.continuity, continuity)
            XCTAssertGreaterThan(l.lastSequence, beforeSequence)
            XCTAssertEqual(l.tapCount, beforeTapCount + 2)
            XCTAssertEqual(l.nodes.first?.sample?.counterAfter, 100)
            if policy.usesRequestQuiet { XCTAssertEqual(l.requestBoundary?.hidCounter, 101) }
            try finish(&l)
            XCTAssertEqual(l.startHistoryBoundary, boundary)
            for (a, b) in zip(l.nodes, l.nodes.dropFirst()) { XCTAssertEqual(b.sequence, a.sequence + 1) }
        } }
    }
    func testExactCutoffAndAllLaterObservationsSurviveBeginUnchanged() throws {
        var l = waiting(.requestQuietReal)
        l.sampled(sample(up - 250_000_001))
        l.sampled(sample(up - 250_000_000))
        l.event(ownPacket: nil, at: up - 200_000_000)
        l.sampled(sample(up - 100_000_000))
        let retained = l.nodes.filter { $0.observedAt >= up - 250_000_000 }
        let counter = l.tapCount, epoch = l.epoch, sequence = l.lastSequence
        l.begin(packet(up), at: up)
        XCTAssertEqual(try encoded(l.nodes), try encoded(retained))
        XCTAssertEqual(l.tapCount, counter); XCTAssertEqual(l.epoch, epoch); XCTAssertEqual(l.lastSequence, sequence)
        XCTAssertEqual(l.startHistoryBoundary?.retainedFromSequence, retained.first?.sequence)
    }
    func testCapacityInsideRequiredIntervalStillStopsAndCannotRestart() throws {
        for policy in policies {
            var l = waiting(policy)
            for i in 0..<512 { l.sampled(sample(up - 100_000_000 + UInt64(i) * 1_000)) }
            l.begin(packet(up), at: up)
            XCTAssertEqual(l.nodes.count, 512); XCTAssertEqual(l.startHistoryBoundary?.retiredNodeCount, 0)
            l.sampled(sample(up + 1_000))
            XCTAssertEqual(l.state, .stopped(.overflow)); XCTAssertEqual(l.nodes.count, 513)
            let failure = l.firstFailure, boundary = l.startHistoryBoundary
            l.begin(packet(up), at: up + 2_000); l.claim(at: up + 2_000)
            l.sampled(sample(up + 3_000)); l.event(ownPacket: packet(up), at: up + 4_000)
            XCTAssertEqual(l.firstFailure, failure); XCTAssertEqual(l.startHistoryBoundary, boundary)
            XCTAssertNil(l.proof); XCTAssertEqual(l.validationCount, 0)
        }
    }
    func testProofPhaseCapacityCannotBeEvadedByRetiringMoreHistory() throws {
        var l = waiting(.requestQuietReal); try start(&l, appKitFirst: false)
        l.startRequestWarmup(at: up + 5_000_000)
        let boundary = l.startHistoryBoundary, request = l.requestBoundary
        for i in 0..<513 { l.sampled(sample(up + 6_000_000 + UInt64(i) * 1_000, count: 101, activity: up)) }
        XCTAssertEqual(l.state, .stopped(.overflow)); XCTAssertEqual(l.nodes.count, 513)
        XCTAssertEqual(l.startHistoryBoundary, boundary); XCTAssertEqual(l.requestBoundary, request)
        XCTAssertNil(l.proof)
    }
    func testStaleFutureOrStoppedStartCannotTrimWaitingEvidence() throws {
        for kind in ["stale", "future", "loss", "cancel"] {
            var l = waiting(.requestQuietReal)
            let before = try encoded(l.nodes)
            if kind == "loss" { l.lost(at: up - 1_000_000) }
            if kind == "cancel" { l.fail(.cancelled) }
            let actualBefore = try encoded(l.nodes)
            l.begin(packet(up), at: kind == "stale" ? up + 250_000_001 : kind == "future" ? up - 1 : up)
            XCTAssertTrue(l.stopped); XCTAssertNil(l.startHistoryBoundary)
            XCTAssertEqual(try encoded(l.nodes), actualBefore)
            if kind != "loss" { XCTAssertEqual(actualBefore, before) }
        }
    }
    func testLateOrCrossStageInputAndMissingAnchorRemainRefusals() throws {
        for first in [true, false] { for kind in ["late", "foreignBeforeBegin", "foreignAfterBegin", "duplicateUp", "missingAnchor", "clock"] {
            var l = waiting(.requestQuietReal); let p = packet(up)
            if kind != "missingAnchor" { l.sampled(sample(up - 100_000_000)) }
            if first { l.begin(p, at: up) }
            l.event(ownPacket: p, at: up + 1_000_000)
            l.sampled(sample(up + 2_000_000, count: 101, activity: up))
            if kind == "foreignBeforeBegin" { l.event(ownPacket: nil, at: up + 3_000_000) }
            if !first { l.begin(p, at: up + 4_000_000) }
            if kind == "foreignAfterBegin" { l.event(ownPacket: nil, at: up + 5_000_000) }
            if kind == "duplicateUp" { l.event(ownPacket: p, at: up + 5_000_000) }
            l.sampled(sample(kind == "clock" ? up : up + 6_000_000, count: 101, activity: up))
            l.claim(at: kind == "late" ? up + 260_000_000 : up + 6_001_000)
            XCTAssertTrue(l.stopped, "\(first)/\(kind)"); XCTAssertNil(l.requestBoundary); XCTAssertNil(l.proof)
            XCTAssertEqual(l.matchedStartCount, 0)
            let failure = l.firstFailure
            l.begin(p, at: up + 300_000_000); l.claim(at: up + 300_000_000)
            XCTAssertEqual(l.firstFailure, failure)
        } }
    }
    func testRecordedHumanOverflowPrefixNowMatchesRequestWithoutInventedQuietSuffix() throws {
        struct Result: Decodable { let localStartTerminal: MenuBarRealLocalAuthorization.Terminal }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("docs/evidence/menu-bar-real-v13-restart-live-2026-10-07/session")
        let data = try Data(contentsOf: folder.appendingPathComponent("result.json"))
        let manifest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: folder.deletingLastPathComponent().appendingPathComponent("session-sha256.json")))
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), manifest["result.json"])
        let c = try JSONDecoder().decode(Result.self, from: data).localStartTerminal
        let p = try XCTUnwrap(c.capturedStart)
        struct Ready: Decodable { let windowID: Int }
        let ready = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: folder.appendingPathComponent("local-ui-ready.json")))
        var l = L(session: c.binding.nonce, pid: c.binding.controllerPID, purpose: .realStart, startPolicy: .requestQuietReal)
        l.configure(window: ready.windowID)
        // Missing original prefix is not fabricated: replay only retained nodes.
        // Relative sequence/tap/epoch values differ; immutable raw samples do not.
        for node in c.input.nodes {
            if node.sequence == 866 {
                XCTAssertEqual(l.nodes.count, 512)
                l.begin(p, at: try XCTUnwrap(node.sample).began)
            }
            switch node.kind {
            case .sample: l.sampled(try XCTUnwrap(node.sample))
            case .ownUp: l.event(ownPacket: try XCTUnwrap(node.packet), at: node.observedAt)
            case .activity: l.event(ownPacket: nil, at: node.observedAt)
            case .loss: l.lost(at: node.observedAt)
            }
        }
        l.claim(at: try XCTUnwrap(c.input.nodes.last).observedAt)
        XCTAssertEqual(l.state, .requestMatched); XCTAssertEqual(l.matchedStartCount, 1)
        XCTAssertEqual(l.requestBoundary?.hidCounter, 29537339)
        XCTAssertNil(l.requestBoundary?.warmupStartedAt); XCTAssertNil(l.proof); XCTAssertEqual(l.validationCount, 0)
        if let directory = ProcessInfo.processInfo.environment["MAC_TOOLS_START_HISTORY_REPLAY_DIRECTORY"] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct Replay: Encodable {
                let scope = "offlineRetainedHumanPrefixReplayWithoutQuietSuffix"
                let nativeAuthorization = false, nativePosts = 0
                let sourceSHA256: String, boundary: L.StartHistoryBoundary, request: L.RequestBoundary
                let nodes: [L.Node]
            }
            try encoder.encode(Replay(sourceSHA256: try XCTUnwrap(manifest["result.json"]),
                boundary: try XCTUnwrap(l.startHistoryBoundary), request: try XCTUnwrap(l.requestBoundary), nodes: l.nodes))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("human-prefix-request-only.json"))
        }
    }
}
