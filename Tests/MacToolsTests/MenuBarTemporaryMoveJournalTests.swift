import XCTest
import Darwin
@testable import MacTools

final class MenuBarTemporaryMoveJournalTests: XCTestCase {
    private typealias J = MenuBarTemporaryMoveJournal
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("temporary-move-v1.json") }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("move-journal-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func expect(_ failure: J.Failure, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? J.Failure, failure, file: file, line: line) }
    }
    func testLifecycleSeparateFilenamePrivateModesAndDurableRepeatedSave() throws {
        let f = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        XCTAssertNil(try j.inspect())
        XCTAssertEqual(try j.persist(f.record, replacing: nil, boundTo: f.owner), f.record)
        let data = try Data(contentsOf: file)
        XCTAssertEqual(try j.persist(f.record, replacing: nil, boundTo: f.owner), f.record)
        XCTAssertEqual(try Data(contentsOf: file), data)
        var previous = f.record
        for phase in [MenuBarTemporaryMoveModel.Record.Phase.moved, .restorePrepared, .restored] {
            let next = f.phase(phase)
            XCTAssertEqual(try j.persist(next, replacing: previous, boundTo: f.owner), next)
            XCTAssertEqual(try J(directory: directory).load(boundTo: f.owner), next)
            previous = next
        }
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned-width.json").path))
        try j.clear(previous, boundTo: f.owner); try j.clear(previous, boundTo: f.owner)
        XCTAssertNil(try j.inspect())
    }
    func testStaleDuplicateTransactionAndBackwardPhaseCannotOverwriteResponsibility() throws {
        let f = try MenuBarMoveAdapterFixture(), other = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        expect(.stale) { _ = try j.persist(other.record, replacing: nil, boundTo: other.owner) }
        let moved = f.phase(.moved)
        _ = try j.persist(moved, replacing: f.record, boundTo: f.owner)
        expect(.stale) { _ = try j.persist(f.phase(.restored), replacing: f.record, boundTo: f.owner) }
        expect(.transition) { _ = try j.persist(f.record, replacing: moved, boundTo: f.owner) }
        expect(.transition) { try j.clear(moved, boundTo: f.owner) }
        expect(.stale) { try j.clear(f.phase(.restored), boundTo: f.owner) }
        XCTAssertEqual(try j.inspect(), moved)
    }
    func testBindingMismatchDoesNotEraseAndInspectStillReportsPendingResponsibility() throws {
        let f = try MenuBarMoveAdapterFixture(), changed = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        let before = try Data(contentsOf: file)
        expect(.identity) { _ = try j.load(boundTo: changed.owner) }
        expect(.identity) { _ = try j.persist(f.phase(.moved), replacing: f.record, boundTo: changed.owner) }
        expect(.identity) { try j.clear(f.phase(.restored), boundTo: changed.owner) }
        XCTAssertEqual(try j.inspect(), f.record); XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testMalformedTruncatedAndChecksumDamagedFilesCannotBeOverwrittenOrCleared() throws {
        let f = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        let valid = try Data(contentsOf: file)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        envelope["checksum"] = String(repeating: "0", count: 64)
        let invalid = [Data("{".utf8), Data(valid.prefix(valid.count / 2)), try JSONSerialization.data(withJSONObject: envelope)]
        for damage in invalid {
            try damage.write(to: file)
            expect(.corrupt) { _ = try j.inspect() }
            expect(.corrupt) { _ = try j.persist(f.record, replacing: nil, boundTo: f.owner) }
            expect(.corrupt) { try j.clear(f.phase(.restored), boundTo: f.owner) }
            XCTAssertEqual(try Data(contentsOf: file), damage)
        }
    }
    func testUnsupportedSchemaAndChangedPlanAreRejectedBeforeWrite() throws {
        let f = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        let unsupported = J.Record(schemaVersion: 2, transaction: f.record.transaction, plan: f.record.plan, phase: .prepared)
        expect(.corrupt) { _ = try j.persist(unsupported, replacing: nil, boundTo: f.owner) }
        expect(.transition) { _ = try j.persist(f.phase(.restored), replacing: nil, boundTo: f.owner) }
        XCTAssertNil(try j.inspect())
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        let p = f.record.plan
        let changed = MenuBarTemporaryMoveModel.Plan(original: p.original, reservationWidth: p.reservationWidth,
                                                     rightInset: 21, shownOrder: p.shownOrder)
        let inconsistent = J.Record(schemaVersion: 1, transaction: f.record.transaction, plan: changed, phase: .moved)
        expect(.transition) { _ = try j.persist(inconsistent, replacing: f.record, boundTo: f.owner) }
        XCTAssertEqual(try j.inspect(), f.record)
    }
    func testFailuresBeforeRenameKeepPreviousAndAfterRenameExposePossibleEffectRecord() throws {
        enum Injected: Error { case stop }
        let f = try MenuBarMoveAdapterFixture(), plain = J(directory: directory)
        _ = try plain.persist(f.record, replacing: nil, boundTo: f.owner)
        for point in [J.Point.temporaryCreated, .fileSynced] {
            let broken = J(directory: directory) { if $0 == point { throw Injected.stop } }
            XCTAssertThrowsError(try broken.persist(f.phase(.moved), replacing: f.record, boundTo: f.owner))
            XCTAssertEqual(try plain.inspect(), f.record)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".tmp") })
        }
        let afterRename = J(directory: directory) { if $0 == .renamed { throw Injected.stop } }
        XCTAssertThrowsError(try afterRename.persist(f.phase(.moved), replacing: f.record, boundTo: f.owner))
        XCTAssertEqual(try plain.inspect(), f.phase(.moved))
        // An unknown persistence outcome retries the same bytes, never the event.
        XCTAssertEqual(try plain.persist(f.phase(.moved), replacing: f.record, boundTo: f.owner), f.phase(.moved))
        let afterSync = J(directory: directory) { if $0 == .directorySynced { throw Injected.stop } }
        XCTAssertThrowsError(try afterSync.persist(f.phase(.restorePrepared), replacing: f.phase(.moved), boundTo: f.owner))
        XCTAssertEqual(try plain.inspect(), f.phase(.restorePrepared))
    }
    func testClearFailureAfterRemovalCanOnlyAcknowledgeRestoredAbsence() throws {
        enum Injected: Error { case stop }
        let f = try MenuBarMoveAdapterFixture(), plain = J(directory: directory)
        _ = try plain.persist(f.record, replacing: nil, boundTo: f.owner)
        _ = try plain.persist(f.phase(.restored), replacing: f.record, boundTo: f.owner)
        let broken = J(directory: directory) { if $0 == .removed { throw Injected.stop } }
        XCTAssertThrowsError(try broken.clear(f.phase(.restored), boundTo: f.owner))
        XCTAssertNil(try plain.inspect())
        try plain.clear(f.phase(.restored), boundTo: f.owner)
        _ = try plain.persist(f.record, replacing: nil, boundTo: f.owner)
        expect(.stale) { try plain.clear(f.phase(.restored), boundTo: f.owner) }
        XCTAssertEqual(try plain.inspect(), f.record)
    }
    func testFileSymlinkHardLinkOversizeAndPublicModeFailClosed() throws {
        let f = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        let other = directory.appendingPathComponent("other")
        try Data("outside evidence".utf8).write(to: other)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: other.path)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        expect(.unsafeFile) { _ = try j.inspect() }
        XCTAssertEqual(try String(contentsOf: other), "outside evidence")
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(link(other.path, file.path), 0)
        expect(.unsafeFile) { _ = try j.inspect() }
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(mkfifo(file.path, mode_t(0o600)), 0)
        expect(.unsafeFile) { _ = try j.inspect() }
        try FileManager.default.removeItem(at: file)
        try Data(repeating: 0, count: 524_289).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        expect(.tooLarge) { _ = try j.inspect() }
        try FileManager.default.removeItem(at: file)
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        expect(.unsafeFile) { _ = try j.inspect() }
    }
    func testDirectoryReplacementAndLockContentionCannotBypassStore() throws {
        let j = J(directory: directory)
        XCTAssertNil(try j.inspect())
        let lock = open(directory.appendingPathComponent(".temporary-move.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(lock, 0)
        defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        expect(.busy) { _ = try J(directory: directory).inspect() }
        XCTAssertEqual(flock(lock, LOCK_UN), 0)
        // Rename outside the leaf, keeping both old/new in the test parent.
        let sibling = directory.deletingLastPathComponent().appendingPathComponent("move-journal-old-\(UUID())")
        try FileManager.default.moveItem(at: directory, to: sibling)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        expect(.unsafeFile) { _ = try j.inspect() }
    }
    func testDirectoryAndLockSymlinksOrUnsafeModeAreRejectedWithoutRepair() throws {
        let other = directory.appendingPathComponent("other")
        try Data("untouched".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(".temporary-move.lock"), withDestinationURL: other)
        expect(.unsafeFile) { _ = try J(directory: directory).inspect() }
        XCTAssertEqual(try String(contentsOf: other), "untouched")
        let lockPath = directory.appendingPathComponent(".temporary-move.lock")
        try FileManager.default.removeItem(at: lockPath)
        XCTAssertEqual(mkfifo(lockPath.path, mode_t(0o600)), 0)
        expect(.unsafeFile) { _ = try J(directory: directory).inspect() }
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        expect(.unsafeFile) { _ = try J(directory: alias).inspect() }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        expect(.unsafeFile) { _ = try J(directory: directory).inspect() }
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o755) // Never chmod an unknown existing directory to pass.
    }
    func testOrphanTemporaryFileCannotReplacePendingRecoveryRecord() throws {
        let f = try MenuBarMoveAdapterFixture(), j = J(directory: directory)
        _ = try j.persist(f.record, replacing: nil, boundTo: f.owner)
        let orphan = directory.appendingPathComponent(".temporary-move-\(UUID()).tmp")
        try Data("interrupted write".utf8).write(to: orphan)
        XCTAssertEqual(try J(directory: directory).inspect(), f.record)
        XCTAssertEqual(try Data(contentsOf: orphan), Data("interrupted write".utf8))
        XCTAssertEqual(try j.inspect(), f.record)
    }
    func testModelKeepsPossibleEffectResponsibilityWhenPersistenceResultIsUnknown() throws {
        enum Injected: Error { case stop }
        let f = try MenuBarMoveAdapterFixture()
        let original = f.record.plan.original
        var a = original; a.sequence = 1; a.uptimeMilliseconds = 1000
        var model = MenuBarTemporaryMoveModel.Machine()
        let action = try model.begin(a, original, access: .init(ax: true, post: true, interferenceObservation: true), now: 1100, reservationWidth: 42)
        guard case .persist(let pending) = action else { return XCTFail("No model action before persistence") }
        let broken = J(directory: directory) { if $0 == .renamed { throw Injected.stop } }
        XCTAssertThrowsError(try broken.persist(pending, replacing: nil, boundTo: f.owner))
        model.invalidate(.journal)
        XCTAssertEqual(model.pending, pending); XCTAssertEqual(model.state, .needsRecovery)
        XCTAssertEqual(try J(directory: directory).inspect(), pending)
        XCTAssertFalse(MenuBarTemporaryMoveModel.backendEnabled)
    }
}
