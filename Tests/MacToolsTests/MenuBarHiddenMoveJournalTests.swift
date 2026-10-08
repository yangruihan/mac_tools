// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import Darwin
@testable import MacTools

final class MenuBarHiddenMoveJournalTests: XCTestCase {
    private typealias J = MenuBarHiddenMoveJournal
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("hidden-move-v2.json") }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hidden-journal-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func expect(_ failure: J.Failure, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? J.Failure, failure, file: file, line: line) }
    }
    func testLifecyclePrivateModesTwoReturnSamplesAndSeparateV1Responsibility() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), j = J(directory: directory)
        let v1 = try MenuBarMoveAdapterFixture(), legacy = MenuBarTemporaryMoveJournal(directory: directory)
        _ = try legacy.persist(v1.record, replacing: nil, boundTo: v1.owner)
        let v1File = directory.appendingPathComponent("temporary-move-v1.json"), before = try Data(contentsOf: v1File)
        XCTAssertNil(try j.inspect())
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        let initial = try Data(contentsOf: file)
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        XCTAssertEqual(try Data(contentsOf: file), initial)
        var previous = record
        for phase in [J.Record.Phase.moved, .restorePrepared, .restored] {
            let next = try f.phase(phase, from: record)
            _ = try j.persist(next, replacing: previous, boundTo: f.original.owner)
            XCTAssertEqual(try J(directory: directory).load(boundTo: f.original.owner), next)
            previous = next
        }
        XCTAssertEqual(previous.returnEvidence?.count, 2)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        try j.clear(previous, boundTo: f.original.owner); try j.clear(previous, boundTo: f.original.owner)
        XCTAssertNil(try j.inspect()); XCTAssertEqual(try Data(contentsOf: v1File), before)
        XCTAssertEqual(try legacy.inspect(), v1.record)
    }
    func testStaleTransactionBackwardTransitionAndUnprovenReturnCannotErase() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), j = J(directory: directory)
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        expect(.stale) { _ = try j.persist(f.record(), replacing: nil, boundTo: f.original.owner) }
        let moved = try f.phase(.moved, from: record)
        _ = try j.persist(moved, replacing: record, boundTo: f.original.owner)
        expect(.transition) { _ = try j.persist(record, replacing: moved, boundTo: f.original.owner) }
        expect(.transition) { try j.clear(moved, boundTo: f.original.owner) }
        let returned = try f.phase(.restored, from: record)
        expect(.stale) { _ = try j.persist(returned, replacing: record, boundTo: f.original.owner) }
        var forged = moved; forged.phase = .restored
        expect(.corrupt) { _ = try j.persist(forged, replacing: moved, boundTo: f.original.owner) }
        XCTAssertEqual(try j.inspect(), moved)
    }
    func testOwnerSessionMismatchKeepsOriginalJournalBytes() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), j = J(directory: directory)
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        let before = try Data(contentsOf: file), changed = f.owner(nonce: UUID())
        expect(.identity) { _ = try j.load(boundTo: changed) }
        expect(.identity) { try j.clear(f.phase(.restored, from: record), boundTo: changed) }
        XCTAssertEqual(try Data(contentsOf: file), before); XCTAssertEqual(try j.inspect(), record)
    }
    func testCorruptEnvelopeAndUnsupportedSchemaAreNeverOverwritten() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), j = J(directory: directory)
        var wrong = record
        wrong = .init(schemaVersion: 1, transaction: record.transaction, plan: record.plan, phase: .prepared, returnEvidence: nil)
        expect(.corrupt) { _ = try j.persist(wrong, replacing: nil, boundTo: f.original.owner) }
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        let valid = try Data(contentsOf: file)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        envelope["version"] = 1
        let invalid = [Data("{".utf8), Data(valid.prefix(valid.count / 2)), try JSONSerialization.data(withJSONObject: envelope)]
        for damage in invalid {
            try damage.write(to: file)
            expect(.corrupt) { _ = try j.inspect() }
            expect(.corrupt) { _ = try j.persist(record, replacing: nil, boundTo: f.original.owner) }
            expect(.corrupt) { try j.clear(f.phase(.restored, from: record), boundTo: f.original.owner) }
            XCTAssertEqual(try Data(contentsOf: file), damage)
        }
    }
    func testFaultBeforeRenameKeepsOriginalAfterRenameKeepsPossibleEffect() throws {
        enum Injected: Error { case stop }
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), plain = J(directory: directory)
        _ = try plain.persist(record, replacing: nil, boundTo: f.original.owner)
        let moved = try f.phase(.moved, from: record)
        for point in [J.Point.temporaryCreated, .fileSynced] {
            let broken = J(directory: directory) { if $0 == point { throw Injected.stop } }
            XCTAssertThrowsError(try broken.persist(moved, replacing: record, boundTo: f.original.owner))
            XCTAssertEqual(try plain.inspect(), record)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".tmp") })
        }
        let broken = J(directory: directory) { if $0 == .renamed { throw Injected.stop } }
        XCTAssertThrowsError(try broken.persist(moved, replacing: record, boundTo: f.original.owner))
        XCTAssertEqual(try plain.inspect(), moved)
        XCTAssertEqual(try plain.persist(moved, replacing: record, boundTo: f.original.owner), moved)
    }
    func testUnsafeLeafModesSymlinksAndCompetingLockFailClosed() throws {
        let f = MenuBarHiddenMoveFixture(), record = try f.record(), j = J(directory: directory)
        let other = directory.appendingPathComponent("other")
        try Data("untouched".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        expect(.unsafeFile) { _ = try j.inspect() }
        XCTAssertEqual(try String(contentsOf: other), "untouched")
        try FileManager.default.removeItem(at: file)
        _ = try j.persist(record, replacing: nil, boundTo: f.original.owner)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        expect(.unsafeFile) { _ = try j.inspect() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let lockFD = open(directory.appendingPathComponent(".hidden-move-v2.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(lockFD, 0); defer { close(lockFD) }
        XCTAssertEqual(flock(lockFD, LOCK_EX | LOCK_NB), 0)
        expect(.busy) { _ = try J(directory: directory).inspect() }
        XCTAssertEqual(flock(lockFD, LOCK_UN), 0)
        XCTAssertEqual(try j.inspect(), record)
    }
}
