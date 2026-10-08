// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
@testable import MacTools

final class MenuBarHiddenMoveCoordinatorTests: XCTestCase {
    private typealias M = MenuBarHiddenMoveModel
    private typealias I = MenuBarMoveInterference
    private typealias J = MenuBarHiddenMoveJournal
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hidden-coordinator-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private final class Input: MenuBarHiddenInterferenceSource {
        var time: UInt64 = 1100, sequence: UInt64 = 0, epoch = UUID(), continuity = UUID()
        var reads = 0, incomplete = false, queue: [I.Event] = []
        var operationStop: MenuBarOperationStop?
        func bindOperationStop(_ stop: MenuBarOperationStop?) { operationStop = stop }
        var unavailable: I.Unavailable?
        func read() -> I.Availability {
            reads += 1; sequence += 1
            if let unavailable { return .unavailable(unavailable) }
            return .available(.init(sequence: sequence, uptimeMilliseconds: time, continuity: continuity,
                externalEpoch: epoch, coverage: incomplete ? [.keyboard] : I.requiredCoverage, buttons: [], keys: [], modifiers: 0))
        }
        func drainEvents() -> [I.Event] { let all = queue; queue = []; return all }
        func interrupt() {
            operationStop?.request(.externalInput)
            sequence += 1; epoch = UUID()
            queue.append(.init(sequence: sequence, uptimeMilliseconds: time, continuity: continuity, attribution: .unknown))
        }
    }
    private final class Driver: MenuBarHiddenMoveDriver {
        enum Failure: Error { case admission, possibleEffect, menuUnknown, visible }
        let fixture = MenuBarHiddenMoveFixture(), journal: J, input: Input
        var actions: [String] = [], samples = 0, restored = false
        var rejectAdmission = false, moveThrows = false, menuUnknown = false, visibleFails = false, interruptAfterMove = false
        var afterRestore: (() -> Void)?, afterOpen: (() -> Void)?, afterClose: (() -> Void)?
        var unresolvedDown = false
        func verifyNoUnresolvedDown() throws { if unresolvedDown { throw Failure.possibleEffect } }
        var operationStop: MenuBarOperationStop?
        func bindOperationStop(_ stop: MenuBarOperationStop?) { operationStop = stop }
        var failAt: String?
        var now: UInt64 { input.time }
        init(_ journal: J, _ input: Input) { self.journal = journal; self.input = input }
        func admit(_ plan: M.Plan) throws { if rejectAdmission { throw Failure.admission } }
        func samplePair() throws -> (M.Snapshot, M.Snapshot) {
            samples += 1
            return restored ? (fixture.sample(3, input.time - 100), fixture.sample(4, input.time)) : (fixture.sample(1, input.time - 100), fixture.sample(2, input.time))
        }
        func moveToVisible(_ plan: M.Plan, lease: I.Lease) throws {
            XCTAssertEqual(try journal.inspect()?.phase, .prepared)
            actions.append("move")
            if interruptAfterMove { input.interrupt() }
            if moveThrows { throw Failure.possibleEffect }
        }
        func verifyVisible(_ plan: M.Plan) throws { actions.append("verifyVisible"); if visibleFails { throw Failure.visible } }
        func openOwnedMenu(_ owner: M.Owner, lease: I.Lease) throws {
            actions.append("open"); afterOpen?(); if failAt == "open" { throw Failure.possibleEffect }
        }
        func cancelOwnedMenu(_ owner: M.Owner) throws {
            actions.append("cancelMenu"); afterClose?(); if failAt == "cancelMenu" { throw Failure.possibleEffect }
        }
        func verifyMenuClosed(_ owner: M.Owner) throws { actions.append("verifyClosed"); if menuUnknown { throw Failure.menuUnknown } }
        func restore(_ plan: M.Plan, lease: I.Lease) throws {
            XCTAssertEqual(try journal.inspect()?.phase, .restorePrepared)
            actions.append("restore"); restored = true; input.time += 200
            if failAt == "restore" { throw Failure.possibleEffect }
            afterRestore?()
        }
    }
    func testDefaultPolicyDoesNothingBeforeJournalOrInputAndUnprovenAdmissionStops() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.run())
        XCTAssertEqual(driver.samples, 0); XCTAssertEqual(input.reads, 0); XCTAssertTrue(driver.actions.isEmpty)
        driver.rejectAdmission = true
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertNil(try j.inspect()); XCTAssertEqual(input.reads, 0); XCTAssertTrue(driver.actions.isEmpty)
    }
    func testIsolatedFakeFullLoopPersistsBeforeBothMovesAndClearsOnlyAfterTwoReturnSamples() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        try c.run(.isolatedOwnedFixture)
        XCTAssertEqual(driver.actions, ["move", "verifyVisible", "open", "cancelMenu", "verifyClosed", "restore"])
        XCTAssertNil(try j.inspect()); XCTAssertNil(c.retained); XCTAssertFalse(c.active)
    }
    #if !OWNED_LIVE_CONTROLLER
    func testAttemptAccountingOccursAfterAdmissionAndRecoveryBeforeAnyGateOrMove() throws {
        enum Disk: Error { case uncertain }
        for fault in ["admission", "recovery", "cancel", "consumption"] {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            driver.rejectAdmission = fault == "admission"
            if fault == "recovery" {
                let record = try driver.fixture.record()
                _ = try j.persist(record, replacing: nil, boundTo: record.plan.original.owner)
            }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            var consumed = 0
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, consumeAction: {
                consumed += 1
                XCTAssertEqual(driver.samples, 1); XCTAssertEqual(input.reads, 0)
                XCTAssertNil(try j.inspect()); XCTAssertTrue(driver.actions.isEmpty)
                throw Disk.uncertain
            }, cancelled: { fault == "cancel" }))
            XCTAssertEqual(consumed, fault == "consumption" ? 1 : 0)
            XCTAssertEqual(input.reads, 0); XCTAssertTrue(driver.actions.isEmpty)
        }
    }
    #endif
    func testPersistenceUnknownOutcomeNeverDispatchesAndNextCallRefusesPendingRecord() throws {
        enum Injected: Error { case stop }
        let broken = J(directory: directory) { if $0 == .renamed { throw Injected.stop } }
        let input = Input(), driver = Driver(broken, input)
        let c = MenuBarHiddenMoveCoordinator(journal: broken, input: input, driver: driver)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertEqual(try J(directory: directory).inspect()?.phase, .prepared)
        XCTAssertTrue(driver.actions.isEmpty)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertTrue(driver.actions.isEmpty)
    }
    func testPossibleMoveEffectKeepsPreparedAndRestartNeverReplays() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        driver.moveThrows = true
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertEqual(try j.inspect()?.phase, .prepared); XCTAssertEqual(driver.actions, ["move"])
        let inspection = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertEqual(try inspection.inspectRecovery(), .retained)
        XCTAssertEqual(driver.actions, ["move"]); XCTAssertNotNil(inspection.retained)
    }
    func testUnknownHumanInputOrVisibleFailureRetainsMovedWithoutMenuOrReturn() throws {
        for human in [true, false] {
            let sub = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let j = J(directory: sub), input = Input(), driver = Driver(j, input)
            driver.interruptAfterMove = human; driver.visibleFails = !human
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
            XCTAssertEqual(try j.inspect()?.phase, .moved)
            XCTAssertFalse(driver.actions.contains("open")); XCTAssertFalse(driver.actions.contains("restore"))
        }
    }
    func testUnknownMenuStateAndCancelAfterMoveCannotAcknowledgeRestoration() throws {
        for menu in [true, false] {
            let sub = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let j = J(directory: sub), input = Input(), driver = Driver(j, input)
            driver.menuUnknown = menu
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, cancelled: { !menu && driver.actions.contains("move") }))
            XCTAssertEqual(try j.inspect()?.phase, .moved); XCTAssertFalse(driver.actions.contains("restore"))
        }
    }
    func testIncompleteInputCoverageCannotPrepareOrSend() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        input.incomplete = true
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertNil(try j.inspect()); XCTAssertTrue(driver.actions.isEmpty)
    }
    func testExplicitRecoveryClearsFreshOriginalProofWithoutMouseOrInputLease() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        let record = try driver.fixture.record()
        _ = try j.persist(record, replacing: nil, boundTo: record.plan.original.owner)
        driver.restored = true; input.time += 200
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        try c.restoreRetained(.isolatedOwnedFixture)
        XCTAssertNil(try j.inspect()); XCTAssertTrue(driver.actions.isEmpty); XCTAssertEqual(input.reads, 0)
    }
    func testExplicitRecoveryDefaultDisabledAndIncompleteInputNeverDispatchInverse() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        let prepared = try driver.fixture.record()
        var moved = prepared; moved.phase = .moved
        _ = try j.persist(prepared, replacing: nil, boundTo: prepared.plan.original.owner)
        _ = try j.persist(moved, replacing: prepared, boundTo: moved.plan.original.owner)
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.restoreRetained()); XCTAssertEqual(driver.samples, 0)
        input.incomplete = true
        XCTAssertThrowsError(try c.restoreRetained(.isolatedOwnedFixture))
        XCTAssertFalse(driver.actions.contains("restore")); XCTAssertEqual(try j.inspect()?.phase, .moved)
    }

    func testInterferenceLossAndEpochChangeDuringReturnRetainRestorePrepared() throws {
        for fault in 0..<4 {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            driver.afterRestore = {
                if fault == 0 { input.interrupt() }
                if fault == 1 { input.unavailable = .sourceLost }
                if fault == 2 { input.epoch = UUID() }
                if fault == 3 { input.continuity = UUID() }
            }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
            XCTAssertEqual(driver.actions.filter { $0 == "restore" }.count, 1)
            XCTAssertEqual(try j.inspect()?.phase, .restorePrepared)
            XCTAssertNotNil(c.retained)
        }
    }
    func testCancellationDuringReturnAndExpiredTransactionCannotClearJournal() throws {
        for expire in [false, true] {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            if expire { driver.afterRestore = { input.time = 6500 } }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, cancelled: { !expire && driver.restored }))
            XCTAssertEqual(try j.inspect()?.phase, .restorePrepared)
        }
    }
    func testExplicitInverseRecoveryCannotClearAfterListenerLossDuringReturn() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        let prepared = try driver.fixture.record(); var moved = prepared; moved.phase = .moved
        _ = try j.persist(prepared, replacing: nil, boundTo: prepared.plan.original.owner)
        _ = try j.persist(moved, replacing: prepared, boundTo: moved.plan.original.owner)
        driver.afterRestore = { input.unavailable = .sourceLost }
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.restoreRetained(.isolatedOwnedFixture))
        XCTAssertEqual(driver.actions.filter { $0 == "restore" }.count, 1)
        XCTAssertEqual(try j.inspect()?.phase, .restorePrepared)
    }

    func testReturnEvidenceMustBeDurableBeforeJournalClear() throws {
        for failStage in ["returned", "complete", "none"] {
            let sub = directory.appendingPathComponent(UUID().uuidString)
            let j = J(directory: sub), input = Input(), driver = Driver(j, input)
            var returnStored = false, stages: [String] = []
            enum Disk: Error { case failed }
            let evidence = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent(UUID().uuidString),
                nonce: driver.fixture.original.owner.nonce, controllerPID: 123) { bytes, file in
                let record = try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: bytes)
                stages.append(record.stage)
                if ["returned", "complete"].contains(record.stage) { XCTAssertEqual(try j.inspect()?.phase, .restored) }
                if record.stage == failStage { throw Disk.failed }
                try MenuBarDispatchWitness.writeNew(bytes, to: file)
                if record.stage == "returned" { returnStored = true }
            }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: evidence)
            if failStage == "none" {
                try c.run(.isolatedOwnedFixture); XCTAssertTrue(returnStored)
                XCTAssertNil(try j.inspect()); XCTAssertTrue(c.completedFullCycle)
                XCTAssertEqual(stages, ["original-plan", "prepared", "moved", "restore-prepared", "returned", "complete"])
            } else {
                XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
                XCTAssertEqual(try j.inspect()?.phase, .restored); XCTAssertFalse(c.completedFullCycle)
                XCTAssertTrue(evidence.poisoned)
            }
        }
    }
    func testActivityDuringReturnEvidenceWriteRetainsJournal() throws {
        let j = J(directory: directory.appendingPathComponent("recovery")), input = Input(), driver = Driver(j, input)
        let evidence = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent("stages"),
            nonce: driver.fixture.original.owner.nonce, controllerPID: 123) { bytes, file in
            try MenuBarDispatchWitness.writeNew(bytes, to: file)
            let record = try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: bytes)
            if record.stage == "returned" { input.interrupt() }
        }
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: evidence)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture)); XCTAssertEqual(try j.inspect()?.phase, .restored)
        XCTAssertFalse(c.completedFullCycle)
    }
    func testRealPermitCoordinatorGateAndDurableJournalIntegrateWithoutNativeSender() throws {
        for changedGate in [false, true] {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            let evidence = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent(UUID().uuidString),
                nonce: driver.fixture.original.owner.nonce, controllerPID: 123)
            let h = try MenuBarRealLocalAuthorizationTests.Harness(fixture: driver.fixture, evidence: evidence)
            h.continuity = input.continuity; h.epoch = input.epoch
            try h.start(); try h.finish(); let permit = try h.broker.permit(); input.time = h.time / 1_000_000
            if changedGate { input.epoch = UUID() }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: evidence)
            if changedGate {
                XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, startPermit: permit))
                XCTAssertTrue(driver.actions.isEmpty); XCTAssertNil(try j.inspect())
            } else {
                try c.run(.isolatedOwnedFixture, startPermit: permit)
                XCTAssertEqual(driver.actions, ["move", "verifyVisible", "open", "cancelMenu", "verifyClosed", "restore"])
                XCTAssertTrue(c.completedFullCycle); XCTAssertNil(try j.inspect())
                XCTAssertTrue(permit.consumed); XCTAssertFalse(h.broker.monitor.diagnostics().monitoringHealthy)
            }
        }
    }

    func testExplicitRecoveryHonorsCancellationBudgetAndPoisonedEvidence() throws {
        for fault in 0..<3 {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            let prepared = try driver.fixture.record(); var moved = prepared; moved.phase = .moved
            _ = try j.persist(prepared, replacing: nil, boundTo: prepared.plan.original.owner)
            _ = try j.persist(moved, replacing: prepared, boundTo: moved.plan.original.owner)
            let evidence = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent(UUID().uuidString),
                nonce: driver.fixture.original.owner.nonce, controllerPID: 123)
            if fault == 0 { driver.afterRestore = { input.time = 7000 } }
            if fault == 2 { XCTAssertThrowsError(try evidence.append("bad", ["value": Double.nan])) }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: evidence)
            XCTAssertThrowsError(try c.restoreRetained(.isolatedOwnedFixture, cancelled: { fault == 1 && driver.restored }))
            XCTAssertNotNil(try j.inspect()); XCTAssertFalse(c.completedFullCycle)
            XCTAssertEqual(driver.actions.filter { $0 == "restore" }.count, fault == 2 ? 0 : 1)
        }
    }
    func testMenuOpenCloseAndInverseMayHaveEffectButFailureCannotAdvanceOrClear() throws {
        for point in ["open", "cancelMenu", "restore"] {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            driver.failAt = point
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
            XCTAssertEqual(driver.actions.last, point)
            XCTAssertEqual(try j.inspect()?.phase, point == "restore" ? .restorePrepared : .moved)
            XCTAssertFalse(c.completedFullCycle); XCTAssertFalse(c.active)
            let before = driver.actions
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
            XCTAssertEqual(driver.actions, before) // No implicit menu retry/inverse.
        }
    }
    func testEveryDurableStageFailureStopsAtItsLastProvenJournalPhase() throws {
        let points: [(String, M.Record.Phase?, [String])] = [
            ("original-plan", nil, []), ("prepared", .prepared, []), ("moved", .moved, ["move"]),
            ("restore-prepared", .restorePrepared, ["move", "verifyVisible", "open", "cancelMenu", "verifyClosed"]),
            ("returned", .restored, ["move", "verifyVisible", "open", "cancelMenu", "verifyClosed", "restore"]),
            ("complete", .restored, ["move", "verifyVisible", "open", "cancelMenu", "verifyClosed", "restore"])]
        enum Disk: Error { case uncertain }
        for (stage, phase, actions) in points {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            let recorder = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent(UUID().uuidString),
                nonce: driver.fixture.original.owner.nonce, controllerPID: 123) { data, file in
                try MenuBarDispatchWitness.writeNew(data, to: file)
                if try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: data).stage == stage { throw Disk.uncertain }
            }
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: recorder)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture)); XCTAssertEqual(try j.inspect()?.phase, phase)
            XCTAssertEqual(driver.actions, actions); XCTAssertTrue(recorder.poisoned); XCTAssertFalse(c.completedFullCycle)
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture)); XCTAssertEqual(driver.actions, actions)
        }
    }
    func testFailedHandoffWriteCannotStopOverlappingMonitorOrReachMove() throws {
        let j = J(directory: directory.appendingPathComponent("recovery")), input = Input(), driver = Driver(j, input)
        enum Disk: Error { case uncertain }
        let recorder = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent("stages"),
            nonce: driver.fixture.original.owner.nonce, controllerPID: 123) { data, file in
            try MenuBarDispatchWitness.writeNew(data, to: file)
            if try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: data).stage == "real-local-handoff" { throw Disk.uncertain }
        }
        let h = try MenuBarRealLocalAuthorizationTests.Harness(fixture: driver.fixture, evidence: recorder)
        h.continuity = input.continuity; h.epoch = input.epoch
        try h.start(); try h.finish(); let permit = try h.broker.permit(); input.time = h.time / 1_000_000
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: recorder)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, startPermit: permit))
        XCTAssertTrue(permit.consumed); XCTAssertFalse(permit.handedOff)
        XCTAssertTrue(h.broker.monitor.diagnostics().monitoringHealthy)
        XCTAssertTrue(driver.actions.isEmpty); XCTAssertNil(try j.inspect()); XCTAssertTrue(recorder.poisoned)
        XCTAssertThrowsError(try permit.check(driver.fixture.plan()))
    }

    func testCancellationExternalInputAndMonitorLossAfterOpenBlockMenuCloseAndInverse() throws {
        for fault in 0..<3 {
            let j = J(directory: directory.appendingPathComponent(UUID().uuidString)), input = Input(), driver = Driver(j, input)
            let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
            var cancelled = false
            driver.afterOpen = {
                XCTAssertTrue(input.operationStop === driver.operationStop)
                XCTAssertTrue(driver.operationStop === c.operationStop)
                if fault == 0 { cancelled = true }
                if fault == 1 { input.interrupt() }
                if fault == 2 { input.unavailable = .sourceLost }
            }
            XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, cancelled: { cancelled }))
            XCTAssertTrue(driver.actions.contains("open"))
            XCTAssertFalse(driver.actions.contains("cancelMenu")); XCTAssertFalse(driver.actions.contains("restore"))
            XCTAssertEqual(try j.inspect()?.phase, .moved)
            XCTAssertNotNil(c.operationStop.snapshot.reason)
            XCTAssertNil(input.operationStop); XCTAssertNil(driver.operationStop)
        }
    }
    func testTakeoverDuringMenuClosePreventsRestoreAndKeepsJournal() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        driver.afterClose = { input.interrupt() }
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertTrue(driver.actions.contains("cancelMenu")); XCTAssertFalse(driver.actions.contains("restore"))
        XCTAssertEqual(try j.inspect()?.phase, .moved)
    }
    func testRestorePreparedWriteCancellationBlocksInverse() throws {
        let j = J(directory: directory.appendingPathComponent("recovery")), input = Input(), driver = Driver(j, input)
        var cancelled = false
        let evidence = try MenuBarMoveStageRecorder(directory: directory.appendingPathComponent("stages"),
            nonce: driver.fixture.original.owner.nonce, controllerPID: 123) { bytes, file in
            try MenuBarDispatchWitness.writeNew(bytes, to: file)
            if try JSONDecoder().decode(MenuBarMoveStageRecorder.Record.self, from: bytes).stage == "restore-prepared" { cancelled = true }
        }
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver, evidence: evidence)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture, cancelled: { cancelled }))
        XCTAssertFalse(driver.actions.contains("restore"))
        XCTAssertEqual(try j.inspect()?.phase, .restorePrepared)
        XCTAssertEqual(c.operationStop.snapshot.reason, .cancelled)
    }

    func testOriginalGeometryCannotClearUnresolvedDownResponsibility() throws {
        let j = J(directory: directory), input = Input(), driver = Driver(j, input)
        driver.moveThrows = true; driver.unresolvedDown = true
        let c = MenuBarHiddenMoveCoordinator(journal: j, input: input, driver: driver)
        XCTAssertThrowsError(try c.run(.isolatedOwnedFixture))
        XCTAssertEqual(try j.inspect()?.phase, .prepared)
        driver.restored = true // fresh original geometry is not release proof
        input.time += 200
        XCTAssertThrowsError(try c.restoreRetained(.isolatedOwnedFixture))
        XCTAssertEqual(try j.inspect()?.phase, .prepared)
        XCTAssertNotNil(c.retained); XCTAssertFalse(c.completedFullCycle)
        XCTAssertFalse(driver.actions.contains("restore"))
    }
}
