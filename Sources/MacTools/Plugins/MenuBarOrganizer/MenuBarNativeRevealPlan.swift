import CoreGraphics
import Foundation

/// Geometry contract shared with the preview-gated live reveal controller.
/// Observations must include the
/// front application's occupied menu area, never only physical notch geometry.
struct MenuBarNativeRevealPlan {
    struct Observation: Equatable {
        let generation: UUID
        let displayID: CGDirectDisplayID
        let target: MenuBarStatusTarget
        let targetButton: CGRect
        let ownedSpacer: CGRect
        let recoveryButton: CGRect
        let safeAreas: [CGRect]
        let applicationMenu: CGRect
        let orderedWindowIDs: [CGWindowID]
        var peers: [MenuBarStatusTarget] = []
        var frontPID: Int32? = nil
        var frontApplication: MenuBarApplicationIdentity? = nil
        var recoveryTarget: MenuBarStatusTarget? = nil
    }
    enum Failure: String, LocalizedError, Equatable, MenuBarNativeDiagnosticError {
        case invalidObservation, unsupportedLayout, alreadyVisible, noSpace
        case changedEnvironment, changedIdentity, changedOrder, unverifiedReflow, targetNotOnScreen
        var diagnosticCode: String { "plan.\(rawValue)" }
        var errorDescription: String? {
            switch self {
            case .invalidObservation: return "目标或观测数据无效，未确认露出。"
            case .unsupportedLayout: return "当前布局不支持安全露出，未继续。"
            case .alreadyVisible: return "目标已位于可见区域，无需临时增宽。"
            case .noSpace: return "应用菜单之后没有足够空间完整露出目标。"
            case .changedEnvironment: return "前台菜单、显示区域或环境代次改变，露出验证停止。"
            case .changedIdentity: return "目标、恢复入口或图标运行身份改变，露出验证停止。"
            case .changedOrder: return "菜单栏窗口几何顺序改变（包括未显示窗口），露出验证停止。"
            case .unverifiedReflow: return "宽度变化与完整目标位移或恢复入口不一致，未确认露出。"
            case .targetNotOnScreen: return "目标几何虽可读取，但系统未确认该窗口已显示，未确认露出。"
            }
        }
    }
    enum Purpose: String {
        case moveIntoSafeSlot, attemptUnorderedTarget
    }
    let before: Observation
    let requestedExtraLength: CGFloat
    let purpose: Purpose
    private let leftSlot: CGRect
    private static let tolerance: CGFloat = 1

    static func make(_ before: Observation, maximumExtraLength: CGFloat = 512) throws -> Self {
        guard maximumExtraLength.isFinite, maximumExtraLength > 0,
              valid(before.target.frame), valid(before.targetButton), valid(before.ownedSpacer),
              valid(before.recoveryButton), valid(before.applicationMenu),
              let application = before.target.application, application.launch.isFinite,
              !application.bundleID.isEmpty, !application.bundlePath.isEmpty,
              before.orderedWindowIDs.filter({ $0 == before.target.id }).count == 1,
              Set(before.orderedWindowIDs).count == before.orderedWindowIDs.count else { throw Failure.invalidObservation }
        let areas = before.safeAreas.sorted { $0.minX < $1.minX }
        guard areas.count == 2, areas.allSatisfy(valid),
              areas[0].maxX < areas[1].minX,
              abs(areas[0].minY - areas[1].minY) <= tolerance,
              areas[1].contains(before.recoveryButton),
              before.ownedSpacer.maxX <= before.recoveryButton.minX + tolerance,
              abs(before.ownedSpacer.minY - before.target.frame.minY) <= tolerance,
              before.targetButton.maxX <= before.ownedSpacer.minX + tolerance,
              before.target.frame.contains(before.targetButton),
              before.applicationMenu.minX >= areas[0].minX - tolerance,
              before.applicationMenu.maxX <= areas[0].maxX,
              abs(before.applicationMenu.minY - areas[0].minY) <= tolerance else { throw Failure.unsupportedLayout }
        let minimumX = before.applicationMenu.maxX + 4
        let slot = CGRect(x: minimumX, y: areas[0].minY,
                          width: max(0, areas[0].maxX - 4 - minimumX), height: areas[0].height)
        let alreadyInSlot = slot.contains(before.targetButton)
        if alreadyInSlot && before.target.onScreen { throw Failure.alreadyVisible }
        // A hidden window can have a valid cached frame already inside the
        // slot. Allocate one real button width, once, if leftward travel fits.
        // This authorizes only our width attempt, never target interaction.
        let purpose: Purpose = alreadyInSlot ? .attemptUnorderedTarget : .moveIntoSafeSlot
        let extra = alreadyInSlot ? before.targetButton.width : before.targetButton.maxX - slot.maxX
        guard extra > 0, extra <= maximumExtraLength,
              slot.contains(before.targetButton.offsetBy(dx: -extra, dy: 0)) else { throw Failure.noSpace }
        return Self(before: before, requestedExtraLength: extra, purpose: purpose, leftSlot: slot)
    }

