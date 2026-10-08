// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// Durable at-most-once attempt accounting, not input or movement authorization.
/// Both native real entry routes must consume the same round AND session files.
/// Partial/unknown writes stay consumed; this type has no reset or replay API.
enum MenuBarRealActionConsumption {
    enum Failure: Error { case binding }
    /// Only the native real broker can reach real attempt accounting. The
    /// shared low-level writer below does not turn JSON/test evidence into input
    /// authorization. A failed/unknown write still burns the attempt forever.
    static func consumeAuthorized(round: URL, session: URL, binding: MenuBarDispatchWitness.Binding,
                                  permit: MenuBarRealLocalAuthorization.Permit) throws {
        try permit.checkForRealAction(binding: binding)
        try consume(round: round, session: session, binding: binding)
    }
    static func consume(round: URL, session: URL, binding: MenuBarDispatchWitness.Binding) throws {
        guard binding.targetPID > 0, binding.controllerPID > 0,
              binding.controllerLaunch.isFinite, binding.controllerLaunch > 0,
              binding.controllerSHA256.count == 64,
              binding.controllerSHA256.allSatisfy({ $0.isHexDigit }) else { throw Failure.binding }
        let data = try JSONEncoder().encode(binding)
        // Includes file and parent-directory fsync, O_EXCL and O_NOFOLLOW.
        try MenuBarDispatchWitness.writeNew(data, to: round)
        try MenuBarDispatchWitness.writeNew(data, to: session.appendingPathComponent("run-consumed"))
    }
}
