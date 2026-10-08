// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarRealRunControlTests: XCTestCase {
    var directory: URL!
    let binding = MenuBarDispatchWitness.Binding(nonce: UUID(), targetPID: 321, controllerPID: 123,
        controllerLaunch: 10, controllerSHA256: String(repeating: "c", count: 64))
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("real-control-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func request() -> [String: Any] {
        ["nonce": binding.nonce.uuidString, "pid": binding.targetPID, "controllerPID": binding.controllerPID,
         "transaction": "transaction", "action": "cancel-preparation", "atUnix": 100.0]
    }
    func testFreshBoundCancelLatchesWithoutGrantingStart() throws {
        let c = MenuBarRealRunControl(directory: directory, binding: binding, transaction: "transaction")
        XCTAssertFalse(try c.read(now: 100))
        try MenuBarDispatchWitness.writeNew(JSONSerialization.data(withJSONObject: request()), to: directory.appendingPathComponent("cancel-preparation.json"))
        XCTAssertTrue(try c.read(now: 101)); XCTAssertTrue(try c.read(now: 999)); XCTAssertTrue(c.cancelled)
    }
    func testWrongBindingStaleAndSymlinkAreRefused() throws {
        for key in ["nonce", "pid", "controllerPID", "transaction", "action", "atUnix"] {
            let sub = directory.appendingPathComponent(key); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
            var request = request(); request[key] = key == "atUnix" ? 97.0 : "wrong"
            try MenuBarDispatchWitness.writeNew(JSONSerialization.data(withJSONObject: request), to: sub.appendingPathComponent("cancel-preparation.json"))
            XCTAssertThrowsError(try MenuBarRealRunControl(directory: sub, binding: binding, transaction: "transaction").read(now: 100))
        }
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("cancel-preparation.json").path, withDestinationPath: "/nonexistent")
        XCTAssertThrowsError(try MenuBarRealRunControl(directory: directory, binding: binding, transaction: "transaction").read(now: 100))
    }
    func testRemoteTriggerCannotStartLocalRealWorker() throws {
        try Data("{}".utf8).write(to: directory.appendingPathComponent("action-request.json"))
        XCTAssertThrowsError(try MenuBarRealRunControl(directory: directory, binding: binding, transaction: "transaction").read(now: 100))
    }
}
