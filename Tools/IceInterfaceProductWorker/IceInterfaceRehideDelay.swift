import Foundation

/// Occupancy checks can themselves consume the last fraction of the delay.
/// Sample the remaining interval after those checks and never sleep a negative interval.
@MainActor enum IceInterfaceRehideDelay {
    static func wait(seconds: Double, clock: () -> Double, check: () throws -> Void,
                     pause: (Double) async throws -> Void) async throws {
        let deadline = clock() + seconds
        while clock() < deadline {
            try Task.checkCancellation()
            try check()
            let remaining = deadline - clock()
            guard remaining > 0 else { break }
            try await pause(min(0.1, remaining))
        }
    }
}
