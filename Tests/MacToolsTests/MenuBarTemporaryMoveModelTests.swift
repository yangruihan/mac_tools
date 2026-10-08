import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarTemporaryMoveModelTests: XCTestCase {
    private typealias M = MenuBarTemporaryMoveModel
    private struct Fixture {
        let access = M.Access(ax: true, post: true, interferenceObservation: true)
        let original: M.Sample
        init() {
            func identity(_ id: UInt32) -> MenuBarRecordedTarget {
                let app = MenuBarApplicationIdentity(bundleID: id == 2 ? "com.ryanai.mactools.nativetargets" : "model.peer.\(id)",
                    bundlePath: "/Model\(id).app", launch: 100 + Double(id))
                return MenuBarRecordedTarget(MenuBarStatusTarget(id: id, pid: 20 + Int32(id),
                    frame: .zero, onScreen: true, application: app))
            }
            let windows = zip([UInt32(1), 2, 3, 4, 5, 6], [500.0, 600, 700, 1050, 1550, 1650]).map { id, x in
                M.Window(identity: identity(id), frame: CGRect(x: x, y: 0, width: 40, height: 37),
                    button: CGRect(x: x + 4, y: 6.5, width: 32, height: 24), onScreen: .ordered,
                    listedOnScreen: true, alpha: 1, ownerOcclusionVisible: id == 2 ? true : nil)
            }
            let scope = M.Scope(continuity: UUID(), spaceEpoch: UUID(), displayUUID: "model-display", displayID: 1,
                scale: 2, rotation: 0, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                leftSafe: CGRect(x: 0, y: 0, width: 771, height: 32), rightSafe: CGRect(x: 956, y: 0, width: 772, height: 32),
                frontPID: 10, frontApplication: MenuBarApplicationIdentity(bundleID: "model.front", bundlePath: "/ModelFront.app", launch: 10))
            original = M.Sample(sequence: 1, uptimeMilliseconds: 1000, scope: scope,
                owner: M.Owner(nonce: UUID(), itemInstance: UUID(), itemKey: "mactools_native_acceptance_T",
                    signedIdentifier: "com.ryanai.mactools.nativetargets", team: "model-team", codeHash: "model-code-hash", target: windows[1].identity),
                windows: windows, recovery: windows[5].identity, applicationMenu: CGRect(x: 0, y: 0, width: 470, height: 32),
                overlays: [], interface: .closed, inputIdle: true, interferenceEpoch: UUID())
        }
        func sample(_ sequence: UInt64, _ time: UInt64, moved: Bool = false,
                    interface: M.Interface = .closed, scope: M.Scope? = nil) -> M.Sample {
            var s = M.Sample(sequence: sequence, uptimeMilliseconds: time, scope: scope ?? original.scope,
                owner: original.owner, windows: original.windows, recovery: original.recovery,
                applicationMenu: original.applicationMenu, overlays: [], interface: interface, inputIdle: true,
                interferenceEpoch: original.interferenceEpoch)
            if moved {
                var target = s.windows.remove(at: 1)
                target.frame.origin.x = 1608; target.button.origin.x = 1612
                for i in 1...3 { s.windows[i].frame.origin.x -= 42; s.windows[i].button.origin.x -= 42 }
                s.windows.insert(target, at: 4)
            }
            return s
        }
        func changedScope(continuity: UUID? = nil, space: UUID? = nil, display: String? = nil, scale: Double? = nil) -> M.Scope {
            let s = original.scope
            return M.Scope(continuity: continuity ?? s.continuity, spaceEpoch: space ?? s.spaceEpoch,
                displayUUID: display ?? s.displayUUID, displayID: s.displayID, scale: scale ?? s.scale,
                rotation: s.rotation, frame: s.frame, leftSafe: s.leftSafe, rightSafe: s.rightSafe,
                frontPID: s.frontPID, frontApplication: s.frontApplication)
        }
    }
    private func record(_ action: M.Action) throws -> M.Record {
        guard case .persist(let record) = action else { XCTFail("Expected persistence before a modeled action"); throw M.Failure.phase }
        return record
    }
    private func begin(_ f: Fixture, _ machine: inout M.Machine) throws -> M.Record {
        try record(machine.begin(f.sample(1, 1000), f.sample(2, 1100), access: f.access, now: 1100, reservationWidth: 42))
    }
    private func show(_ f: Fixture, _ machine: inout M.Machine) throws -> M.Record {
        let prepared = try begin(f, &machine)
        XCTAssertEqual(try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200), .modelRelocateOnce)
        XCTAssertEqual(try machine.observedMove(f.sample(4, 1300, moved: true), access: f.access, now: 1300), .none)
        let moved = try record(machine.observedMove(f.sample(5, 1400, moved: true), access: f.access, now: 1400))
        XCTAssertEqual(try machine.persisted(moved, live: f.sample(6, 1500, moved: true), access: f.access, now: 1500), .none)
        return moved
    }
    private func expect(_ failure: M.Failure, _ work: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try work(), file: file, line: line) { XCTAssertEqual($0 as? M.Failure, failure, file: file, line: line) }
    }
    func testFullModelTransactionPersistsBeforeBothMovesAndAfterVerifiedRestore() throws {
        let f = Fixture(); var machine = M.Machine()
        XCTAssertFalse(M.backendEnabled)
        let moved = try show(f, &machine)
        XCTAssertEqual(moved.phase, .moved); XCTAssertEqual(machine.state, .shown)
        XCTAssertEqual(moved.plan.shownOrder.map(\.windowID), [1, 3, 4, 5, 2, 6])
        let returning = try record(machine.requestReturn(f.sample(7, 1600, moved: true), f.sample(8, 1700, moved: true), access: f.access, now: 1700))
        XCTAssertEqual(returning.phase, .restorePrepared)
        XCTAssertEqual(try machine.persisted(returning, live: f.sample(9, 1800, moved: true), access: f.access, now: 1800), .modelRestoreOnce)
        XCTAssertEqual(try machine.observedRestore(f.sample(10, 1900), access: f.access, now: 1900), .none)
        let restored = try record(machine.observedRestore(f.sample(11, 2000), access: f.access, now: 2000))
        XCTAssertEqual(restored.phase, .restored)
        XCTAssertEqual(try machine.persisted(restored, live: f.sample(12, 2100), access: f.access, now: 2100), .clearJournal)
        XCTAssertNotNil(machine.pending)
        try machine.cleared(transaction: restored.transaction)
        XCTAssertEqual(machine.state, .idle); XCTAssertNil(machine.pending)
        for value in [moved, returning, restored] {
            XCTAssertEqual(try JSONDecoder().decode(M.Record.self, from: JSONEncoder().encode(value)), value)
        }
    }
    func testActualSavedOwnerNegativeVisibilityCannotPrepareAMove() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/evidence/menu-bar-native-owner-window-2026-10-03/representative-owner-sample.json")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let models = try XCTUnwrap(saved["modelsBefore"] as? [[String: Any]])
        let t = try XCTUnwrap(models.first(where: { $0["title"] as? String == "T" }))
        XCTAssertEqual(t["itemVisible"] as? Bool, true); XCTAssertEqual(t["windowVisible"] as? Bool, true)
        XCTAssertEqual(t["windowOnActiveSpace"] as? Bool, true); XCTAssertEqual(t["windowOcclusionVisible"] as? Bool, false)
        let cg = try XCTUnwrap(saved["cgAllBefore"] as? [String: Any])
        let rows = try XCTUnwrap(cg["ownRows"] as? [[String: Any]])
        XCTAssertTrue(rows.allSatisfy { ($0["kCGWindowIsOnscreen"] as? [String: Any])?["present"] as? Bool == false })
        let f = Fixture(); var a = f.sample(1, 1000), b = f.sample(2, 1100)
        // Project the actual negative flags into the isolated model inventory;
        // no synthetic positive binding is asserted for the saved desktop.
        for s in 0...1 {
            if s == 0 { a.windows[1].onScreen = .missing; a.windows[1].listedOnScreen = false; a.windows[1].ownerOcclusionVisible = false }
            else { b.windows[1].onScreen = .missing; b.windows[1].listedOnScreen = false; b.windows[1].ownerOcclusionVisible = false }
        }
        var machine = M.Machine()
        expect(.targetNotVisible) { _ = try machine.begin(a, b, access: f.access, now: 1100, reservationWidth: 42) }
        XCTAssertNil(machine.pending); XCTAssertEqual(machine.state, .idle)
    }
    func testMissingEachExistingAccessCapabilityRefusesBeforeJournal() {
        let f = Fixture()
        for access in [M.Access(ax: false, post: true, interferenceObservation: true),
                       M.Access(ax: true, post: false, interferenceObservation: true),
                       M.Access(ax: true, post: true, interferenceObservation: false)] {
            var machine = M.Machine()
            expect(.permissions) { _ = try machine.begin(f.sample(1, 1000), f.sample(2, 1100), access: access, now: 1100, reservationWidth: 42) }
            XCTAssertNil(machine.pending)
        }
    }
    func testRightCapacityIncludesReservationAndTwentyPointInset() {
        let f = Fixture(); var a = f.sample(1, 1000), b = f.sample(2, 1100)
        a.windows[3].frame.origin.x = 980; a.windows[3].button.origin.x = 984
        b.windows = a.windows
        var machine = M.Machine()
        expect(.noCapacity) { _ = try machine.begin(a, b, access: f.access, now: 1100, reservationWidth: 42) }
        XCTAssertNil(machine.pending)
    }
    func testUnknownHiddenPeerIsNotRemovedToProveOrder() {
        let f = Fixture(); var a = f.sample(1, 1000), b = f.sample(2, 1100)
        a.windows[0].onScreen = .missing; a.windows[0].listedOnScreen = false; b.windows = a.windows
        var machine = M.Machine()
        expect(.incompleteOrder) { _ = try machine.begin(a, b, access: f.access, now: 1100, reservationWidth: 42) }
        XCTAssertNil(machine.pending)
    }
    func testNonfiniteAlphaAndOpenMenuCannotPrepare() {
        let f = Fixture(); var a = f.sample(1, 1000), b = f.sample(2, 1100)
        a.windows[1].alpha = .infinity; b.windows = a.windows
        var machine = M.Machine()
        expect(.targetNotVisible) { _ = try machine.begin(a, b, access: f.access, now: 1100, reservationWidth: 42) }
        for menu in [M.Interface.open, .unknown] {
            var m = M.Machine()
            expect(.recoveryAmbiguous) { _ = try m.begin(f.sample(1, 1000, interface: menu), f.sample(2, 1100, interface: menu), access: f.access, now: 1100, reservationWidth: 42) }
            XCTAssertNil(m.pending)
        }
    }
    func testUnstableOrRepeatedSamplesNeverPrepare() {
        let f = Fixture()
        var changed = f.sample(2, 1100); changed.windows[1].frame.origin.x += 1; changed.windows[1].button.origin.x += 1
        for b in [f.sample(1, 1100), f.sample(2, 1050), changed] {
            var machine = M.Machine()
            expect(.unstable) { _ = try machine.begin(f.sample(1, 1000), b, access: f.access, now: 1100, reservationWidth: 42) }
            XCTAssertNil(machine.pending)
        }
    }
    func testStalePersistenceReceiptAndDuplicateModelMoveDoNotReplay() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        let stale = M.Record(schemaVersion: 1, transaction: UUID(), plan: prepared.plan, phase: .prepared)
        expect(.staleReceipt) { _ = try machine.persisted(stale, live: f.sample(3, 1200), access: f.access, now: 1200) }
        XCTAssertEqual(machine.state, .prepared)
        XCTAssertEqual(try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200), .modelRelocateOnce)
        expect(.phase) { _ = try machine.persisted(prepared, live: f.sample(4, 1300), access: f.access, now: 1300) }
        XCTAssertEqual(machine.state, .needsRecovery); XCTAssertNotNil(machine.pending)
    }
    func testPostMoveRequiresTwoPositiveSamplesAndKeepsPreparedRecoveryOnFailure() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        _ = try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200)
        XCTAssertEqual(try machine.observedMove(f.sample(4, 1300, moved: true), access: f.access, now: 1300), .none)
        var bad = f.sample(5, 1400, moved: true); bad.windows[4].onScreen = .missing; bad.windows[4].listedOnScreen = false
        expect(.targetNotVisible) { _ = try machine.observedMove(bad, access: f.access, now: 1400) }
        XCTAssertEqual(machine.pending?.phase, .prepared); XCTAssertEqual(machine.state, .needsRecovery)
    }
    func testUnexpectedNonTargetPermutationIsRejectedEvenWithOrderedPixels() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        _ = try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200)
        var bad = f.sample(4, 1300, moved: true)
        let a = bad.windows[2], b = bad.windows[3]
        bad.windows[2] = M.Window(identity: b.identity, frame: a.frame, button: a.button, onScreen: a.onScreen, listedOnScreen: true, alpha: 1)
        bad.windows[3] = M.Window(identity: a.identity, frame: b.frame, button: b.button, onScreen: b.onScreen, listedOnScreen: true, alpha: 1)
        expect(.unexpectedOrder) { _ = try machine.observedMove(bad, access: f.access, now: 1300) }
        XCTAssertEqual(machine.state, .needsRecovery); XCTAssertNotNil(machine.pending)
    }
    func testMenuUnknownDoesNotAuthorizeReturnAndMixedCloseSamplesFail() throws {
        let f = Fixture(); var machine = M.Machine(); _ = try show(f, &machine)
        XCTAssertEqual(try machine.requestReturn(f.sample(7, 1600, moved: true, interface: .unknown),
            f.sample(8, 1700, moved: true, interface: .unknown), access: f.access, now: 1700), .observeInterface)
        XCTAssertEqual(machine.state, .waitingForClose); XCTAssertEqual(machine.pending?.phase, .moved)
        expect(.unstable) { _ = try machine.requestReturn(f.sample(9, 1800, moved: true),
            f.sample(10, 1900, moved: true, interface: .unknown), access: f.access, now: 1900) }
        let returning = try record(machine.requestReturn(f.sample(11, 2000, moved: true), f.sample(12, 2100, moved: true), access: f.access, now: 2100))
        XCTAssertEqual(returning.phase, .restorePrepared)
    }
    func testOrderedPeerPartlyPushedIntoNotchCannotProveMove() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        _ = try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200)
        var bad = f.sample(4, 1300, moved: true)
        bad.windows[2].frame.origin.x = 950; bad.windows[2].button.origin.x = 954
        expect(.incompleteOrder) { _ = try machine.observedMove(bad, access: f.access, now: 1300) }
        XCTAssertEqual(machine.pending?.phase, .prepared); XCTAssertEqual(machine.state, .needsRecovery)
    }
    func testShrinkingTargetButtonCannotManufactureSlotProof() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        _ = try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200)
        var bad = f.sample(4, 1300, moved: true); bad.windows[4].button.size.width = 4
        expect(.invalidGeometry) { _ = try machine.observedMove(bad, access: f.access, now: 1300) }
        XCTAssertEqual(machine.pending?.phase, .prepared); XCTAssertEqual(machine.state, .needsRecovery)
    }
    func testDeadlinePreservesResponsibilityAndOriginalProofCanSettleWithoutReturnMove() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        _ = try machine.persisted(prepared, live: f.sample(3, 1200), access: f.access, now: 1200)
        expect(.deadline) { _ = try machine.observedMove(f.sample(4, 7000, moved: true), access: f.access, now: 7000) }
        XCTAssertEqual(machine.state, .needsRecovery)
        let restored = try record(machine.requestReturn(f.sample(5, 7100), f.sample(6, 7200), access: f.access, now: 7200))
        XCTAssertEqual(restored.phase, .restored)
        XCTAssertEqual(try machine.persisted(restored, live: f.sample(7, 7300), access: f.access, now: 7300), .clearJournal)
    }
    func testObserverLossSpaceDisplayOrScaleChangeCannotReplayCrashRecovery() throws {
        let f = Fixture(); var machine = M.Machine(); let moved = try show(f, &machine)
        for scope in [f.changedScope(continuity: UUID()), f.changedScope(space: UUID()),
                      f.changedScope(display: "another-display"), f.changedScope(scale: 3)] {
            var recovered = M.Machine(pending: moved)
            expect(.environment) { _ = try recovered.requestReturn(f.sample(7, 2000, moved: true, scope: scope),
                f.sample(8, 2100, moved: true, scope: scope), access: f.access, now: 2100) }
            XCTAssertEqual(recovered.state, .needsRecovery); XCTAssertEqual(recovered.pending, moved)
        }
    }
    func testRestartAfterRestoreWasPreparedNeverRepeatsThatMoveBlindly() throws {
        let f = Fixture(); var machine = M.Machine(); _ = try show(f, &machine)
        let returning = try record(machine.requestReturn(f.sample(7, 1600, moved: true), f.sample(8, 1700, moved: true), access: f.access, now: 1700))
        var recovered = M.Machine(pending: returning)
        expect(.recoveryAmbiguous) { _ = try recovered.requestReturn(f.sample(9, 1800, moved: true), f.sample(10, 1900, moved: true), access: f.access, now: 1900) }
        XCTAssertEqual(recovered.pending?.phase, .restorePrepared)
        let settled = try record(recovered.requestReturn(f.sample(11, 2000), f.sample(12, 2100), access: f.access, now: 2100))
        XCTAssertEqual(settled.phase, .restored)
    }
    func testHumanInterferenceOrRevocationAfterPersistenceRetainsRecord() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        var human = f.sample(3, 1200); human.interferenceEpoch = UUID()
        expect(.interference) { _ = try machine.persisted(prepared, live: human, access: f.access, now: 1200) }
        XCTAssertEqual(machine.pending, prepared)
        var revoked = M.Machine(); let r = try begin(f, &revoked)
        expect(.permissions) { _ = try revoked.persisted(r, live: f.sample(3, 1200),
            access: M.Access(ax: true, post: false, interferenceObservation: true), now: 1200) }
        XCTAssertEqual(revoked.state, .needsRecovery); XCTAssertEqual(revoked.pending, r)
    }
    func testJournalFailureAndCorruptPlanCannotBeForgottenOrReplayed() throws {
        let f = Fixture(); var machine = M.Machine(); let prepared = try begin(f, &machine)
        machine.invalidate(.journal)
        XCTAssertEqual(machine.pending, prepared); XCTAssertEqual(machine.state, .needsRecovery)
        let corruptPlan = M.Plan(original: prepared.plan.original, reservationWidth: 42, rightInset: 20,
            shownOrder: prepared.plan.originalOrder)
        let corrupt = M.Record(schemaVersion: 1, transaction: UUID(), plan: corruptPlan, phase: .prepared)
        var recovered = M.Machine(pending: corrupt)
        expect(.journal) { _ = try recovered.requestReturn(f.sample(3, 1200), f.sample(4, 1300), access: f.access, now: 1300) }
        XCTAssertEqual(recovered.pending, corrupt)
        expect(.staleReceipt) { try recovered.cleared(transaction: corrupt.transaction) }
    }
}
