import AppKit
import Darwin
import CoreGraphics

// In-memory only. PID and CGWindowID are hints within one launch, never durable identities.
struct MenuBarApplicationIdentity: Equatable {
    let bundleID: String
    let bundlePath: String
    let launch: TimeInterval
    static func current(pid: Int32) -> Self? {
        guard let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier,
              let url = app.bundleURL else { return nil }
        // NSRunningApplication.launchDate is nil for many system agents and login helpers.
        // Kernel start time is process metadata and also disambiguates a recycled PID.
        var process = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              process.pbi_start_tvsec > 0 else { return nil }
        return Self(bundleID: bundleID, bundlePath: url.standardizedFileURL.path,
                    launch: Double(process.pbi_start_tvsec) + Double(process.pbi_start_tvusec) / 1_000_000)
    }
    func sameApplication(_ other: Self) -> Bool {
        !bundleID.isEmpty && !bundlePath.isEmpty && bundleID == other.bundleID && bundlePath == other.bundlePath
    }
}

struct MenuBarIconIdentity {
    let windowID: CGWindowID
    let pid: Int32
    let application: MenuBarApplicationIdentity?
    let singletonAtCapture: Bool
    init(capturing target: MenuBarStatusTarget, peersOnDisplay: [MenuBarStatusTarget]) {
        windowID = target.id; pid = target.pid; application = target.application
        singletonAtCapture = peersOnDisplay.filter { $0.pid == target.pid }.count == 1
    }
    static func resolve(_ identity: Self, windows: [MenuBarStatusTarget], safeAreas: [CGRect], preferredDisplay: CGRect? = nil) -> MenuBarIconResolution {
        guard let original = identity.application, original.launch.isFinite else { return .failed(.unverifiedIdentity) }
        let owned = windows.filter { item in
            item.application.map { original.sameApplication($0) && $0.launch.isFinite } == true
                && (preferredDisplay.map { $0.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) } ?? true)
        }
        guard !owned.isEmpty else { return .failed(.missing) }
        // Prefer the exact window only within the captured process launch. Reject recycled IDs/PIDs.
        let exact = owned.filter { $0.id == identity.windowID && $0.pid == identity.pid
            && $0.application?.launch == original.launch && $0.onScreen }
        let candidate: MenuBarStatusTarget
        if exact.count == 1 { candidate = exact[0] }
        else {
            guard identity.singletonAtCapture else { return .failed(.ambiguous) }
            let visible = owned.filter(\.onScreen)
            guard !visible.isEmpty else { return .failed(.offScreen) }
            guard visible.count == 1 else { return .failed(.ambiguous) }
            candidate = visible[0]
        }
        guard validFrame(candidate.frame) else { return .failed(.invalidGeometry) }
        let point = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
        guard safeAreas.contains(where: { $0.contains(point) }) else { return .failed(.occluded) }
        guard windows.filter({ $0.onScreen && $0.frame.contains(point) }).count == 1 else { return .failed(.overlapped) }
        return .matched(candidate)
    }
    private static func validFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite && frame.width > 8 && frame.width < 150 && frame.height > 0 && frame.height < 64
    }
}

enum MenuBarIconResolution {
    enum Failure: Equatable {
        case unverifiedIdentity, missing, ambiguous, offScreen, occluded, overlapped, invalidGeometry
        var message: String {
            switch self {
            case .unverifiedIdentity: return "无法核实图标所属应用，未发送点击；请重试采集或直接操作原生图标。"
            case .missing: return "原应用已退出或图标尚未重新出现；未发送点击，请等待应用就绪后重试。"
            case .ambiguous: return "同一应用有多个图标或多个显示器副本，无法唯一匹配；未发送点击，请重新采集。"
            case .offScreen: return "已找到原应用的图标，但当前离屏或未显示；未发送点击，请展开后重试。"
            case .occluded: return "已找到原图标，但被刘海或屏幕边界遮挡；未发送点击，可在有足够空间的屏幕上操作。"
            case .overlapped: return "图标位置被其他状态项覆盖，无法核实目标；未发送点击，请展开后重试。"
            case .invalidGeometry: return "原图标尺寸异常，无法安全定位；未发送点击，请重试采集。"
            }
        }
    }
    case matched(MenuBarStatusTarget), failed(Failure)
    var target: MenuBarStatusTarget? { if case .matched(let value) = self { return value }; return nil }
    var failure: Failure? { if case .failed(let value) = self { return value }; return nil }
}
