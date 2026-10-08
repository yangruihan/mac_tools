#if ICE_MENU_BAR_CANDIDATE || ICE_MENU_BAR_INTEGRATED
import SwiftUI
import CryptoKit

/// Product entry into the signed, already verified owned Ice worker.
/// This host has no mouse sender; permissions/identity/cancel/return stay in the worker.
enum MenuBarIceCandidateProductBridge {
    struct Configuration {
        let helper: URL, python: URL, receipt: [String: Any]
    }
    static func configuration() throws -> Configuration {
        guard ["com.ryanai.mactools.icecandidate", "com.ryanai.mactools"].contains(Bundle.main.bundleIdentifier ?? ""),
              let url = Bundle.main.url(forResource: "ice-candidate-bridge", withExtension: "json"),
              let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              receipt["hostBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              receipt["contract"] as? String == "isolatedOwnedQuietV1",
              receipt["strictANYRequired"] as? Bool == false,
              let helperPath = receipt["helper"] as? String,
              let pythonPath = receipt["python"] as? String,
              let helperSHA = receipt["helperSHA256"] as? String else { throw Failure.message("候选构建说明不完整，请重新构建。") }
        let helper = URL(fileURLWithPath: helperPath), python = URL(fileURLWithPath: pythonPath)
        let digest = SHA256.hash(data: try Data(contentsOf: helper)).map { String(format:"%02x",$0) }.joined()
        guard digest == helperSHA, FileManager.default.isExecutableFile(atPath: python.path) else {
            throw Failure.message("测试组件已改变，请重新构建候选。")
        }
        return .init(helper:helper, python:python, receipt:receipt)
    }
    static func command(_ arguments: [String]) throws -> [String: Any] {
        let config = try configuration()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mactools-ice-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:false, attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:directory) }
        let output = directory.appendingPathComponent("stdout"), error = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath:output.path, contents:nil, attributes:[.posixPermissions:0o600])
        FileManager.default.createFile(atPath:error.path, contents:nil, attributes:[.posixPermissions:0o600])
        let stdout = try FileHandle(forWritingTo:output), stderr = try FileHandle(forWritingTo:error)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process(), finished = DispatchSemaphore(value:0)
        process.executableURL = config.python; process.arguments = [config.helper.path] + arguments
        process.standardOutput = stdout; process.standardError = stderr
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout:.now()+15) == .success else {
            process.terminate()
            throw Failure.message("组件启动结果未知。请保留测试窗口并使用其取消按钮，不要重复启动。")
        }
        guard process.terminationStatus == 0 else {
            throw Failure.message("测试组件预检或启动失败；保留已有会话，检查构建或恢复记录。")
        }
        let data = try Data(contentsOf:output)
        guard data.count < 1_048_576,
              let value = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw Failure.message("组件未返回有效结果。") }
        return value
    }
    static func preflight() throws -> [String: Any] {
        let config = try configuration(), value = try command(["--preflight"])
        guard value["prepared"] as? Bool == true,
              let manifest = value["manifest"] as? [String: Any],
              manifest["revision"] as? String == config.receipt["workerRevision"] as? String,
              manifest["controllerSHA256"] as? String == config.receipt["controllerSHA256"] as? String,
              manifest["fixtureSHA256"] as? String == config.receipt["fixtureSHA256"] as? String,
              let recovery = value["recovery"] as? [String:Any], recovery["journalPending"] as? Bool == false else {
            throw Failure.message("组件与候选不匹配或仍有待恢复责任。")
        }
        return ["scope":"ownedTNProductEntry","contract":"isolatedOwnedQuietV1","inputPolicy":"iceMouseTracking",
                "strictANYRequired":false,"workerRevision":manifest["revision"]!,"journalPending":false,
                "mousePosts":0,"windowsOpened":0,"permissionRequests":0,"thirdPartyMovementEnabled":false,
                "hostBackend":"isolatedSignedWorker","installedHostIntegration":Bundle.main.bundleIdentifier == "com.ryanai.mactools"]
    }
}

