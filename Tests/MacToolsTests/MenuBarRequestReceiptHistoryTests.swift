// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import AppKit
import CryptoKit
@testable import MacTools

/// All observations are offline injections or immutable captured bytes.
/// No window, tap, permissions, event post, real marker or native Permit.
final class MenuBarRequestReceiptHistoryTests: XCTestCase {
    typealias L = MenuBarLocalContinuityLedger
    let up: UInt64 = 40_000_000_000
    func packet(_ t: UInt64) -> L.R.Packet {
        .init(MenuBarLocalNativeContinuityTests.Harness(configure: false).event(timestamp: t))
    }
    func ledger(_ policy: L.StartPolicy = .requestQuietReal) -> L {
        var l = L(session: UUID(), pid: 123, purpose: .realStart, startPolicy: policy)
        l.configure(window: 7); return l
    }
    func sample(_ began: UInt64, ended: UInt64? = nil, count: UInt32 = 101,
                after: UInt32? = nil, age: Double = 1, buttons: UInt64 = 0) -> L.Sample {
        .init(began: began, ended: ended ?? began + 1, counterBefore: count, counterAfter: after ?? count,
              age: age, buttons: buttons, modifiers: 0, healthyBefore: true, healthyAfter: true)
    }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value)
    }
    func record<T: Encodable>(_ name: String, _ value: T) throws {
        guard let root = ProcessInfo.processInfo.environment["MAC_TOOLS_RECEIPT_HISTORY_EVIDENCE_DIRECTORY"] else { return }
        try encode(value).write(to: URL(fileURLWithPath: root).appendingPathComponent(name + ".json"))
    }
    func matched() -> L {
        var l = ledger()
        l.sampled(sample(up - 10_000, count: 100))
        l.begin(packet(up), at: up)
        l.event(ownPacket: packet(up), at: up + 100)
        l.sampled(sample(up + 101))
        l.claim(at: up + 103)
        XCTAssertEqual(l.state, .requestMatched); XCTAssertTrue(l.requestReceiptHistoryValid)
        return l
    }
    func testActual2F48RequestPrefixMatchesButFullSuffixRefusesRealHIDChange() throws {
        struct Result: Decodable { let localStartTerminal: MenuBarRealLocalAuthorization.Terminal }
        struct Ready: Decodable { let windowID: Int }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("docs/evidence/menu-bar-destination-recheck-v14-live-2026-10-07/session")
        let raw = try Data(contentsOf: folder.appendingPathComponent("result.json"))
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: folder.deletingLastPathComponent().appendingPathComponent("session-sha256.json")))
        let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, hashes["result.json"])
        let c = try JSONDecoder().decode(Result.self, from: raw).localStartTerminal
        let p = try XCTUnwrap(c.capturedStart)
        let window = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: folder.appendingPathComponent("local-ui-ready.json"))).windowID
        let predecessor = try XCTUnwrap(c.input.nodes.first { $0.sequence == 711 })
        XCTAssertEqual(predecessor.sample!.ended - p.timestamp, 558_083)
        for policy in [L.StartPolicy.requestQuietReal, .preUpContinuity] { for first in [true, false] {
            var l = L(session: c.binding.nonce, pid: c.binding.controllerPID, purpose: .realStart, startPolicy: policy)
            l.configure(window: window)
            let prefix = c.input.nodes.filter { $0.sequence <= 713 }
            for n in prefix {
                // AppKit before the OWN UP RECEIPT, after its predecessor.
                // Actual AppKit observation time is unknown; this order is offline.
                if first && n.sequence == 712 { l.begin(p, at: predecessor.observedAt + 1) }
                switch n.kind {
                case .sample: l.sampled(try XCTUnwrap(n.sample))
                case .activity: l.event(ownPacket: nil, at: n.observedAt, activity: n.activity)
                case .ownUp: l.event(ownPacket: n.packet, at: n.observedAt)
                case .loss: l.lost(at: n.observedAt)
                }
                if !first && n.sequence == 713 { l.begin(p, at: n.observedAt) }
            }
            var full = l // Same original prefix, without the earlier offline claim.
            l.claim(at: prefix.last!.observedAt)
            XCTAssertNil(l.proof); XCTAssertEqual(l.validationCount, 0)
            if policy.usesRequestQuiet {
                XCTAssertEqual(l.state, .requestMatched)
                let h = try XCTUnwrap(l.requestBoundary?.receiptHistory)
                XCTAssertEqual(h.predecessorEnded, predecessor.observedAt)
                XCTAssertEqual(h.upObservedAt - h.predecessorEnded, 31_417)
                XCTAssertFalse(l.requestHistorySupportsNativeAuthority)
                XCTAssertFalse(h.activityTimesComplete) // Cannot produce new native authority from missing old metadata.
                XCTAssertTrue(l.requestReceiptHistoryValid)
                // First retained sample has no preceding retained HID counter;
                // its relative epoch cannot reproduce that missing prefix delta.
                let original = prefix.map { n in L.Node(sequence: n.sequence - 685, observedAt: n.observedAt,
                    epoch: n.epoch - (n.sequence == 686 ? 558 : 559), kind: n.kind, tapCount: n.tapCount - 269, sample: n.sample, packet: n.packet) }
                XCTAssertEqual(try encode(l.nodes), try encode(original))
                struct Replay: Encodable {
                    let scope = "offlineOriginal2F48PrefixThroughFirstPostReceiptSampleWithRelativeSequenceTapEpoch"
                    let nativePermitIssued = false, injectedQuietSuffix = false, eventTimesFabricated = false
                    let sourceSHA256: String, appKitBeforeOwnReceipt: Bool
                    let request: L.RequestBoundary, nodes: [L.Node]
                }
                try record("2f48-request-only-\(first)", Replay(sourceSHA256: digest, appKitBeforeOwnReceipt: first,
                    request: try XCTUnwrap(l.requestBoundary), nodes: l.nodes))
                for n in c.input.nodes where n.sequence > 713 { l.sampled(try XCTUnwrap(n.sample)) }
                XCTAssertEqual(l.state, .stopped(.laterInput)) // Real captured HID delta +1 at 714; never waived.
                XCTAssertEqual(l.lastSample?.counterAfter, 30092901)
                XCTAssertEqual(l.firstFailure?.previousState, "requestMatched")
                XCTAssertNil(l.proof); XCTAssertEqual(l.validationCount, 0)
                try record("2f48-full-suffix-refusal-\(first)", try XCTUnwrap(l.firstFailure))
                for n in c.input.nodes where n.sequence > 713 { full.sampled(try XCTUnwrap(n.sample)) }
                full.claim(at: c.atUptimeNanoseconds) // Actual captured claim timing.
                XCTAssertEqual(full.state, .stopped(.laterInput)); XCTAssertEqual(full.matchedStartCount, 0)
                XCTAssertNil(full.requestBoundary); XCTAssertNil(full.proof)
                try record("2f48-actual-claim-refusal-\(first)", try XCTUnwrap(full.firstFailure))
            } else { XCTAssertEqual(l.state, .stopped(.missingPreUpAnchor)) }
        } }
    }
    func testDeferredPreUpActivityIsRecordedInBothOrdersAndNeverClassifiedAsQuiet() throws {
        for first in [true, false] {
            var l = ledger(); l.sampled(sample(up - 100, count: 100))
            if first { l.begin(packet(up), at: up) }
            l.event(ownPacket: nil, at: up + 10, activity: .init(type: CGEventType.leftMouseDown.rawValue, timestamp: up - 10))
            l.sampled(sample(up + 11, count: 100)) // Physically after up, strictly before receipt.
            l.event(ownPacket: packet(up), at: up + 20)
            l.sampled(sample(up + 21))
            if !first { l.begin(packet(up), at: up + 22) }
            let before = try encode(l.nodes)
            l.claim(at: up + 23)
            XCTAssertEqual(l.state, .requestMatched); XCTAssertNil(l.proof)
            XCTAssertEqual(try encode(l.nodes), before)
            XCTAssertEqual(l.requestBoundary?.receiptHistory?.unqualifiedActivitySequences, [2])
            XCTAssertEqual(l.requestBoundary?.receiptHistory?.activityTimesComplete, true)
            XCTAssertEqual(l.requestBoundary?.hidCounter, 101); XCTAssertTrue(l.requestReceiptHistoryValid)
        }
    }
    func testUnknownOrImpossibleDeferredTimeAndPhysicalPostUpActivityRefuse() {
        for time in [UInt64(0), up, up + 1, up + 11] {
            var l = ledger(); l.sampled(sample(up - 100)); l.begin(packet(up), at: up)
            l.event(ownPacket: nil, at: up + 10, activity: .init(type: 1, timestamp: time))
            XCTAssertTrue(l.stopped); XCTAssertNil(l.requestBoundary)
            let failure = l.firstFailure
            l.sampled(sample(up + 11)); l.event(ownPacket: packet(up), at: up + 20); l.claim(at: up + 22)
            XCTAssertEqual(l.firstFailure, failure); XCTAssertEqual(l.matchedStartCount, 0)
        }
        var l = ledger(); l.sampled(sample(up - 100)); l.begin(packet(up), at: up)
        l.event(ownPacket: nil, at: up + 10)
        XCTAssertEqual(l.state, .stopped(.unprovenReceiptActivity))
    }
    func testMetadataPostUpBeforeAppKitCannotHideInUnqualifiedHistory() {
        for timestamp in [up, up + 1, up + 11, 0] {
            var l = ledger(); l.sampled(sample(up - 100))
            l.event(ownPacket: nil, at: up + 10, activity: .init(type: 1, timestamp: timestamp))
            l.sampled(sample(up + 11)); l.event(ownPacket: packet(up), at: up + 20)
            l.sampled(sample(up + 21)); l.begin(packet(up), at: up + 22); l.claim(at: up + 23)
            XCTAssertTrue(l.stopped); XCTAssertNil(l.requestBoundary)
        }
    }
    func testAnyActivityAfterOwnReceiptIncludingDelayedPreUpPacketIsSticky() {
        for kind in ["oldTime", "newTime", "unknown", "repeatUp", "wrongOwnUp"] {
            var l = ledger(); l.sampled(sample(up - 100)); l.begin(packet(up), at: up)
            if kind == "wrongOwnUp" { l.event(ownPacket: packet(up - 1), at: up + 10) }
            else {
                l.event(ownPacket: packet(up), at: up + 10)
                l.event(ownPacket: kind == "repeatUp" ? packet(up) : nil, at: up + 11,
                        activity: kind == "unknown" ? nil : .init(type: 1, timestamp: kind == "oldTime" ? up - 1 : up + 11))
            }
            XCTAssertEqual(l.state, .stopped(.laterInput), kind)
            l.sampled(sample(up + 12)); l.claim(at: up + 13)
            XCTAssertNil(l.requestBoundary); XCTAssertNil(l.proof)
        }
    }
    func testReceiptPredecessorStrictBoundaryAndExisting250msLimit() {
        for delta in [UInt64(0), 1, 250_000_000, 250_000_001] {
            var l = ledger()
            let receiptAt = up + 100
            l.sampled(sample(receiptAt - delta, ended: receiptAt - delta))
            l.begin(packet(up), at: max(up, receiptAt - delta))
            l.event(ownPacket: packet(up), at: receiptAt); l.sampled(sample(receiptAt + 1))
            l.claim(at: receiptAt + 3)
            XCTAssertEqual(l.state, delta == 1 || delta == 250_000_000 ? .requestMatched : .stopped(.missingReceiptPredecessor))
        }
    }
    func testMissingOrNonImmediatePredecessorCannotUseOlderQuietSample() {
        for activity in [false, true] {
            var l = ledger()
            if activity {
                l.sampled(sample(up - 100)); l.event(ownPacket: nil, at: up - 50, activity: .init(type: 1, timestamp: up - 50))
            }
            l.begin(packet(up), at: up); l.event(ownPacket: packet(up), at: up + 10)
            l.sampled(sample(up + 11)); l.claim(at: up + 13)
            XCTAssertEqual(l.state, .stopped(.missingReceiptPredecessor)); XCTAssertNil(l.requestBoundary)
        }
    }
    func testHistorySealRejectsMissingVersionTimesSequencesCounterAndDroppedActivity() throws {
        var l = ledger(); l.sampled(sample(up - 100))
        l.event(ownPacket: nil, at: up - 50, activity: .init(type: 1, timestamp: up - 50))
        l.sampled(sample(up - 49)); l.begin(packet(up), at: up)
        l.event(ownPacket: packet(up), at: up + 10); l.sampled(sample(up + 11)); l.claim(at: up + 13)
        let request = try XCTUnwrap(l.requestBoundary)
        XCTAssertTrue(L.validReceiptHistory(request, nodes: l.nodes)); XCTAssertTrue(l.requestHistorySupportsNativeAuthority)
        let original = try JSONSerialization.jsonObject(with: encode(request)) as! [String: Any]
        for key in ["receiptHistory", "version", "predecessorSequence", "predecessorBegan", "predecessorEnded",
                    "physicalUpTimestamp", "upSequence", "upObservedAt", "guardSequence", "retainedFromSequence",
                    "upTapCount", "unqualifiedActivitySequences", "activityTimesComplete", "hidCounter", "matchedAt", "matchSequence"] {
            var altered = original, h = original["receiptHistory"] as! [String: Any]
            if key == "receiptHistory" { altered.removeValue(forKey: key) }
            else if key == "hidCounter" || key == "matchedAt" || key == "matchSequence" { altered[key] = 0 }
            else {
                if key == "unqualifiedActivitySequences" { h[key] = [UInt64]() }
                else if key == "activityTimesComplete" { h[key] = false }
                else { h[key] = 0 }
                altered["receiptHistory"] = h
            }
            let decoded = try JSONDecoder().decode(L.RequestBoundary.self, from: JSONSerialization.data(withJSONObject: altered))
            XCTAssertFalse(L.validReceiptHistory(decoded, nodes: l.nodes), key)
        }
        XCTAssertFalse(L.validReceiptHistory(request, nodes: l.nodes.filter { $0.kind != .activity }))
        XCTAssertFalse(L.validReceiptHistory(request, nodes: Array(l.nodes.dropFirst())))
    }
    func testFirstPostReceiptReadCannotBeReplacedByLaterGoodReads() {
        for kind in ["overlap", "counter", "held", "age"] {
            var l = ledger(); l.sampled(sample(up - 100)); l.begin(packet(up), at: up)
            l.event(ownPacket: packet(up), at: up + 10)
            l.sampled(sample(kind == "overlap" ? up + 9 : up + 11, ended: up + 12,
                             after: kind == "counter" ? 102 : 101,
                             age: kind == "age" ? 0 : 1, buttons: kind == "held" ? 1 : 0))
            l.sampled(sample(up + 13)); l.claim(at: up + 15)
            if kind == "age" {
                // Zero age still has activity upper bound == FIRST end. Later
                // zero-age reads cannot move it; a subsequent age reset refuses.
                XCTAssertEqual(l.state, .requestMatched)
                XCTAssertEqual(l.requestBoundary?.hidActivityUpperBound, up + 12)
                l.sampled(sample(up + 20, age: 0)); XCTAssertEqual(l.state, .stopped(.hidActivityUnproven))
            } else { XCTAssertTrue(l.stopped, kind); XCTAssertNil(l.requestBoundary) }
        }
    }
    func testCancellationBeforeReceiptRequestWarmupAndCountdownIsPermanent() throws {
        for phase in ["receipt", "request", "warmup", "countdown"] {
            var l = phase == "receipt" ? ledger() : matched()
            if phase == "receipt" { l.sampled(sample(up - 100)); l.begin(packet(up), at: up) }
            if phase == "warmup" || phase == "countdown" { l.startRequestWarmup(at: up + 104) }
            if phase == "countdown" {
                l.sampled(sample(up + 250_000_104)); let first = l.lastSequence + 1
                l.sampled(sample(up + 250_000_106)); l.sampled(sample(up + 250_000_108))
                l.completeRequestQuiet(firstNewSequence: first, at: up + 250_000_110)
                XCTAssertEqual(l.state, .countdown)
            }
            l.fail(.cancelled); let failure = l.firstFailure, nodes = try encode(l.nodes), boundary = l.requestBoundary
            l.begin(packet(up), at: up + 111); l.claim(at: up + 112); l.startRequestWarmup(at: up + 113)
            l.sampled(sample(up + 4_000_000_000))
            XCTAssertEqual(l.state, .stopped(.cancelled)); XCTAssertEqual(l.firstFailure, failure)
            XCTAssertEqual(try encode(l.nodes), nodes); XCTAssertEqual(l.requestBoundary, boundary)
            XCTAssertEqual(l.validationCount, 0)
        }
    }
    func testTrackingModeRegistrationIsExplicitAndIsolatedAdapterRemainsSenderFree() throws {
        let modes = MenuBarLocalStartInput.observationRunLoopModes.map { $0.rawValue as String }
        XCTAssertEqual(modes.count, 2)
        XCTAssertTrue(modes.contains(CFRunLoopMode.commonModes.rawValue as String))
        XCTAssertTrue(modes.contains(RunLoop.Mode.eventTracking.rawValue))
        let h = try MenuBarRequestWarmupTests.Harness(startPolicy: .requestQuietReal)
        try h.request(); try h.quietWindow(); try h.countdown()
        XCTAssertTrue(h.broker.monitor.ledger.requestReceiptHistoryValid)
        XCTAssertEqual(h.broker.monitor.ledger.requestBoundary?.receiptHistory?.activityTimesComplete, true)
        let permit = try h.broker.permit()
        XCTAssertFalse(permit.diagnosticOnly); XCTAssertEqual(permit.authority, .isolated)
        XCTAssertThrowsError(try permit.checkForRealAction(binding: h.broker.binding))
        XCTAssertFalse(h.broker.monitor.diagnostics().native)
    }
}
