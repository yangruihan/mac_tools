import Foundation

@MainActor enum IceRehideDelayChecks {
    enum Failure: Error { case assertion, inactiveRevoked }
    static func run() async throws -> [String: Any] {
        var assertions = 0
        func require(_ condition: Bool) throws { guard condition else { throw Failure.assertion }; assertions += 1 }
        var time = 100.0, pauses: [Double] = [], checks = 0
        try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1; time = 115.001 }, pause: { pauses.append($0) })
        try require(time >= 115 && pauses.isEmpty && checks == 1)
        // Reproduce the exact old loop's check-to-sleep boundary without executing
        // its fatal UInt64 conversion. The captured live crash proves that trap.
        try require(min(0.1, 115 - time) < 0)
        time = 100; pauses = []; checks = 0
        try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1 }, pause: { pauses.append($0); time += $0 })
        try require(time >= 115)
        try require(pauses.allSatisfy { $0 > 0 && $0 <= 0.1 })
        try require(abs(pauses.reduce(0, +) - 15) < 0.000001 && checks == pauses.count)
        time = 100; pauses = []; checks = 0
        var rejected = false
        do {
            try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: { checks += 1; throw Failure.inactiveRevoked }, pause: { pauses.append($0) })
        } catch Failure.inactiveRevoked { rejected = true }
        try require(rejected && pauses.isEmpty && checks == 1)
        time = 100; pauses = []
        let cancelled = Task { @MainActor in
            try await IceInterfaceRehideDelay.wait(seconds: 15, clock: { time }, check: {}, pause: { pauses.append($0) })
        }
        cancelled.cancel()
        rejected = false
        do { try await cancelled.value } catch is CancellationError { rejected = true }
        try require(rejected && pauses.isEmpty)
        return ["passed": true, "assertions": assertions, "nativePosts": 0,
                "deadlineCrossingInOccupancyCheckCovered": true, "delaySeconds": 15]
    }
}
