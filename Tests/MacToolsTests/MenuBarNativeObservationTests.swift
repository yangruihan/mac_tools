import AppKit
import XCTest
@testable import MacTools

final class MenuBarNativeObservationTests: XCTestCase {
    private let display = MenuBarDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        quartzFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        safeAreas: [CGRect(x: 0, y: 1291, width: 918, height: 38), CGRect(x: 1138, y: 1291, width: 918, height: 38)])
    private let generation = UUID()
    private func item(_ id: UInt32, pid: Int32, x: CGFloat, width: CGFloat = 42, launch: Double = 1) -> MenuBarStatusTarget {
        .init(id: id, pid: pid, frame: CGRect(x: x, y: 0, width: width, height: 43), onScreen: true,
              application: MenuBarApplicationIdentity(bundleID: "test.\(pid)", bundlePath: "/Test\(pid).app", launch: launch))
    }
    private func context(shift: CGFloat = 0, extras: [MenuBarStatusTarget] = [], overlays: [CGRect] = [],
                         unsafe: [UInt32] = [], frontLaunch: Double = 1) -> MenuBarNativeObservation.Context {
        .init(generation: generation, displays: [display],
              windows: [item(1, pid: 20, x: 963 - shift), item(2, pid: 10, x: 1586 - shift, width: 38 + shift),
                        item(3, pid: 10, x: 1624, width: 33), item(4, pid: 10, x: 1224 - shift, width: 24)] + extras,
              ownerPID: 10, controlID: 2, dividerID: 4, frontPID: 30,
              frontApplication: MenuBarApplicationIdentity(bundleID: "front", bundlePath: "/Front.app", launch: frontLaunch),
              overlays: overlays, unprovenPixelWindowIDs: unsafe)
    }
    private func assemble(_ context: MenuBarNativeObservation.Context, duplicates: Bool = false,
                          menu: [CGRect]? = nil) throws -> MenuBarNativeRevealPlan.Observation {
        let target = try XCTUnwrap(context.windows.first { $0.id == 1 })
        let frame = CGRect(x: target.frame.minX + 8, y: 10.5, width: 26, height: 22)
        return try MenuBarNativeObservation.assemble(context, identity: MenuBarIconIdentity(capturing: target, peersOnDisplay: context.windows),
            targetAX: duplicates ? [frame, frame] : [frame],
            recoveryAX: [CGRect(x: 1623, y: 9.5, width: 34.5, height: 24)],
            menuAX: menu ?? [CGRect(x: 0, y: 0, width: 300, height: 38)])
    }
    func testAssemblesCompletePublicGeometryAndVerifiesNativeReflow() throws {
        let before = try assemble(context())
        XCTAssertEqual(before.recoveryButton, CGRect(x: 1624, y: 9.5, width: 33, height: 24))
        XCTAssertEqual(before.peers.map(\.id), [1, 4, 2, 3])
        let plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertEqual(plan.requestedExtraLength, 83)
        XCTAssertNoThrow(try plan.verify(assemble(context(shift: 83))))
    }
    func testAmbiguousRecoveryAndDuplicateAXMatchesAreRefused() {
        XCTAssertThrowsError(try assemble(context(extras: [item(5, pid: 10, x: 1680)])))
        XCTAssertThrowsError(try assemble(context(), duplicates: true))
    }
    func testPhysicallyCollapsedDividerHasSpecificPreconditionRefusal() throws {
        let original = context()
        var windows = original.windows
        windows[3] = item(4, pid: 10, x: -2845, width: 4128)
        let collapsed = MenuBarNativeObservation.Context(generation: generation, displays: [display], windows: windows,
            ownerPID: 10, controlID: 2, dividerID: 4, frontPID: 30, frontApplication: original.frontApplication, overlays: [])
        XCTAssertThrowsError(try assemble(collapsed)) {
            XCTAssertEqual(String(describing: $0), "collapsed")
        }
    }
    func testUnknownPeerAndRecycledTargetAreNotSilentlyIgnored() throws {
        var unknown = item(5, pid: 40, x: 800); unknown.application = nil
        XCTAssertThrowsError(try assemble(context(extras: [unknown])))
        let first = try assemble(context()), plan = try MenuBarNativeRevealPlan.make(first)
        var recycled = context(shift: 83).windows
        recycled[3].application = MenuBarApplicationIdentity(bundleID: "test.10", bundlePath: "/Test10.app", launch: 2)
        let changed = MenuBarNativeObservation.Context(generation: generation, displays: [display], windows: recycled,
            ownerPID: 10, controlID: 2, dividerID: 4, frontPID: 30, frontApplication: first.frontApplication!, overlays: [])
        XCTAssertThrowsError(try plan.verify(assemble(changed)))
    }
    func testUnknownHiddenPeerIsStillRefusedRatherThanDroppedFromOrder() throws {
        let unknown = MenuBarStatusTarget(id: 99, pid: 40,
            frame: CGRect(x: 800, y: 0, width: 30, height: 43), onScreen: false, application: nil)
        XCTAssertThrowsError(try assemble(context(extras: [unknown]))) {
            XCTAssertEqual($0 as? MenuBarNativeObservationFailure, .topology)
        }
        let hidden = MenuBarStatusTarget(id: 99, pid: 40,
            frame: unknown.frame, onScreen: false, application: item(99, pid: 40, x: 800).application)
        let observation = try assemble(context(extras: [hidden]))
        XCTAssertTrue(observation.orderedWindowIDs.contains(99))
        XCTAssertFalse(try XCTUnwrap(observation.peers.first { $0.id == 99 }).onScreen)
    }
    func testPartialAXNotchCoverageIsNotClippedToSafeAreaToPass() throws {
        let before = try assemble(context())
        let insufficient = try assemble(context(shift: 75))
        XCTAssertGreaterThan(insufficient.targetButton.maxX, 918)
        let plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertThrowsError(try plan.verify(insufficient))
    }
    func testMenuUnknownOrOnWrongDisplayRefusesAndOccupiedSpaceIsExcluded() throws {
        XCTAssertThrowsError(try assemble(context(), menu: []))
        XCTAssertThrowsError(try assemble(context(), menu: [CGRect(x: -100, y: -300, width: 300, height: 24)]))
        let crowded = try assemble(context(), menu: [CGRect(x: 0, y: 0, width: 900, height: 38)])
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(crowded))
        let before = try assemble(context()), plan = try MenuBarNativeRevealPlan.make(before)
        XCTAssertThrowsError(try plan.verify(assemble(context(shift: 83, frontLaunch: 2))))
    }
    func testInactiveNativeMenuZeroSizeGeometryCannotPassMenuSafetyCheck() {
        // The no-activation self-AX reproduction returns success with zero-size
        // menu items. API success alone must never prove occupied screen space.
        XCTAssertThrowsError(try assemble(context(), menu: [CGRect(x: 0, y: 37, width: 0, height: 0)])) {
            XCTAssertEqual($0 as? MenuBarNativeObservationFailure, .menu)
        }
    }
    func testOverlayOrUnknownOpacityCannotClaimCompleteVisibility() {
        XCTAssertThrowsError(try assemble(context(overlays: [CGRect(x: 965, y: 8, width: 50, height: 30)])))
        XCTAssertThrowsError(try assemble(context(unsafe: [1])))
        XCTAssertThrowsError(try assemble(context(unsafe: [3])))
        XCTAssertThrowsError(try assemble(context(unsafe: [2])))
    }
    func testManualEditingMayChangeOrderButNotIdentitySetOrRecovery() throws {
        let before = try assemble(context()), plan = try MenuBarNativeRevealPlan.make(before)
        let confirmed = try assemble(context(shift: 83))
        var manual = confirmed
        manual = .init(generation: manual.generation, displayID: manual.displayID,
            target: item(1, pid: 20, x: 700), targetButton: CGRect(x: 708, y: 10.5, width: 26, height: 22),
            ownedSpacer: manual.ownedSpacer, recoveryButton: manual.recoveryButton, safeAreas: manual.safeAreas,
            applicationMenu: manual.applicationMenu, orderedWindowIDs: [4, 1, 2, 3], peers: manual.peers,
            frontPID: manual.frontPID, frontApplication: manual.frontApplication, recoveryTarget: manual.recoveryTarget)
        XCTAssertNoThrow(try plan.verifyEditing(manual, confirmed: confirmed))
        manual.peers.removeLast()
        XCTAssertThrowsError(try plan.verifyEditing(manual, confirmed: confirmed))
    }
    @MainActor
    func testOrdinaryBundleCannotEnableWidthFromSettingsOrPublicEntry() throws {
        let name = "NativePreviewGate.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "MacToolsNativeRevealPreviewEnabled")
        let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults)
        settings.set(try JSONEncoder().encode(false), forKey: "optedIn")
        let plugin = MenuBarOrganizerPlugin(context: PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in }))
        let original = defaults.persistentDomain(forName: name)! as NSDictionary
        XCTAssertFalse(plugin.nativeRevealPreviewEnabled)
        plugin.start(); plugin.beginNativeReveal(1); plugin.recoverNativeReveal(); plugin.toolboxWillClose(); plugin.stop()
        XCTAssertEqual(plugin.nativeRevealState, .idle); XCTAssertFalse(plugin.isOrganizing)
        XCTAssertTrue((defaults.persistentDomain(forName: name)! as NSDictionary).isEqual(original))
    }
}
