import AppKit

/// Public NSStatusItem adapter. Merely compiling it has no effects; the organizer
/// constructs it only behind the preview gate. Only a supplied owned object can
/// be resized, and a retained object/instance binding prevents recycled windows.
@MainActor
final class MenuBarOwnedStatusItemWidthDriver: MenuBarNativeRevealWidthDriver {
    private let item: NSStatusItem
    private let binding: MenuBarOwnedWidthBinding
    private let generation: () -> UUID
    private let readObservation: (MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation
    private let restorationSafety: () async throws -> Void
    init(item: NSStatusItem, itemKey: String, generation: @escaping () -> UUID,
         observe: @escaping (MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation,
         restorationSafety: @escaping () async throws -> Void) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard !itemKey.isEmpty, item.autosaveName == itemKey,
              let application = MenuBarApplicationIdentity.current(pid: pid) else {
            throw MenuBarNativeRevealController.Failure.wrongOwner
        }
        self.item = item; self.generation = generation; readObservation = observe
        self.restorationSafety = restorationSafety
        binding = MenuBarOwnedWidthBinding(itemKey: itemKey, instance: UUID(), pid: pid, application: application)
    }
    private func checkOwner() throws {
        guard item.autosaveName == binding.itemKey,
              MenuBarApplicationIdentity.current(pid: binding.pid) == binding.application else {
            throw MenuBarNativeRevealController.Failure.wrongOwner
        }
    }
    func widthState() throws -> MenuBarOwnedWidthState {
        try checkOwner()
        guard let button = item.button, let window = button.window, window.isVisible, window.windowNumber > 0 else {
            throw MenuBarNativeRevealController.Failure.staleObservation
        }
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let own = rows.filter { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == window.windowNumber
            && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == binding.pid
            && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)) }
        guard own.count == 1, let bounds = own[0][kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds), frame.width.isFinite, frame.width > 0 else {
            throw MenuBarNativeRevealController.Failure.staleObservation
        }
        let effective = item.length >= 0 ? item.length : button.bounds.width
        guard effective.isFinite, effective >= 0 else { throw MenuBarNativeRevealController.Failure.staleObservation }
        return MenuBarOwnedWidthState(binding: binding, length: item.length, effectiveLength: effective,
                                     backingFrame: frame, environment: generation())
    }
    func observe(_ identity: MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation {
        let before = try widthState()
        let observation = try await readObservation(identity)
        guard try widthState() == before, observation.ownedSpacer == before.backingFrame,
              observation.generation == before.environment else { throw MenuBarNativeRevealController.Failure.staleObservation }
        return observation
    }
    func setLength(_ length: CGFloat, matching expected: MenuBarOwnedWidthBinding) throws {
        try checkOwner()
        guard expected == binding,
              length == NSStatusItem.variableLength || (length.isFinite && length >= 0 && length <= 2048) else {
            throw MenuBarNativeRevealController.Failure.wrongOwner
        }
        // Restoration does not require an old window number or an onscreen
        // backing window: this exact retained NSStatusItem is still ours.
        item.length = length
    }
    func verifyRestorationSafety() async throws { try await restorationSafety() }
}
