// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// Isolated local-entry model. This is not an input attribution implementation.
/// Native wiring must supply a one-use equality proof from AppKit AND the tap;
/// no PID-only, coordinate-only, timestamp-only or recent-input exemption.
struct MenuBarLocalAcceptanceGate {
    struct StartProof: Equatable {
        let session: UUID, receipt: UUID, window: Int, eventNumber: Int
        let timestamp: UInt64, targetPID: Int32
    }
    enum State: Equatable { case preparing, ready, countdown, triggerProposed, terminal(String) }
    private(set) var state: State = .preparing
    private(set) var triggerCount = 0
    private(set) var matchedStartCount = 0
    private var deadline: UInt64?
    private var previousTime: UInt64 = 0
    private var ownPID: Int32 = 0
    private var ownWindow = 0
    let session: UUID
    init(session: UUID) { self.session = session }
    mutating func prepared(pid: Int32, window: Int) {
        if state == .preparing, pid > 0, window > 0 { ownPID = pid; ownWindow = window; state = .ready }
    }
    mutating func start(appKit: StartProof, tap: StartProof, now: UInt64) {
        guard state == .ready else { return }
        guard appKit == tap, appKit.session == session, appKit.targetPID == ownPID,
              appKit.window == ownWindow, appKit.timestamp > 0 else {
            state = .terminal("开始按钮事件未得到双端匹配，未触发")
            return
        }
        matchedStartCount = 1
        previousTime = now; deadline = now + 3000; state = .countdown
    }
    mutating func activity() {
        if state == .countdown || state == .triggerProposed { state = .terminal("检测到其他活动，已停止") }
    }
    mutating func cancel() {
        if case .terminal = state { return }
        state = .terminal("已取消")
    }
    mutating func tick(now: UInt64, monitorHealthy: Bool) {
        guard state == .countdown, let deadline else { return }
        guard monitorHealthy, now >= previousTime, now - previousTime <= 500 else {
            state = .terminal("监听失效或倒计时中断，未触发"); return
        }
        previousTime = now
        if now >= deadline { triggerCount += 1; state = .triggerProposed }
    }
    func remainingSeconds(now: UInt64) -> Int {
        guard state == .countdown, let deadline, deadline > now else { return 0 }
        return Int((deadline - now + 999) / 1000)
    }
}
