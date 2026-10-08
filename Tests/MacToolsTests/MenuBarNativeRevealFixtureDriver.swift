import AppKit
import Foundation
#if !NATIVE_REVEAL_STANDALONE
@testable import MacTools
#endif

/// Shared by tests and the standalone candidate. These are private NSView
/// frames and synthetic window IDs, never NSStatusBar items or desktop windows.
@MainActor
final class MenuBarNativeRevealFixtureDriver: MenuBarNativeRevealWidthDriver {
    let bar = NSView(frame: CGRect(x: 0, y: 0, width: 2056, height: 43))
    let spacer = NSView(frame: CGRect(x: 1586, y: 0, width: 38, height: 43))
    let target = NSView(frame: CGRect(x: 963, y: 0, width: 42, height: 43))
    var binding = MenuBarOwnedWidthBinding(itemKey: "fixture-owned-spacer", instance: UUID(), pid: 10,
        application: MenuBarApplicationIdentity(bundleID: "fixture", bundlePath: "/Fixture.app", launch: 1))
    var generation = UUID()
    var length: CGFloat = -1
    var applicationMenuWidth: CGFloat = 300
    var orderedIDs: [UInt32] = [1, 2, 3]
    var targetOnScreen = true
    var reflowFactor: CGFloat = 1
    var recoveryShift: CGFloat = 0
    var failsNextWidthRead = false
    var throwsBeforeWrite = false
    var throwsAfterWrite = false
    var ignoresRestoreGeometry = false
    var throwsAtObservation: Int?
    var pauseAtObservation: Int?
    var continuation: CheckedContinuation<Void, Never>?
    private(set) var writes: [CGFloat] = []
    private(set) var observations = 0
    var didSetLength: (() -> Void)?
    var restorationUnsafe = false
    let targetApplication = MenuBarApplicationIdentity(bundleID: "fixture.target", bundlePath: "/FixtureTarget.app", launch: 1)
    init() { bar.addSubview(spacer); bar.addSubview(target) }
    var identity: MenuBarIconIdentity {
        let target = targetSnapshot()
        return MenuBarIconIdentity(capturing: target, peersOnDisplay: [target])
    }
    private func targetSnapshot() -> MenuBarStatusTarget {
        MenuBarStatusTarget(id: 1, pid: 20, frame: target.frame, onScreen: targetOnScreen, application: targetApplication)
    }
    func widthState() throws -> MenuBarOwnedWidthState {
        if failsNextWidthRead { failsNextWidthRead = false; throw MenuBarNativeRevealController.Failure.staleObservation }
        return MenuBarOwnedWidthState(binding: binding, length: length, effectiveLength: length >= 0 ? length : 22,
                              backingFrame: spacer.frame, environment: generation)
    }
    func observe(_ identity: MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation {
        observations += 1
        if observations == pauseAtObservation { await withCheckedContinuation { continuation = $0 }; continuation = nil }
        if observations == throwsAtObservation { throw MenuBarNativeRevealController.Failure.staleObservation }
        let item = targetSnapshot()
        return .init(generation: generation, displayID: 1, target: item,
            targetButton: CGRect(x: item.frame.minX + 8, y: 10.5, width: 26, height: 22),
            ownedSpacer: spacer.frame, recoveryButton: CGRect(x: 1632 + recoveryShift, y: 9.5, width: 17, height: 24),
            safeAreas: [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)],
            applicationMenu: CGRect(x: 0, y: 0, width: applicationMenuWidth, height: 38), orderedWindowIDs: orderedIDs)
    }
    func setLength(_ proposed: CGFloat, matching expected: MenuBarOwnedWidthBinding) throws {
        guard expected == binding else { throw MenuBarNativeRevealController.Failure.wrongOwner }
        if throwsBeforeWrite { throw MenuBarNativeRevealController.Failure.staleObservation }
        writes.append(proposed); length = proposed
        if proposed != -1 || !ignoresRestoreGeometry {
            let growth = proposed == -1 ? 0 : (proposed - 22) * reflowFactor
            let previousGrowth = spacer.frame.width - 38
            spacer.frame = CGRect(x: 1586 - growth, y: 0, width: 38 + growth, height: 43)
            target.frame = target.frame.offsetBy(dx: previousGrowth - growth, dy: 0)
        }
        didSetLength?()
        if throwsAfterWrite { throwsAfterWrite = false; throw MenuBarNativeRevealController.Failure.staleObservation }
    }
    func verifyRestorationSafety() async throws {
        let recovery = CGRect(x: 1632 + recoveryShift, y: 9.5, width: 17, height: 24)
        if restorationUnsafe || !CGRect(x: 1138, y: 0, width: 918, height: 38).contains(recovery) {
            throw MenuBarNativeRevealController.Failure.restorationUnverified
        }
    }
}

@MainActor
final class MenuBarMemoryOwnedWidthJournal: MenuBarOwnedWidthJournal {
    var record: MenuBarOwnedWidthRecord?
    var failSave = false
    var failLoad = false
    var failClear = false
    var saves = 0
    func load() throws -> MenuBarOwnedWidthRecord? {
        if failLoad { throw MenuBarNativeRevealController.Failure.recoveryRequired }
        return record
    }
    func save(_ value: MenuBarOwnedWidthRecord) throws {
        if failSave { throw MenuBarNativeRevealController.Failure.recoveryRequired }
        try value.validate(); record = value; saves += 1
    }
    func clear() throws {
        if failClear { throw MenuBarNativeRevealController.Failure.recoveryRequired }
        record = nil
    }
}
