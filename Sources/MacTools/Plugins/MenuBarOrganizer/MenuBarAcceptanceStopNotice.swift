// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// Display-only state after the worker has saved its final receipt and removed
/// both taps. It cannot restart the input proof, issue a permit or call a sender.
struct MenuBarAcceptanceStopNotice {
    enum State: Equatable { case idle, showing, closed }
    private(set) var state: State = .idle
    private(set) var deadline: UInt64?
    private var lastTime: UInt64?
    static let readDuration: UInt64 = 30_000_000_000

    mutating func begin(at now: UInt64, receiptWritten: Bool, inputsStopped: Bool,
                        notAfter: UInt64 = .max) -> Bool {
        guard state == .idle else { return false }
        let end = now.addingReportingOverflow(Self.readDuration)
        guard receiptWritten, inputsStopped, !end.overflow, notAfter > now else { close(); return false }
        deadline = min(end.partialValue, notAfter); lastTime = now; state = .showing
        return true
    }
    mutating func expire(at now: UInt64) -> Bool {
        guard state == .showing, let deadline, let lastTime else { return state == .closed }
        guard now >= lastTime, now < deadline else { close(); return true }
        self.lastTime = now
        return false
    }
    mutating func close() { state = .closed }

    static func message(cause: MenuBarLocalContinuityLedger.Cause?, cancelled: Bool,
                        expired: Bool, fullCyclePassed: Bool,
                        sessionPosts: Int?, pidPosts: Int?, pendingRecovery: Bool?,
                        operationFailure: String? = nil,
                        bindingRejection: MenuBarRealLocalAuthorization.BindingRejection? = nil) -> String {
        let emitted = sessionPosts.flatMap { a in pidPosts.flatMap { b in
            a >= 0 && b >= 0 ? (a > 0 || b > 0) : nil
        } }
        let heading: String
        if fullCyclePassed, emitted == true, pendingRecovery == false {
            heading = "自建 T 已完成移动、菜单打开/关闭与归位。"
        } else if cancelled { heading = "本轮已取消。" }
        else if expired { heading = "等待开始已超时，本轮已结束。" }
        else {
            switch cause {
            case .laterInput: heading = "检测到开始之后的新输入活动，已保护停止。活动来源尚未确定。"
            case .hidActivityUnproven, .hidChangedAcrossStart:
                heading = "无法确认输入活动处于允许的时间范围，已保护停止。"
            case .monitorLost: heading = "输入监听失效，已保护停止。"
            case .missingReceiptPredecessor: heading = "开始事件接收前的连续采样记录缺失，已停止。"
            case .unprovenReceiptActivity: heading = "开始事件匹配期间的输入时间无法确认，已停止。"
            case .overflow: heading = "输入记录超过安全容量，已保护停止。"
            case .cancelled: heading = "本轮已取消。"
            default:
                if let rejection = bindingRejection {
                    switch rejection.check {
                    case .processIdentity: heading = "控制程序的进程或签名身份与本轮记录不一致，已停止。"
                    case .requestProof: heading = "输入证明与本轮请求记录不一致，已停止。"
                    case .layoutCommit:
                        heading = "许可前的稳定布局采集、身份或连续性检查未通过，已停止。\n具体原因：\((operationFailure ?? "layoutCommit").prefix(240))"
                    case .inputPlan:
                        if rejection.failedFields.contains("plan.items") {
                            heading = "准备后菜单栏图标的位置或可见状态已变化，动作前检查停止了本轮。"
                        } else if rejection.failedFields.contains("plan.scope") {
                            heading = "准备后显示器或桌面环境已变化，动作前检查停止了本轮。"
                        } else { heading = "动作前目标或输入证明与准备记录不一致，已停止。" }
                    }
                } else if operationFailure == "binding" {
                    heading = "动作前身份、布局或输入证明的绑定检查未通过，已停止；本次记录未细分字段。"
                } else if let operationFailure, !operationFailure.isEmpty {
                    heading = "本轮验收未通过，已停止。\n具体原因：\(operationFailure.prefix(240))"
                } else { heading = "本轮验收未通过，已停止。" }
            }
        }
        let emission: String
        switch emitted {
        case false: emission = "未发送鼠标事件；未执行图标移动。"
        case true: emission = "本轮已发送鼠标事件，结果见本次记录。"
        case nil: emission = "发送状态未能确认，结果见本次记录。"
        }
        let recovery: String
        switch pendingRecovery {
        case false: recovery = "没有待恢复责任。"
        case true: recovery = "恢复责任仍保留，需处理本次恢复记录。"
        case nil: recovery = "恢复状态未能确认，需检查本次记录。"
        }
        return "\(heading)\n\(emission)\n\(recovery)\n\n输入监听已关闭。此窗口仅展示结果，可关闭；最多显示 30 秒。"
    }
}
