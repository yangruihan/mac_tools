// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

/// Offline replay only: no CGEvent, native reads, taps, windows, Permit or sender.
/// The human trace did not retain begin/claim call times. Both compatible begin
/// placements and the recorded claim-time bounds are exercised, never invented
/// as historical facts. The synthetic trace retains only its post-anchor suffix.
final class MenuBarCapturedStartBoundaryTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    struct Snapshot: Decodable {
        struct Binding: Decodable { let controllerPID: Int32, nonce: UUID }
        let binding: Binding
        let capturedStart: MenuBarLocalStartReceipt.Packet
        let input: MenuBarLocalStartInput.Evidence
        let atUptimeNanoseconds: UInt64
        let matchFacts: [String: Bool]
    }
    struct Trace {
        let snapshot: Snapshot, window: Int, sha256: String
        var nodes: [L.Node] { snapshot.input.nodes }
        func ledger(_ purpose: L.Purpose = .realStart) -> L {
            var ledger = L(session: snapshot.binding.nonce, pid: snapshot.binding.controllerPID, purpose: purpose)
            ledger.configure(window: window)
            return ledger
        }
    }
    private func load(human: Bool) throws -> Trace {
        let folder = human ? "menu-bar-real-local-user-round-2026-10-05" : "menu-bar-real-input-diagnostic-2026-10-05"
        let expectedSHA = human ? "fbb4b112664f3f0460a08f4285cc7ce43480540479ef78d98df9c2996a413ea8" : "0eaa58cfc07d25dae5c19a647f88c01c072bba2c55544f144b2fceb177c1710c"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/evidence/\(folder)/session")
        let data = try Data(contentsOf: root.appendingPathComponent("result.json"))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard sha == expectedSHA else { throw NSError(domain: "CapturedTraceChanged", code: 1) }
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let snapshotData = try JSONSerialization.data(withJSONObject: XCTUnwrap(result[human ? "localStartTerminal" : "localAuthorization"]))
        struct Ready: Decodable { let windowID: Int }
        let ready = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: root.appendingPathComponent("local-ui-ready.json")))
        return Trace(snapshot: try JSONDecoder().decode(Snapshot.self, from: snapshotData), window: ready.windowID, sha256: sha)
    }
    private func feed(_ node: L.Node, into ledger: inout L) throws {
        switch node.kind {
        case .sample: ledger.sampled(try XCTUnwrap(node.sample))
        case .ownUp: ledger.event(ownPacket: try XCTUnwrap(node.packet), at: node.observedAt)
        case .activity: ledger.event(ownPacket: nil, at: node.observedAt)
        case .loss: ledger.lost(at: node.observedAt)
        }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func record(_ name: String, trace: Trace, ledger: L, details: [String: Any] = [:]) throws {
        guard let directory = ProcessInfo.processInfo.environment["MAC_TOOLS_CAPTURED_START_REPLAY_DIRECTORY"] else { return }
        var result: [String: Any] = ["scope": "offlineCapturedLedgerReplay", "nativeReads": 0, "eventPosts": 0,
            "fixtureSHA256": trace.sha256, "state": String(describing: ledger.state), "epoch": ledger.epoch,
            "nodes": ledger.nodes.count, "matchedStartCount": ledger.matchedStartCount,
            "validationCount": ledger.validationCount, "proofPresent": ledger.proof != nil]
        for (key, value) in details { result[key] = value }
        if let failure = ledger.firstFailure { result["firstFailure"] = try JSONSerialization.jsonObject(with: encode(failure)) }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"), options: .atomic)
    }
    private func replayHuman(_ trace: Trace, appKitFirst: Bool, claimAt: UInt64, subtractCounter: Bool = false) throws -> L {
        var ledger = trace.ledger()
        let packet = trace.snapshot.capturedStart
        let up = try XCTUnwrap(trace.nodes.first { $0.kind == .ownUp })
        let anchor = try XCTUnwrap(trace.nodes.last { $0.sequence < up.sequence && $0.kind == .sample })
        let anchorCount = try XCTUnwrap(anchor.sample?.counterAfter)
        for node in trace.nodes {
            if node.sequence == up.sequence && appKitFirst { ledger.begin(packet, at: packet.timestamp) }
            if subtractCounter, node.sequence > up.sequence, let s = node.sample {
                // Deliberately false counterfactual, never modify the evidence file.
                ledger.sampled(.init(began: s.began, ended: s.ended, counterBefore: anchorCount, counterAfter: anchorCount,
                    age: s.age, buttons: s.buttons, modifiers: s.modifiers, healthyBefore: s.healthyBefore, healthyAfter: s.healthyAfter))
            } else { try feed(node, into: &ledger) }
            if node.sequence == up.sequence + 1 && !appKitFirst { ledger.begin(packet, at: node.observedAt) }
        }
        ledger.claim(at: claimAt)
        return ledger
    }
    func testHumanFullTraceRefusesInBothCompatibleCallbackOrdersAndClaimBounds() throws {
        let trace = try load(human: true), packet = trace.snapshot.capturedStart
        XCTAssertEqual(trace.nodes.count, 315)
        XCTAssertEqual(trace.nodes.filter { $0.kind == .activity }.count, 90)
        XCTAssertTrue(trace.nodes.filter { $0.kind == .activity }.allSatisfy { $0.packet == nil })
        let up = try XCTUnwrap(trace.nodes.first { $0.kind == .ownUp })
        XCTAssertEqual(up.packet, packet); XCTAssertEqual(packet.type, 2); XCTAssertEqual(packet.sourceState, 1)
        let requiredNodes = trace.nodes.filter { $0.observedAt >= packet.timestamp - 250_000_000 }
        for field in ["type", "timestamp", "number", "sourcePID", "sourceState", "flags", "point"] {
            XCTAssertEqual(trace.snapshot.matchFacts[field + "Equal"], true)
        }
        for appKitFirst in [true, false] {
            for claimAt in [try XCTUnwrap(trace.nodes.last).observedAt, trace.snapshot.atUptimeNanoseconds] {
                var ledger = try replayHuman(trace, appKitFirst: appKitFirst, claimAt: claimAt)
                XCTAssertEqual(ledger.state, .stopped(.hidChangedAcrossStart))
                // Only waiting history outside the admissible anchor interval
                // retires; all retained raw epochs/indices/times stay exact.
                XCTAssertEqual(try encode(ledger.nodes), try encode(requiredNodes))
                XCTAssertEqual(ledger.startHistoryBoundary?.retiredNodeCount, trace.nodes.count - requiredNodes.count)
                XCTAssertEqual(ledger.firstFailure?.operation, "claim(at:)")
                XCTAssertEqual(ledger.firstFailure?.lastSequence, 315)
                XCTAssertEqual(ledger.firstFailure?.previousState, "awaitingReceipt")
                XCTAssertNil(ledger.proof); XCTAssertEqual(ledger.matchedStartCount, 0); XCTAssertEqual(ledger.validationCount, 0)
                let failure = ledger.firstFailure
                ledger.event(ownPacket: packet, at: claimAt + 1)
                ledger.begin(packet, at: claimAt + 2); ledger.claim(at: claimAt + 3)
                XCTAssertEqual(ledger.firstFailure, failure); XCTAssertEqual(ledger.nodes.count, requiredNodes.count)
                try record("human-\(appKitFirst)-\(claimAt)", trace: trace, ledger: ledger,
                    details: ["appKitBeforeTapPlacement": appKitFirst, "claimBound": claimAt, "rawRetainedNodesEqual": true])
            }
        }
        // Two ledger epochs are observations from two channels, not two input events.
        let boundary = Array(trace.nodes.suffix(5))
        XCTAssertEqual(boundary.map(\.epoch), [153, 154, 155, 155, 155])
        XCTAssertEqual(boundary.map(\.tapCount), [90, 91, 91, 91, 91])
        XCTAssertEqual(boundary.filter { $0.kind != .sample }.map(\.kind), [.ownUp])
    }
    func testSubtractingOneInCounterfactualStillFailsIndependentHIDAgeGuard() throws {
        let trace = try load(human: true)
        for appKitFirst in [true, false] {
            let ledger = try replayHuman(trace, appKitFirst: appKitFirst,
                claimAt: trace.snapshot.atUptimeNanoseconds, subtractCounter: true)
            XCTAssertEqual(ledger.state, .stopped(.hidActivityUnproven))
            XCTAssertNil(ledger.proof); XCTAssertEqual(ledger.validationCount, 0)
            try record("counterfactual-subtract-one-\(appKitFirst)", trace: trace, ledger: ledger,
                details: ["counterfactual": true, "altered": "post-up counters only; original fixture unchanged"])
        }
        _ = try load(human: true) // Verify the original evidence hash again.
    }
    private func syntheticPrefix(_ trace: Trace, appKitFirst: Bool, purpose: L.Purpose = .realStart) throws -> L {
        var ledger = trace.ledger(purpose)
        let proof = try XCTUnwrap(trace.snapshot.input.proof), packet = trace.snapshot.capturedStart
        for node in trace.nodes where node.sequence <= proof.matchSequence {
            if node.sequence == proof.upSequence && appKitFirst { ledger.begin(packet, at: packet.timestamp) }
            try feed(node, into: &ledger)
            if node.sequence == proof.upSequence + 1 && !appKitFirst { ledger.begin(packet, at: node.observedAt) }
        }
        ledger.claim(at: proof.matchedAt)
        XCTAssertEqual(ledger.state, .countdown)
        return ledger
    }
    func testCapturedSyntheticSuffixPassesWithOnlyIndexNormalization() throws {
        let trace = try load(human: false), original = try XCTUnwrap(trace.snapshot.input.proof)
        let anchor = try XCTUnwrap(trace.nodes.first), final = try XCTUnwrap(trace.snapshot.input.finalSampleSequence)
        XCTAssertEqual(anchor.sequence, 9); XCTAssertEqual(anchor.tapCount, 1); XCTAssertEqual(anchor.epoch, 2)
        XCTAssertEqual(trace.nodes.count, 143)
        for appKitFirst in [true, false] {
            for realStart in [true, false] {
                var ledger = try syntheticPrefix(trace, appKitFirst: appKitFirst, purpose: realStart ? .realStart : .noMove)
                for node in trace.nodes where node.sequence > original.matchSequence {
                    try feed(node, into: &ledger)
                    if node.sequence == final {
                        // Original complete() call time was not retained: use this sample's end as a test invocation.
                        ledger.complete(firstNewSequence: final - anchor.sequence, at: node.observedAt)
                    }
                }
                XCTAssertEqual(ledger.state, realStart ? .validatedRealInput : .validatedNoMove)
                XCTAssertEqual(ledger.matchedStartCount, 1); XCTAssertEqual(ledger.validationCount, 1)
                let proof = try XCTUnwrap(ledger.proof)
                XCTAssertEqual(proof.packet, original.packet); XCTAssertEqual(proof.matchedAt, original.matchedAt)
                XCTAssertEqual(proof.deadline - proof.matchedAt, 3_000_000_000)
                XCTAssertEqual(proof.hidCounter, original.hidCounter); XCTAssertEqual(proof.hidActivityUpperBound, original.hidActivityUpperBound)
                let normalized = trace.nodes.map { n in L.Node(sequence: n.sequence - anchor.sequence + 1,
                    observedAt: n.observedAt, epoch: n.epoch - anchor.epoch, kind: n.kind,
                    tapCount: n.tapCount - anchor.tapCount, sample: n.sample, packet: n.packet) }
                XCTAssertEqual(try encode(ledger.nodes), try encode(normalized))
                XCTAssertEqual(ledger.finalSampleSequence, final - anchor.sequence + 1)
                try record("synthetic-\(appKitFirst)-\(realStart)", trace: trace, ledger: ledger,
                    details: ["retainedSuffixOnly": true, "sequenceOffset": 8, "epochOffset": 2, "tapCountOffset": 1,
                              "timestampsPacketsAndSamplesUnchanged": true])
            }
        }
    }
    func testSyntheticPositiveControlCannotAbsorbLaterInputOrHealthLoss() throws {
        let trace = try load(human: false), proof = try XCTUnwrap(trace.snapshot.input.proof)
        let cases: [(String, L.Cause)] = [("tap", .laterInput), ("repeatUp", .laterInput), ("counter", .laterInput),
            ("ageOnly", .hidActivityUnproven), ("button", .laterInput), ("modifier", .laterInput), ("lost", .monitorLost)]
        for (kind, cause) in cases {
            var ledger = try syntheticPrefix(trace, appKitFirst: false)
            let time = proof.matchedAt + 100_000, s = try XCTUnwrap(ledger.lastSample)
            switch kind {
            case "tap": ledger.event(ownPacket: nil, at: time)
            case "repeatUp": ledger.event(ownPacket: trace.snapshot.capturedStart, at: time)
            default:
                let count = proof.hidCounter + (kind == "counter" ? 1 : 0)
                ledger.sampled(.init(began: time, ended: time, counterBefore: count, counterAfter: count,
                    age: kind == "ageOnly" ? 0 : (try XCTUnwrap(s.age)) + Double(time - s.ended) / 1_000_000_000,
                    buttons: kind == "button" ? 1 : 0, modifiers: kind == "modifier" ? 1 : 0,
                    healthyBefore: true, healthyAfter: kind != "lost"))
            }
            XCTAssertEqual(ledger.state, .stopped(cause), kind)
            let failure = ledger.firstFailure, count = ledger.nodes.count
            for node in trace.nodes where node.sequence > proof.matchSequence { try feed(node, into: &ledger) }
            ledger.complete(firstNewSequence: 1, at: trace.snapshot.atUptimeNanoseconds)
            XCTAssertEqual(ledger.firstFailure, failure); XCTAssertEqual(ledger.nodes.count, count)
            XCTAssertEqual(ledger.validationCount, 0)
            try record("negative-\(kind)", trace: trace, ledger: ledger, details: ["injection": kind, "laterQuietDoesNotResume": true])
        }
    }
}