    /// Requested NSStatusItem length is not backing-window width. Accept only
    /// measured native reflow, with the target fully clear of notch AND app menus.
    func verify(_ after: Observation) throws {
        guard after.generation == before.generation, after.displayID == before.displayID,
              after.safeAreas == before.safeAreas, after.applicationMenu == before.applicationMenu,
              after.frontPID == before.frontPID, after.frontApplication == before.frontApplication else { throw Failure.changedEnvironment }
        guard after.target.id == before.target.id, after.target.pid == before.target.pid,
              after.target.application == before.target.application else { throw Failure.changedIdentity }
        guard after.orderedWindowIDs == before.orderedWindowIDs else { throw Failure.changedOrder }
        guard samePeers(before.peers, after.peers), after.recoveryTarget == before.recoveryTarget else { throw Failure.changedIdentity }
        guard after.target.onScreen else { throw Failure.targetNotOnScreen }
        let measured = after.ownedSpacer.width - before.ownedSpacer.width
        guard Self.valid(after.target.frame), Self.valid(after.targetButton), Self.valid(after.ownedSpacer),
              measured.isFinite, measured > 0,
              abs(after.ownedSpacer.maxX - before.ownedSpacer.maxX) <= Self.tolerance,
              abs(after.ownedSpacer.minY - before.ownedSpacer.minY) <= Self.tolerance,
              abs(after.ownedSpacer.height - before.ownedSpacer.height) <= Self.tolerance,
              close(after.recoveryButton, before.recoveryButton),
              close(after.targetButton, before.targetButton.offsetBy(dx: -measured, dy: 0)),
              close(after.target.frame, before.target.frame.offsetBy(dx: -measured, dy: 0)),
              leftSlot.contains(after.targetButton) else { throw Failure.unverifiedReflow }
    }
    func verifyEditing(_ current: Observation, confirmed: Observation) throws {
        guard current.generation == confirmed.generation, current.displayID == confirmed.displayID,
              current.safeAreas == confirmed.safeAreas, current.frontPID == confirmed.frontPID,
              current.frontApplication == confirmed.frontApplication, current.applicationMenu == confirmed.applicationMenu else { throw Failure.changedEnvironment }
        guard current.target.id == confirmed.target.id, current.target.pid == confirmed.target.pid,
              current.target.application == confirmed.target.application,
              samePeers(current.peers, confirmed.peers), current.recoveryTarget == confirmed.recoveryTarget else { throw Failure.changedIdentity }
        guard current.target.onScreen else { throw Failure.targetNotOnScreen }
        // Manual order changes are permitted; only the exact identity set survives.
        guard current.ownedSpacer == confirmed.ownedSpacer, current.recoveryButton == confirmed.recoveryButton,
              current.safeAreas.contains(where: { $0.contains(current.targetButton) }),
              !current.applicationMenu.intersects(current.targetButton) else { throw Failure.unverifiedReflow }
    }
    private func samePeers(_ a: [MenuBarStatusTarget], _ b: [MenuBarStatusTarget]) -> Bool {
        guard a.count == b.count else { return false }
        return a.allSatisfy { old in
            let matches = b.filter { $0.id == old.id }
            return matches.count == 1 && matches[0].pid == old.pid && matches[0].application == old.application
        }
    }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
    }
    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX, a.minY, a.width, a.height], [b.minX, b.minY, b.width, b.height])
            .allSatisfy { abs($0 - $1) <= Self.tolerance }
    }
}
