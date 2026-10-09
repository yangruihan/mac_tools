#if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
import SwiftUI
import CryptoKit

/// Product entry into the signed, already verified owned Ice worker.
/// This host has no mouse sender; permissions/identity/cancel/return stay in the worker.
enum MenuBarIceCandidateProductBridge {
    static func preflight() throws -> [String: Any] { try MenuBarIceInterfaceProductBridge.preflight() }
}

@MainActor final class MenuBarIceCandidateProductModel: ObservableObject {
    @Published var status = "已通过本机自建 T/N 的真实搬出、菜单与归位验证。"
    @Published var busy = false
    @Published var ownedAttempted = false
    @Published var session: URL?
    @Published var ordinaryRows: [MenuBarIceSelectedTarget.Row] = []
    @Published var ordinaryWindowID: UInt32 = 0
    @Published var ordinaryStatus = "请选择具体应用图标，核验身份后打开单轮控制窗口。"
    private var ordinaryDirectory: MenuBarIceSelectedTarget.Directory?
    private var ordinaryTarget: MenuBarIceSelectedTarget?
    var hasOrdinaryTarget: Bool { ordinaryTarget != nil }
    @Published var ordinarySession: URL?
    @Published var ordinaryAttempted = false
    private var ordinaryLaunch: MenuBarIceInterfaceProductBridge.Launch?
    private var ownedLaunch: MenuBarIceInterfaceProductBridge.Launch?
    private var controllerPID: Int32?
    private var controllerProof: MenuBarProcessSignature.Proof?
    private func activateProductWindow() async throws -> MenuBarIceSelectedTarget.Directory {
        guard let window = NSApp.windows.first(where: { $0.title == "MacTools · Ice 候选" || $0.title == "Mac 工具箱" }) else { throw MenuBarIceInterfaceProductBridge.Failure.invalid }
        // Activate our existing ordinary window before capture, not after binding a fullscreen Space.
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let until = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < until {
            if window.isOnActiveSpace, window.isKeyWindow, NSApp.isActive,
               let directory = try? MenuBarIceSelectedTarget.readDirectory() { return directory }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw MenuBarIceInterfaceProductBridge.Failure.invalid
    }
    func readOrdinaryDirectory() {
        guard !busy else { return }
        ordinaryTarget = nil; ordinaryWindowID = 0
        busy = true
        Task {
            defer { busy = false }
            do {
                let directory = try await activateProductWindow()
                ordinaryDirectory = directory; ordinaryRows = directory.rows
                ordinaryStatus = "请选择具体图标。刷新列表不会移动图标或打开菜单。"
            } catch {
                ordinaryDirectory = nil; ordinaryRows = []
                ordinaryStatus = "无法读取本机单屏图标列表：\(error)"
            }
        }
    }
    func bindOrdinaryTarget() {
        ordinaryTarget = nil
        guard let directory = ordinaryDirectory,
              let row = ordinaryRows.first(where:{ $0.id == ordinaryWindowID }) else { return }
        do {
            ordinaryTarget = try MenuBarIceSelectedTarget.capture(row,from:directory)
            ordinaryStatus = "已核验 \(row.title) 的所选图标，可打开单轮控制窗口。"
        } catch { ordinaryStatus = "图标或所属应用已改变，请刷新后重新选择。" }
    }
    func openOrdinarySession() {
        guard !CommandLine.arguments.contains("--ice-candidate-ui-smoke"), !busy,
              session == nil, !ownedAttempted, !ordinaryAttempted, let target = ordinaryTarget else { return }
        ordinaryAttempted = true; busy = true
        ordinaryStatus = "正在准备选定图标的 v9 会话…"
        Task {
            defer { busy = false }
            do {
                _ = try await activateProductWindow()
                let directory = try await Task.detached { try MenuBarIceInterfaceProductBridge.prepare(target) }.value
                ordinarySession = directory // Preserve it even if launch validation fails.
                ordinaryLaunch = try await MenuBarIceInterfaceProductBridge.launch(directory, target: target)
                ordinaryStatus = "控制窗口已就绪。请在其窗口按“开始单轮”；关闭或失焦后等待15秒归位。取消使用控制窗口。"
            } catch { ordinaryStatus = error.localizedDescription }
        }
    }
    func refreshOrdinary() {
        guard let directory = ordinarySession else { return }
        do {
            let url = directory.appendingPathComponent("result.json")
            guard FileManager.default.fileExists(atPath: url.path) else {
                ordinaryStatus = ordinaryLaunch?.isRunning == false
                    ? "控制进程已退出，未发布终态结果；请检查恢复状态并保留证据。"
                    : "尚无终态结果，请查看控制窗口；关闭产品窗口不表示取消。"
                return
            }
            let data = try Data(contentsOf: url)
            guard data.count < 2_000_000, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let nonce = UUID(uuidString: String(directory.lastPathComponent.dropFirst(8))) else { throw MenuBarIceInterfaceProductBridge.Failure.invalid }
            let result = try MenuBarIceInterfaceProductBridge.result(value, nonce: nonce)
            if result.posts == 0, value["stage"] as? String == "package", value["failure"] as? String == "source" {
                ordinaryStatus = "本轮未开始：图形启动路径的权限检查未通过（0次投递）。诊断记录已保留。"; return
            }
            ordinaryStatus = result.passed
                ? "本轮搬出、界面结束及原邻边归位通过（\(result.posts)次投递）。"
                : "本轮停止，未完成闭环（\(result.posts)次投递）。原始结果及恢复责任已保留。"
        } catch { ordinaryStatus = error.localizedDescription }
    }
    func showOrdinaryController() {
        guard let launch = ordinaryLaunch, launch.isRunning,
              (try? MenuBarProcessSignature.read(launch.proof.pid)) == launch.proof else {
            if let directory = ordinarySession, FileManager.default.fileExists(atPath: directory.appendingPathComponent("result.json").path) { refreshOrdinary() }
            else { ordinaryStatus = "原控制进程已退出或身份改变，尚无终态结果；请查看证据。" }
            return
        }
        NSRunningApplication(processIdentifier: launch.proof.pid)?.activate(options: [.activateIgnoringOtherApps])
    }
    func showOrdinaryEvidence() { if let ordinarySession { NSWorkspace.shared.open(ordinarySession) } }
    func inspectRecovery() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached { try MenuBarIceInterfaceProductBridge.recovery() }.value
                status = value["journalPending"] as? Bool == true
                    ? "已有待恢复记录。请查看原始记录；不会重放本轮或自动清除责任。"
                    : "没有待恢复责任。历史结果仍保留在各会话目录。"
            } catch { status = error.localizedDescription }
        }
    }
    func showRecoveryEvidence() {
        let directory = MenuBarIceInterfaceProductBridge.root.appendingPathComponent("selected-relative-recovery-v2")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: directory.path) ? directory : MenuBarIceInterfaceProductBridge.root)
    }
    func openSession(ordinaryWindow: Bool = false) {
        guard !CommandLine.arguments.contains("--ice-candidate-ui-smoke"), !busy, session == nil, !ownedAttempted, !ordinaryAttempted else { return }
        ownedAttempted = true; busy = true; status = "正在准备自建 T/N 会话…"
        Task {
            defer { busy = false }
            do {
                _ = try await activateProductWindow()
                let directory = try await Task.detached { try MenuBarIceInterfaceProductBridge.prepareOwned() }.value
                session = directory
                let launch = try await MenuBarIceInterfaceProductBridge.launch(directory, ownedWindow: ordinaryWindow)
                ownedLaunch = launch; controllerPID = launch.proof.pid; controllerProof = launch.proof
                status = "自建控制进程已启动。请在其窗口按“开始单轮”；需要停止时按“取消并关闭”。"
            } catch { status = error.localizedDescription }
        }
    }
    func refresh() {
        guard let directory = session else { return }
        do {
            let url = directory.appendingPathComponent("result.json")
            guard FileManager.default.fileExists(atPath: url.path) else { status = "尚无终态结果，请查看控制窗口；关闭产品窗口不表示取消。"; return }
            let data = try Data(contentsOf: url)
            guard data.count < 2_000_000, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let nonce = UUID(uuidString: String(directory.lastPathComponent.dropFirst(8))) else { throw MenuBarIceInterfaceProductBridge.Failure.invalid }
            let result = try MenuBarIceInterfaceProductBridge.result(value, nonce: nonce)
            status = result.passed ? "本轮搬出、界面结束及原邻边归位通过（\(result.posts)次投递）。" : "本轮停止（\(result.posts)次投递）。请保留原始结果与恢复记录。"
        } catch { status = error.localizedDescription }
    }
    func showController() {
        guard let controllerPID, let controllerProof,
              (try? MenuBarProcessSignature.read(controllerPID)) == controllerProof else {
            status = "原控制窗口已退出或身份改变；不会激活其他进程。"; return
        }
        NSRunningApplication(processIdentifier:controllerPID)?.activate(options:[.activateIgnoringOtherApps])
    }
    func showEvidence() { if let session { NSWorkspace.shared.open(session) } }
}

