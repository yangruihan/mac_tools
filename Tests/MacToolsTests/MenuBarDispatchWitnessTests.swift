// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarDispatchWitnessTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dispatch-proof-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func witness(_ record: MenuBarHiddenMoveModel.Record) throws -> MenuBarDispatchWitness {
        try MenuBarDispatchWitness(directory: directory, binding: .init(nonce: record.plan.original.owner.nonce,
            targetPID: record.plan.original.owner.target.pid, controllerPID: 321, controllerLaunch: 10,
            controllerSHA256: String(repeating: "c", count: 64)))
    }
    func testSealedNoDispatchCanClosePreparedWithoutPretendingReturnedOrMovingAfterSpaceChange() throws {
        let fixture = MenuBarHiddenMoveFixture(), record = try fixture.record(), w = try witness(MenuBarHiddenMoveFixture().record())
        XCTAssertEqual(try MenuBarHiddenMoveModel.inspectRecovery(record,
            first: fixture.sample(3, 1200, scope: fixture.scope(space: 8)),
            second: fixture.sample(4, 1300, scope: fixture.scope(space: 8)), now: 1300), .environmentChanged)
        // Separate fixture nonce is not accepted.
        XCTAssertThrowsError(try w.sealNoDispatch(record))
        let sub = directory.appendingPathComponent("matching")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let w2 = try MenuBarDispatchWitness(directory: sub, binding: .init(nonce: record.plan.original.owner.nonce, targetPID: record.plan.original.owner.target.pid,
            controllerPID: 321, controllerLaunch: 10, controllerSHA256: String(repeating: "c", count: 64)))
        let journal = MenuBarHiddenMoveJournal(directory: directory.appendingPathComponent("recovery"))
        _ = try journal.persist(record, replacing: nil, boundTo: record.plan.original.owner)
        let proof = try w2.sealNoDispatch(record)
        try journal.abortBeforeDispatch(record, proof: proof)
        XCTAssertNil(try journal.inspect())
        XCTAssertThrowsError(try w2.beforePost(route: "session", windowID: 2))
        let archived = directory.appendingPathComponent("recovery/aborted-before-dispatch-\(record.transaction).json")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: archived)) as! [String: Any]
        XCTAssertEqual(data["restored"] as? Bool, false)
        XCTAssertEqual(data["disposition"] as? String, "abortedBeforeDispatch")
    }
    func testPossiblePostMarkerEvenWithoutCompletionCounterCannotBecomeZeroProof() throws {
        let record = try MenuBarHiddenMoveFixture().record(), w = try witness(record)
        try w.beforePost(route: "session", windowID: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("dispatch-started.json").path))
        XCTAssertThrowsError(try w.sealNoDispatch(record))
    }
    func testGuardAndMarkerArePrivateAndExistingGuardCannotBeRearmed() throws {
        let record = try MenuBarHiddenMoveFixture().record(), w = try witness(record)
        XCTAssertThrowsError(try witness(record))
        try w.beforePost(route: "session", windowID: 2)
        for file in ["emission-guard-ready.json", "dispatch-started.json"] {
            let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file).path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testDanglingDispatchMarkerCannotBeMisreadAsZeroEffects() throws {
        let record = try MenuBarHiddenMoveFixture().record(), w = try witness(record)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("dispatch-started.json").path,
            withDestinationPath: directory.appendingPathComponent("missing").path)
        XCTAssertThrowsError(try w.sealNoDispatch(record))
    }
    func testReportedOriginIsCoarseAndNeverAnOwnGestureOrPhysicalHumanProof() {
        typealias A = MenuBarInputAttribution
        XCTAssertEqual(A.origin(sourcePID: 20, state: 1, selfPID: 20, tools: [30]), .controllerUnregistered)
        XCTAssertEqual(A.origin(sourcePID: 30, state: 1, selfPID: 20, tools: [30]), .knownToolUnregistered)
        XCTAssertEqual(A.origin(sourcePID: 0, state: 1, selfPID: 20, tools: []), .hidStateReported)
        XCTAssertEqual(A.origin(sourcePID: 0, state: 0, selfPID: 20, tools: []), .combinedStateReported)
        XCTAssertEqual(A.origin(sourcePID: 222, state: 12345, selfPID: 20, tools: []), .otherSourceReported)
    }
}
