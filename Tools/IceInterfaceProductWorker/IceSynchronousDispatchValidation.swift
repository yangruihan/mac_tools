import Foundation

/// One synchronous dispatch gets one complete fresh identity/scope/ownership
/// sample. There is no async body and no reusable permit or timer cache.
@MainActor final class IceSynchronousDispatchValidation {
    typealias Scope = (UInt32, UInt)
    enum Failure: Error { case nestedDispatch, changedScope }
    private let read: () throws -> Scope, readScope: () -> Scope, clock: () -> Double
    private let readFinal: () throws -> Scope
    private let trace: (([String: Any]) -> Void)?
    private var current: Scope?
    init(read: @escaping () throws -> Scope, scope: @escaping () -> Scope,
         final: (() throws -> Scope)? = nil,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         trace: (([String: Any]) -> Void)? = nil) {
        self.read = read; readScope = scope; self.clock = clock; self.trace = trace
        readFinal = final ?? { scope() }
    }
    func perform(_ body: () throws -> Void) throws {
        guard current == nil else { throw Failure.nestedDispatch }
        let start = clock(), value = try read()
        current = value
        defer { current = nil }
        trace?(["elapsedMS": (clock() - start) * 1000, "display": value.0, "space": value.1,
                "scope": "oneSynchronousActualPost", "sharedAcrossPosts": false])
        try body()
    }
    func validateRuntime() throws { if current == nil { _ = try read() } }
    func validateBeforePost() throws {
        guard let current else { _ = try read(); return }
        let final = try readFinal()
        guard final.0 == current.0, final.1 == current.1 else { throw Failure.changedScope }
    }
    func scope() -> Scope { current ?? readScope() }
}
