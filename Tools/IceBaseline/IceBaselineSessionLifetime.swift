// Copyright (c) 2026 Ryan.AI. MIT. Pure, monotonic, bounded fixture session.
import Foundation

struct IceBaselineSessionLifetime {
    enum Phase: String { case initializing, ready, active, cleaning, finished }
    enum Action: String { case ready, begin, cancel, terminal }
    enum Failure: Error { case expired, phase, duplicate }
    static let maximum = 200.0
    static let readyBudget = 120.0
    static let operationBudget = 50.0 // <=5s preflight + <=45s native engine.
    static let cleanupBudget = 15.0
    let born: Double
    private(set) var phase: Phase = .initializing
    private(set) var deadline: Double
    private(set) var reason = "initializing"
    private(set) var acknowledgment: String?
    private(set) var operationID: String?
    private var requests: Set<String> = []
    init(now: Double) { born = now; deadline = now + 10 }
    mutating func tick(now: Double) {
        guard phase != .finished else { return }
        if now >= born + Self.maximum {
            phase = .finished; reason = "absoluteDeadline"; deadline = born + Self.maximum
        } else if now >= deadline {
            if phase == .cleaning { phase = .finished; reason += ":cleanupDeadline" }
            else { clean(now: now, reason: "\(phase.rawValue)Deadline") }
        }
    }
    private mutating func clean(now: Double, reason: String) {
        phase = .cleaning; self.reason = reason
        deadline = min(now + Self.cleanupBudget, born + Self.maximum)
    }
    mutating func accept(_ action: Action, request: String, now: Double) throws {
        tick(now: now)
        guard phase != .finished else { throw Failure.expired }
        guard !requests.contains(request) else { throw Failure.duplicate }
        switch action {
        case .ready:
            guard phase == .initializing else { throw Failure.phase }
            phase = .ready; reason = "ready"
            deadline = min(now + Self.readyBudget, born + Self.maximum - Self.operationBudget - Self.cleanupBudget)
        case .begin:
            guard phase == .ready, now < deadline else { throw Failure.expired }
            phase = .active; reason = "active"; operationID = request
            deadline = min(now + Self.operationBudget, born + Self.maximum - Self.cleanupBudget)
        case .cancel, .terminal:
            // Repeated/new cleanup requests never renew a deadline or reopen work.
            if phase != .cleaning { clean(now: now, reason: action.rawValue) }
        }
        requests.insert(request); acknowledgment = request
    }
    func allowsEffects(operation: String, now: Double) -> Bool {
        phase == .active && operationID == operation && now < deadline && now < born + Self.maximum
    }
    func snapshot(now: Double) -> [String: Any] {
        ["phase":phase.rawValue,"reason":reason,"bornUptime":born,"deadlineUptime":deadline,
         "absoluteDeadlineUptime":born + Self.maximum,"atUptime":now,
         "acknowledgment":acknowledgment as Any? ?? NSNull(),"operationID":operationID as Any? ?? NSNull()]
    }

    // Freshness remains independent of the longer, bounded session lifetime.
    static func permitsEffects(_ snapshot: [String: Any], operation: String, now: Double) -> Bool {
        guard snapshot["phase"] as? String == Phase.active.rawValue,
              snapshot["operationID"] as? String == operation,
              let deadline = snapshot["deadlineUptime"] as? Double,
              let absolute = snapshot["absoluteDeadlineUptime"] as? Double,
              let at = snapshot["atUptime"] as? Double,
              deadline.isFinite, absolute.isFinite, at.isFinite, now.isFinite,
              (0...1).contains(now - at) else { return false }
        return now < deadline && now < absolute
    }
    struct Request {
        let id: String, controllerPID: Int32, action: Action
        init(_ value: [String: Any], nonce: String, fixturePID: Int32, now: Double) throws {
            guard value["nonce"] as? String == nonce, value["fixturePID"] as? Int32 == fixturePID,
                  let at = value["atUnix"] as? Double, at.isFinite, (0...1).contains(now - at),
                  let id = value["request"] as? String, UUID(uuidString: id) != nil,
                  let pid = value["controllerPID"] as? Int32, pid > 0,
                  let text = value["action"] as? String, let action = Action(rawValue: text)
            else { throw Failure.phase }
            self.id = id; self.controllerPID = pid; self.action = action
        }
    }
}
