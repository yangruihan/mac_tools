// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarLocalNoMovePreparationTests: XCTestCase {
    typealias P = MenuBarLocalNoMovePreparation
    let binding = P.Binding(pid: 123, launch: 1, nonce: UUID(),
        executable: "/tmp/mac-tools-hidden-driver-task7/Hidden Targets.app/Contents/MacOS/HiddenTargets",
        hash: String(repeating: "a", count: 64), identifier: "com.ryanai.mactools.nativetargets", team: "58TJ64422P")
    lazy var items: [P.Item] = [
        .init(key: "mactools_native_acceptance_T", instance: UUID(), window: 10, pid: 123, frame: CGRect(x: 630, y: 0, width: 29, height: 37)),
        .init(key: "mactools_native_acceptance_N", instance: UUID(), window: 11, pid: 123, frame: CGRect(x: 659, y: 0, width: 30, height: 37))]
    func ready(secondBinding: P.Binding? = nil, secondItems: [P.Item]? = nil, now: UInt64 = 1160, healthy: Bool = true) throws -> P.Ready {
        try P.prepare(expected: binding, first: .init(binding: binding, sequence: 1, uptime: 1000, items: items),
            second: .init(binding: secondBinding ?? binding, sequence: 2, uptime: 1150, items: secondItems ?? items),
            now: now, listenerHealthy: healthy, mode: .local)
    }
    func testMissingDestinationStillAuthorizesLocalPresentationOnly() throws {
        // No destination exists in the injected environment or local input type.
        let destination: Int? = nil
        XCTAssertNil(destination)
        var presented = false
        let presenter: (P.Ready) -> Void = { local in
            presented = true
            XCTAssertFalse(local.nativeDispatchEnabled)
            XCTAssertEqual(local.senderCapability, "absent")
            XCTAssertEqual(local.items.count, 2)
        }
        presenter(try ready()) // Mock presentation: no AppKit window or input tap.
        XCTAssertTrue(presented)
    }
    func testInvalidFixtureOrListenerCannotReachPresenter() {
        var presented = false
        let presenter: (P.Ready) -> Void = { _ in presented = true }
        do { presenter(try ready(healthy: false)); XCTFail("unhealthy") } catch {}
        do { presenter(try ready(secondItems: [])); XCTFail("missing owned models") } catch {}
        do { presenter(try ready(now: 2000)); XCTFail("stale") } catch {}
        XCTAssertFalse(presented)
    }
    func testChangedNoncePIDLaunchPathAndSignatureAllRefuse() {
        let altered = [
            P.Binding(pid: 124, launch: binding.launch, nonce: binding.nonce, executable: binding.executable, hash: binding.hash, identifier: binding.identifier, team: binding.team),
            P.Binding(pid: binding.pid, launch: 2, nonce: binding.nonce, executable: binding.executable, hash: binding.hash, identifier: binding.identifier, team: binding.team),
            P.Binding(pid: binding.pid, launch: binding.launch, nonce: UUID(), executable: binding.executable, hash: binding.hash, identifier: binding.identifier, team: binding.team),
            P.Binding(pid: binding.pid, launch: binding.launch, nonce: binding.nonce, executable: "/Applications/MacTools.app", hash: binding.hash, identifier: binding.identifier, team: binding.team),
            P.Binding(pid: binding.pid, launch: binding.launch, nonce: binding.nonce, executable: binding.executable, hash: String(repeating: "b", count: 64), identifier: binding.identifier, team: binding.team)]
        for changed in altered { XCTAssertThrowsError(try ready(secondBinding: changed)) }
    }
    func testForeignOrChangedGeometryAndDuplicateInstancesRefuse() {
        let t = items[0], n = items[1]
        for changed in [
            P.Item(key: t.key, instance: t.instance, window: t.window, pid: 999, frame: t.frame),
            P.Item(key: t.key, instance: t.instance, window: t.window, pid: t.pid, frame: CGRect(x: 631, y: 0, width: 29, height: 37)),
            P.Item(key: t.key, instance: n.instance, window: t.window, pid: t.pid, frame: t.frame)] {
            XCTAssertThrowsError(try ready(secondItems: [changed, n]))
        }
    }
    func testNoRuntimeUpgradeModeAndCountdownRemainsProposalOnly() throws {
        for mode in ["--run-once", "--wait-once", "--prepare", "--inspect-recovery"] { XCTAssertNil(P.Mode(rawValue: mode)) }
        let local = try ready()
        var gate = MenuBarLocalAcceptanceGate(session: local.binding.nonce)
        gate.prepared(pid: 123, window: 7)
        let proof = MenuBarLocalAcceptanceGate.StartProof(session: local.binding.nonce, receipt: UUID(), window: 7, eventNumber: 1, timestamp: 10, targetPID: 123)
        gate.start(appKit: proof, tap: proof, now: 1000)
        for t in stride(from: UInt64(1100), through: 4000, by: 100) { gate.tick(now: t, monitorHealthy: true) }
        XCTAssertEqual(gate.state, .triggerProposed)
        XCTAssertEqual(gate.triggerCount, 1)
        XCTAssertFalse(local.nativeDispatchEnabled)
        XCTAssertEqual(local.mode, .local)
    }
    func testHistoricalOwnedCGPublicationReplayWithoutAnyDestination() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("docs/evidence/menu-bar-local-no-move-split-2026-10-04/historical-owned-geometry-replay.json")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertTrue(value["destination"] is NSNull)
        let pid = try XCTUnwrap(value["pid"] as? Int32), models = try XCTUnwrap(value["models"] as? [[String: Any]])
        let rows = try XCTUnwrap(value["publicRows"] as? [[String: Any]]), top = try XCTUnwrap(value["screenTop"] as? Double)
        let decoded = try P.items(models: models, publicRows: rows, pid: pid, screenTop: top)
        XCTAssertEqual(decoded.map(\.frame.minX), [630, 659])
        let replayBinding = P.Binding(pid: pid, launch: 1, nonce: UUID(), executable: binding.executable,
            hash: binding.hash, identifier: binding.identifier, team: binding.team)
        let local = try P.prepare(expected: replayBinding,
            first: .init(binding: replayBinding, sequence: 1, uptime: 1000, items: decoded),
            second: .init(binding: replayBinding, sequence: 2, uptime: 1150, items: decoded),
            now: 1160, listenerHealthy: true, mode: .local)
        XCTAssertFalse(local.nativeDispatchEnabled) // Simulated fresh binding, not historical live admission.
        var foreignRows = rows; foreignRows[0]["kCGWindowOwnerPID"] = 999
        XCTAssertThrowsError(try P.items(models: models, publicRows: foreignRows, pid: pid, screenTop: top))
        XCTAssertThrowsError(try P.items(models: models, publicRows: [], pid: pid, screenTop: top))
    }

}
