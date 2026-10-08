// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarRealActionConsumptionTests: XCTestCase {
    var root: URL!, session: URL!, round: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("real-action-test-\(UUID())")
        session = root.appendingPathComponent("session"); round = root.appendingPathComponent("round-consumed")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func binding() -> MenuBarDispatchWitness.Binding {
        .init(nonce: UUID(), targetPID: 123, controllerPID: 234, controllerLaunch: 10, controllerSHA256: String(repeating: "a", count: 64))
    }
    func testRoundCannotBeReusedByAnotherSessionModeOrBinding() throws {
        let b = binding(); try MenuBarRealActionConsumption.consume(round: round, session: session, binding: b)
        let bytes = try Data(contentsOf: round)
        XCTAssertEqual(try JSONDecoder().decode(MenuBarDispatchWitness.Binding.self, from: bytes), b)
        XCTAssertEqual(try Data(contentsOf: session.appendingPathComponent("run-consumed")), bytes)
        let next = root.appendingPathComponent("another-session")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: false)
        XCTAssertThrowsError(try MenuBarRealActionConsumption.consume(round: round, session: next, binding: binding()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: next.appendingPathComponent("run-consumed").path))
        XCTAssertEqual(try Data(contentsOf: round), bytes)
        for file in [round!, session.appendingPathComponent("run-consumed")] {
            let a = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((a[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testSecondWriteFailureDoesNotReopenGlobalRoundOrOverwriteSession() throws {
        let occupied = session.appendingPathComponent("run-consumed"), old = Data("old attempt".utf8)
        try old.write(to: occupied)
        XCTAssertThrowsError(try MenuBarRealActionConsumption.consume(round: round, session: session, binding: binding()))
        XCTAssertEqual(try Data(contentsOf: occupied), old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: round.path))
        XCTAssertThrowsError(try MenuBarRealActionConsumption.consume(round: round, session: session, binding: binding()))
    }
    func testExistingDanglingRoundSymlinkIsNotVacant() throws {
        try FileManager.default.createSymbolicLink(at: round, withDestinationURL: root.appendingPathComponent("absent"))
        XCTAssertThrowsError(try MenuBarRealActionConsumption.consume(round: round, session: session, binding: binding()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.appendingPathComponent("run-consumed").path))
    }
    func testInvalidBindingCannotConsumeEitherFile() throws {
        let b = MenuBarDispatchWitness.Binding(nonce: UUID(), targetPID: 0, controllerPID: 234,
            controllerLaunch: 10, controllerSHA256: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try MenuBarRealActionConsumption.consume(round: round, session: session, binding: b))
        XCTAssertFalse(FileManager.default.fileExists(atPath: round.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.appendingPathComponent("run-consumed").path))
    }
}
