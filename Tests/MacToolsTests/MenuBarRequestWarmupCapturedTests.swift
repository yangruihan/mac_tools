// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

/// Replay of the COMPLETE native FEF17D8A trace, including its measured quiet
/// and countdown samples. Negative variants inject activity only in memory.
final class MenuBarRequestWarmupCapturedTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    struct Result: Decodable { let localAuthorization: MenuBarRealLocalAuthorization.Terminal }
    private func captured() throws -> MenuBarRealLocalAuthorization.Terminal {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/evidence/menu-bar-request-warmup-native-2026-10-05/session/result.json"))
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "9ad93eea3fd4b4b070eecf4eefb8df010aef2ec42baa5e6e2430266014a1bb9a")
        return try JSONDecoder().decode(Result.self, from: data).localAuthorization
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(value)
    }
    private func record(_ name: String, value: [String: String]) throws {
        guard let directory = ProcessInfo.processInfo.environment["MAC_TOOLS_NATIVE_WARMUP_REPLAY_DIRECTORY"] else { return }
        try encoded(value).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"), options: .atomic)
    }
    private func replay(_ c: MenuBarRealLocalAuthorization.Terminal, appKitFirst: Bool,
                        policy: L.StartPolicy = .requestQuietDiagnostic,
                        injection: (sequence: UInt64, kind: String)? = nil) throws -> L {
        let proof = try XCTUnwrap(c.input.proof), request = try XCTUnwrap(c.input.requestBoundary)
        let anchor = try XCTUnwrap(c.input.nodes.first), offset = anchor.sequence - 1
        var ledger = L(session: c.binding.nonce, pid: c.binding.controllerPID, purpose: .realStart, startPolicy: policy)
        ledger.configure(window: proof.window)
        var warmupStarted = false
        for node in c.input.nodes {
            if !warmupStarted, let start = request.warmupStartedAt, (node.sample?.began ?? node.observedAt) >= start,
               ledger.state == .requestMatched {
                ledger.startRequestWarmup(at: start); warmupStarted = true
            }
            if node.sequence == request.upSequence && appKitFirst { ledger.begin(request.packet, at: request.packet.timestamp) }
            if let injection, node.sequence == injection.sequence {
                let s = try XCTUnwrap(node.sample)
                if injection.kind == "tap" { ledger.event(ownPacket: nil, at: s.began) }
                else {
                    ledger.sampled(.init(began: s.began, ended: s.ended,
                        counterBefore: injection.kind == "counter" ? request.hidCounter + 1 : s.counterBefore,
                        counterAfter: injection.kind == "counter" ? request.hidCounter + 1 : s.counterAfter,
                        age: injection.kind == "age" ? 0 : s.age, buttons: s.buttons, modifiers: s.modifiers,
                        healthyBefore: s.healthyBefore, healthyAfter: injection.kind != "health"))
                }
            } else {
                switch node.kind {
                case .sample: ledger.sampled(try XCTUnwrap(node.sample))
                case .ownUp: ledger.event(ownPacket: try XCTUnwrap(node.packet), at: node.observedAt)
                case .activity: ledger.event(ownPacket: nil, at: node.observedAt)
                case .loss: ledger.lost(at: node.observedAt)
                }
            }
            if node.sequence == request.guardSequence && !appKitFirst { ledger.begin(request.packet, at: node.observedAt) }
            if node.sequence == request.matchSequence { ledger.claim(at: request.matchedAt) }
            if node.sequence == proof.matchSequence {
                ledger.completeRequestQuiet(firstNewSequence: node.sequence - offset - 1, at: proof.matchedAt)
            }
            if node.sequence == c.input.finalSampleSequence {
                // Original final complete() invocation time is not recorded;
                // use its final sample's end as the offline invocation bound.
                ledger.complete(firstNewSequence: node.sequence - offset - 1, at: node.observedAt)
            }
        }
        return ledger
    }
    func testCompleteNativeTracePassesWithUnchangedSamplesInBothCallbackOrders() throws {
        let c = try captured(), anchor = try XCTUnwrap(c.input.nodes.first)
        XCTAssertTrue(c.diagnostics.native); XCTAssertEqual(c.input.nodes.count, 161)
        XCTAssertTrue(c.handedOff); XCTAssertEqual(c.validationCount, 1)
        for first in [true, false] {
            let ledger = try replay(c, appKitFirst: first)
            XCTAssertEqual(ledger.state, .validatedRealInput)
            XCTAssertEqual(ledger.validationCount, 1); XCTAssertEqual(ledger.matchedStartCount, 1)
            let proof = try XCTUnwrap(ledger.proof), original = try XCTUnwrap(c.input.proof)
            XCTAssertEqual(proof.packet, original.packet); XCTAssertEqual(proof.hidCounter, original.hidCounter)
            XCTAssertEqual(proof.hidActivityUpperBound, original.hidActivityUpperBound)
            XCTAssertEqual(proof.matchedAt, original.matchedAt); XCTAssertEqual(proof.deadline, original.deadline)
            XCTAssertEqual(proof.requestBoundary?.warmupStartedAt, original.requestBoundary?.warmupStartedAt)
            let normalized = c.input.nodes.map { n in L.Node(sequence: n.sequence - anchor.sequence + 1,
                observedAt: n.observedAt, epoch: n.epoch - anchor.epoch, kind: n.kind,
                tapCount: n.tapCount - anchor.tapCount, sample: n.sample, packet: n.packet) }
            XCTAssertEqual(try encoded(ledger.nodes), try encoded(normalized))
            try record("native-complete-\(first)", value: ["scope": "offlineCompleteNativeTraceReplay",
                "newNativeActions": "0", "samplesAndPacketsUnchanged": "true", "state": String(describing: ledger.state)])
        }
    }
    func testInjectedLaterActivityStopsWarmupCountdownAndPostValidationPermanently() throws {
        let c = try captured(), request = try XCTUnwrap(c.input.requestBoundary), proof = try XCTUnwrap(c.input.proof)
        let warming = try XCTUnwrap(c.input.nodes.first { ($0.sample?.began ?? 0) >= request.warmupStartedAt! }).sequence
        let phases: [(String, UInt64)] = [("warmup", warming), ("countdown", proof.matchSequence + 1),
                                        ("postValidation", try XCTUnwrap(c.input.finalSampleSequence) + 1)]
        for (phase, sequence) in phases {
            for kind in ["tap", "counter", "age", "health"] {
                var ledger = try replay(c, appKitFirst: false, injection: (sequence, kind))
                let expected: L.Cause = kind == "age" ? .hidActivityUnproven : kind == "health" ? .monitorLost : .laterInput
                XCTAssertEqual(ledger.state, .stopped(expected), phase + kind)
                let failure = try XCTUnwrap(ledger.firstFailure), frozenCount = ledger.nodes.count
                // replay() already fed all remaining original healthy samples.
                ledger.begin(request.packet, at: c.atUptimeNanoseconds)
                ledger.claim(at: c.atUptimeNanoseconds); ledger.startRequestWarmup(at: c.atUptimeNanoseconds)
                XCTAssertEqual(ledger.firstFailure, failure); XCTAssertEqual(ledger.nodes.count, frozenCount)
                XCTAssertEqual(ledger.requestBoundary?.hidCounter, request.hidCounter)
                XCTAssertEqual(ledger.requestBoundary?.warmupStartedAt, request.warmupStartedAt)
                try record("injected-\(phase)-\(kind)", value: ["scope": "offlineNativeTraceWithInjectedActivity",
                    "newNativeActions": "0", "phase": phase, "injection": kind, "state": String(describing: ledger.state),
                    "laterQuietDoesNotResume": "true", "nativeNegativeTrial": "false"])
            }
        }
    }
    func testRealPolicyUsesIdenticalNativeSamplesAndKeepsAllTwelveRefusals() throws {
        let c = try captured(), request = try XCTUnwrap(c.input.requestBoundary), proof = try XCTUnwrap(c.input.proof)
        for first in [true, false] {
            let diagnostic = try replay(c, appKitFirst: first)
            let real = try replay(c, appKitFirst: first, policy: .requestQuietReal)
            XCTAssertEqual(real.state, .validatedRealInput)
            XCTAssertEqual(try encoded(real.nodes), try encoded(diagnostic.nodes))
            XCTAssertEqual(real.proof?.deadline, diagnostic.proof?.deadline)
            XCTAssertEqual(real.proof?.hidCounter, diagnostic.proof?.hidCounter)
            XCTAssertEqual(real.requestBoundary?.warmupStartedAt, diagnostic.requestBoundary?.warmupStartedAt)
        }
        let warmup = try XCTUnwrap(c.input.nodes.first { ($0.sample?.began ?? 0) >= request.warmupStartedAt! }).sequence
        for sequence in [warmup, proof.matchSequence + 1, try XCTUnwrap(c.input.finalSampleSequence) + 1] {
            for kind in ["tap", "counter", "age", "health"] {
                let diagnostic = try replay(c, appKitFirst: false, injection: (sequence, kind))
                var real = try replay(c, appKitFirst: false, policy: .requestQuietReal, injection: (sequence, kind))
                XCTAssertEqual(real.state, diagnostic.state); XCTAssertTrue(real.stopped)
                XCTAssertEqual(try encoded(real.nodes), try encoded(diagnostic.nodes))
                let failure = real.firstFailure
                real.begin(request.packet, at: c.atUptimeNanoseconds)
                real.claim(at: c.atUptimeNanoseconds); real.startRequestWarmup(at: c.atUptimeNanoseconds)
                XCTAssertEqual(real.firstFailure, failure)
                XCTAssertEqual(real.requestBoundary?.warmupStartedAt, request.warmupStartedAt)
                try record("real-policy-injected-\(sequence)-\(kind)", value: ["scope": "offlineRealPolicyNativeTraceReplay",
                    "newNativeActions": "0", "realNativeAuthorization": "false", "state": String(describing: real.state)])
            }
        }
    }
}
