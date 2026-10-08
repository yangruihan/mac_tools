// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CryptoKit
@testable import MacTools

final class MenuBarMoveStageRecorderTests: XCTestCase {
    typealias R = MenuBarMoveStageRecorder
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("move-stages-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testDurablePrivateChainBindsFullPayloadAndCannotReopen() throws {
        let nonce = UUID(), dir = root.appendingPathComponent("stages"), recorder = try R(directory: dir, nonce: nonce, controllerPID: 123)
        let original = MenuBarHiddenMoveFixture().original
        try recorder.append("original", original); try recorder.appendJSON("menu", ["generation": 4, "closed": 4])
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        var head: String?
        for (i, file) in files.enumerated() {
            let data = try Data(contentsOf: file), record = try JSONDecoder().decode(R.Record.self, from: data)
            XCTAssertEqual(record.sequence, i + 1); XCTAssertEqual(record.nonce, nonce); XCTAssertEqual(record.controllerPID, 123)
            XCTAssertEqual(record.previousSHA256, head)
            head = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
            if i == 0 { XCTAssertTrue(try JSONDecoder().decode(MenuBarHiddenMoveModel.Snapshot.self, from: record.payload).sameFacts(as: original)) }
        }
        XCTAssertEqual(recorder.count, 2); XCTAssertEqual(recorder.head, head)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertThrowsError(try R(directory: dir, nonce: nonce, controllerPID: 123))
    }
    func testPartialWriteFailurePoisonsRecorderAndCannotRetryNewFilename() throws {
        enum Failure: Error { case disk }
        var writes = 0
        let r = try R(directory: root.appendingPathComponent("stages"), nonce: UUID(), controllerPID: 123) { data, file in
            writes += 1; try MenuBarDispatchWitness.writeNew(data, to: file); throw Failure.disk
        }
        XCTAssertThrowsError(try r.append("prepared", ["value": true]))
        XCTAssertThrowsError(try r.append("retry", ["value": true]))
        XCTAssertTrue(r.poisoned); XCTAssertEqual(writes, 1); XCTAssertEqual(r.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.directory.appendingPathComponent("0001-prepared.json").path))
    }
    func testSerializationFailureAlsoPermanentlyStopsEvidence() throws {
        let r = try R(directory: root.appendingPathComponent("stages"), nonce: UUID(), controllerPID: 123)
        XCTAssertThrowsError(try r.append("invalid", ["value": Double.nan]))
        XCTAssertTrue(r.poisoned); XCTAssertThrowsError(try r.append("later", ["value": 1]))
    }
}
