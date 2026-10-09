// Ice-derived receipt-driven route waiting. GPL-3.0; see THIRD_PARTY_NOTICES.md.
import AppKit

// All receipt, timeout and cancellation transitions serialize on MainActor.
// Only the actual callback time admits a receipt; a posted event timestamp is
// never evidence of timely delivery. A delayed consumer does not undo an ACK
// that was already accepted inside the original absolute 50ms deadline.
@MainActor final class IceSelectedReceiptWait {
    let deadline: Double
    private let clock: () -> Double
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private(set) var acceptedAt: Double?
    private(set) var settlementCount = 0
    var pending: Bool { result == nil }
    init(deadline: Double, clock: @escaping () -> Double) { self.deadline=deadline;self.clock=clock }
    func install(_ continuation: CheckedContinuation<Void, Error>) {
        precondition(self.continuation == nil)
        if let result { continuation.resume(with:result) } else { self.continuation=continuation }
    }
    func setTimeout(_ task: Task<Void, Never>) {
        if pending { timeoutTask=task } else { task.cancel() }
    }
    @discardableResult func received() -> Bool {
        guard pending else { return false }
        return received(at:clock())
    }
    @discardableResult func received(at now:Double) -> Bool {
        guard pending else{return false}
        guard now.isFinite,now<deadline else { fail(IceBaselineError.timeout);return false }
        acceptedAt=now;resolve(.success(()));return true
    }
    @discardableResult func fail(_ error: Error) -> Bool {
        guard pending else { return false };resolve(.failure(error));return true
    }
    private func resolve(_ result: Result<Void, Error>) {
        guard pending else { return }
        self.result=result;settlementCount+=1
        timeoutTask?.cancel();timeoutTask=nil
        let waiting=continuation;continuation=nil;waiting?.resume(with:result)
    }
}
