// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// Software admission fence, not physical-input exclusion. An admitted native
/// call can finish after stop arrives. Only an explicit operation gets a new
/// instance; quiet, receipts and successful observations never reset it.
final class MenuBarOperationStop {
    enum Reason: String, Codable { case cancelled, externalInput, monitorLost, interference, failed, possibleDown }
    enum Failure: Error, Equatable { case stopped(Reason), busy, wrongThread }
    struct Snapshot: Codable {
        let generation: UUID, reason: Reason?, effectInFlight: String?
        let effectsAdmitted: Int
    }
    let generation = UUID()
    private let lock = NSRecursiveLock()
    private var reason: Reason?
    private var inFlight: String?
    private var admitted = 0
    private var cancellation: (() -> Bool)?
    private var cancellationOwner: Thread?
    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(generation: generation, reason: reason, effectInFlight: inFlight, effectsAdmitted: admitted)
    }
    func request(_ cause: Reason) {
        lock.lock(); defer { lock.unlock() }
        if reason == nil { reason = cause }
    }
    func check() throws {
        lock.lock()
        // Validate before copying the scoped callback. Teardown cannot run
        // concurrently with an invocation on its owning thread.
        if let owner = cancellationOwner, owner !== Thread.current {
            lock.unlock(); throw Failure.wrongThread
        }
        let callback = cancellation; lock.unlock()
        if callback?() == true { request(.cancelled) }
        lock.lock(); defer { lock.unlock() }
        if let reason { throw Failure.stopped(reason) }
    }
    func withCancellation<T>(_ callback: () -> Bool, _ body: () throws -> T) throws -> T {
        try withoutActuallyEscaping(callback) { liveCallback in
            lock.lock()
            guard cancellation == nil else { lock.unlock(); throw Failure.busy }
            cancellation = liveCallback; cancellationOwner = Thread.current; lock.unlock()
            defer { lock.lock(); cancellation = nil; cancellationOwner = nil; lock.unlock() }
            return try body()
        }
    }
    /// Release the lock before body: stop remains available while this single
    /// admitted effect is in flight. Prior admission cannot be revoked, including
    /// the interval before entering OS. Physical input versus post is not atomic.
    func perform<T>(_ effect: String, _ body: () throws -> T) throws -> T {
        try check()
        lock.lock()
        if let reason { lock.unlock(); throw Failure.stopped(reason) }
        guard inFlight == nil else { lock.unlock(); throw Failure.busy }
        inFlight = effect; admitted += 1
        lock.unlock()
        defer { lock.lock(); inFlight = nil; lock.unlock() }
        do { return try body() }
        catch { request(.failed); throw error }
    }
}