@MainActor final class MenuBarIceCandidateProductModel: ObservableObject {
    @Published var status = "已通过本机自建 T/N 的真实搬出、菜单与归位验证。"
    @Published var busy = false
    @Published var session: URL?
    @Published var ordinaryRows: [MenuBarIceSelectedTarget.Row] = []
    @Published var ordinaryWindowID: UInt32 = 0
    @Published var ordinaryStatus = "可选择一个普通应用图标，仅核验身份；自动搬移尚未接通。"
    private var ordinaryDirectory: MenuBarIceSelectedTarget.Directory?
    private var ordinaryTarget: MenuBarIceSelectedTarget?
    private var controllerPID: Int32?
    private var controllerProof: MenuBarProcessSignature.Proof?
    func readOrdinaryDirectory() {
        guard !busy else { return }
        ordinaryTarget = nil; ordinaryWindowID = 0
        do {
            let directory = try MenuBarIceSelectedTarget.readDirectory()
            ordinaryDirectory = directory; ordinaryRows = directory.rows
            ordinaryStatus = "请选择具体图标。刷新列表不会移动图标或打开菜单。"
        } catch {
            ordinaryDirectory = nil; ordinaryRows = []
            ordinaryStatus = "无法读取本机单屏图标列表：\(error)"
        }
    }
    func bindOrdinaryTarget() {
        ordinaryTarget = nil
        guard let directory = ordinaryDirectory,
              let row = ordinaryRows.first(where:{ $0.id == ordinaryWindowID }) else { return }
        do {
            ordinaryTarget = try MenuBarIceSelectedTarget.capture(row,from:directory)
            ordinaryStatus = "已核验 \(row.title) 的所选图标；自动搬移尚未接通。"
        } catch { ordinaryStatus = "图标或所属应用已改变，请刷新后重新选择。" }
    }
    func openSession() {
        guard !CommandLine.arguments.contains("--ice-candidate-ui-smoke"), !busy, session == nil else { return }; busy = true
        status = "正在核验组件和恢复状态…"
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached { try MenuBarIceCandidateProductBridge.preflight() }.value
                let prepared = try await Task.detached { try MenuBarIceCandidateProductBridge.command(["--prepare-ice-aligned"]) }.value
                guard let path = prepared["directory"] as? String else { throw Failure.message("没有有效的新会话。") }
                session = URL(fileURLWithPath:path)
                let launched = try await Task.detached { try MenuBarIceCandidateProductBridge.command(["--launch-session",path]) }.value
                controllerPID = ((launched["processes"] as? [String:Any])?["controller"] as? [String:Any])?["pid"] as? Int32
                if let controllerPID {
                    let proof = try MenuBarProcessSignature.read(controllerPID)
                    let config = try MenuBarIceCandidateProductBridge.configuration()
                    guard proof.identifier == "com.ryanai.mactools",
                          proof.executable == "/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController",
                          proof.sha256 == config.receipt["controllerSHA256"] as? String,
                          proof.launch != nil else { throw Failure.message("控制窗口身份无法核实。") }
                    controllerProof = proof
                }
                status = "测试窗口已打开。按“开始自建 T 单轮”；需要停止时按该窗口的“取消本轮”。"
            } catch { status = error.localizedDescription }
        }
    }
    func refresh() {
        guard let session else { return }
        do {
            let resultURL = session.appendingPathComponent("result.json")
            guard FileManager.default.fileExists(atPath:resultURL.path) else {
                status = "尚无终态结果，请查看测试窗口；关闭产品窗口不表示取消测试。"; return
            }
            let data = try Data(contentsOf:resultURL)
            guard data.count < 1_048_576, let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  result["nonce"] as? String == session.lastPathComponent.replacingOccurrences(of:"session-",with:""),
                  result["strictANYRequired"] as? Bool == false || (result["posts"] as? Int == 0) else { throw Failure.message("会话结果无法核实。") }
            let posts = result["posts"] as? Int ?? 0
            status = result["realClosedLoopVerified"] as? Bool == true
                ? "本轮搬出、菜单打开／关闭及归位通过（\(posts)次投递）。请保留证据。"
                : "本轮停止，未通过闭环（\(posts)次投递）。请查看结果并保留恢复责任。"
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
                Text("测试会短暂影响焦点和光标。当前闭环试用仅操作自建 T/N。")
                Text("搬出 T → 打开菜单 → 关闭菜单 → 等待15秒 → 原位归还").font(.callout)
                Text(model.status).textSelection(.enabled).accessibilityIdentifier("ice-candidate-status")
                HStack {
                    Button("打开 T/N 测试窗口") { model.openSession() }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.session != nil || CommandLine.arguments.contains("--ice-candidate-ui-smoke"))
                        .accessibilityIdentifier("ice-candidate-open-owned-session")
                    Button("显示控制窗口") { model.showController() }.disabled(model.session == nil)
                    Button("检查结果") { model.refresh() }.disabled(model.session == nil)
                    Button("查看证据") { model.showEvidence() }.disabled(model.session == nil)
                }
                Text("此候选目前仅供本机单屏自建项试用；普通应用图标的自动搬移尚未接入。取消请使用测试控制窗口的按钮。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
          }
          GroupBox("普通图标 · 只读选择") {
            VStack(alignment:.leading,spacing:10) {
                Text(model.ordinaryStatus).font(.callout)
                HStack {
                    Button("刷新图标列表") { model.readOrdinaryDirectory() }.disabled(model.busy)
                    Picker("目标",selection:$model.ordinaryWindowID) {
                        Text("请选择图标").tag(UInt32(0))
                        ForEach(model.ordinaryRows) { row in
                            Text("\(row.title) · \(row.id)").tag(row.id)
                        }
                    }.onChange(of:model.ordinaryWindowID) { _ in model.bindOrdinaryTarget() }
                }
            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
          }
        }
    }
}
#endif