struct MenuBarIceCandidateProductView: View {
    @StateObject private var model = MenuBarIceCandidateProductModel()
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
          GroupBox("Ice 菜单栏试用 · 自建 T/N") {
            VStack(alignment:.leading, spacing:14) {
                Text("自建 T/N 测试会短暂影响焦点和光标。")
                Text("搬出 T → 打开界面 → 结束界面 → 等待15秒 → 原邻边归还").font(.callout)
                Text(model.status).textSelection(.enabled).accessibilityIdentifier("ice-candidate-status")
                HStack {
                    Button("自建菜单测试") { model.openSession() }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.session != nil || model.ownedAttempted || model.ordinaryAttempted || CommandLine.arguments.contains("--ice-candidate-ui-smoke"))
                        .accessibilityIdentifier("ice-candidate-open-owned-session")
                    Button("自建普通窗口测试") { model.openSession(ordinaryWindow: true) }
                        .disabled(model.busy || model.session != nil || model.ownedAttempted || model.ordinaryAttempted || CommandLine.arguments.contains("--ice-candidate-ui-smoke"))
                    Button("显示控制窗口") { model.showController() }.disabled(model.session == nil)
                    Button("检查结果") { model.refresh() }.disabled(model.session == nil)
                    Button("查看证据") { model.showEvidence() }.disabled(model.session == nil)
                }
                Text("自建测试与所选普通图标分别在各自控制窗口开始与取消。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
          }
          GroupBox("普通图标 · 单轮试用") {
            VStack(alignment:.leading,spacing:10) {
                Text(model.ordinaryStatus).font(.callout)
                HStack {
                    Button("刷新图标列表") { model.readOrdinaryDirectory() }.disabled(model.busy || model.ordinaryAttempted || model.session != nil)
                    Picker("目标",selection:$model.ordinaryWindowID) {
                        Text("请选择图标").tag(UInt32(0))
                        ForEach(model.ordinaryRows) { row in
                            Text("\(row.title) · \(row.id)").tag(row.id)
                        }
                    }.disabled(model.busy || model.ordinaryAttempted || model.session != nil).onChange(of:model.ordinaryWindowID) { _ in model.bindOrdinaryTarget() }
                }
                HStack {
                    Button("打开选定图标控制窗口") { model.openOrdinarySession() }
                        .disabled(model.busy || !model.hasOrdinaryTarget || model.session != nil || model.ownedAttempted || model.ordinaryAttempted || CommandLine.arguments.contains("--ice-candidate-ui-smoke"))
                        .accessibilityIdentifier("ice-interface-open-selected-session")
                    Button("显示控制窗口") { model.showOrdinaryController() }.disabled(model.ordinarySession == nil)
                    Button("检查结果") { model.refreshOrdinary() }.disabled(model.ordinarySession == nil)
                    Button("查看证据") { model.showOrdinaryEvidence() }.disabled(model.ordinarySession == nil)
                }
                Text("会短暂影响焦点和光标。此按钮只打开控制窗口，开始按钮执行一次左键试用。仅验证原邻居同一侧的归位。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
          }
          HStack {
              Button("检查恢复状态") { model.inspectRecovery() }.disabled(model.busy)
              Button("查看恢复记录") { model.showRecoveryEvidence() }
          }
        }
    }
}
#endif
