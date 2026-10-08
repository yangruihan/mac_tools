// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// A single monotonic budget shared by diagnostic setup and ready sampling.
/// Does not start a listener, authorize input or extend an expired observation.
struct MenuBarLocalObservationBudget: Encodable {
    enum Failure: Error { case clock, invalidDuration }
    static let tenSeconds: UInt64 = 10_000_000_000
    let began, deadline: UInt64

    init(began: UInt64, duration: UInt64 = Self.tenSeconds) throws {
        let end = began.addingReportingOverflow(duration)
        guard duration > 0 else { throw Failure.invalidDuration }
        guard !end.overflow else { throw Failure.clock }
        self.began = began; deadline = end.partialValue
    }

    func remaining(at now: UInt64) throws -> UInt64 {
        guard now >= began else { throw Failure.clock }
        return now < deadline ? deadline - now : 0
    }

    func waitSeconds(at now: UInt64, maximum: UInt64) throws -> TimeInterval {
        Double(min(try remaining(at: now), maximum)) / 1_000_000_000
    }

    func observe(now: () -> UInt64, poll: () throws -> Void, wait: (TimeInterval) -> Void) throws {
        while try remaining(at: now()) > 0 {
            try poll()
            // Include the poll's duration. Never add an uncapped final wait or
            // a final poll after the deadline, including a late scheduler wake.
            let seconds = try waitSeconds(at: now(), maximum: 100_000_000)
            if seconds > 0 { wait(seconds) }
        }
    }
}
