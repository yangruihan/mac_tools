// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import Darwin

/// Cancel is bound to this worker and transaction. No file grants a local start.
final class MenuBarRealRunControl {
    enum Failure: Error { case invalidRequest, remoteStart, cancelled }
    let directory: URL, binding: MenuBarDispatchWitness.Binding, transaction: String
    private(set) var cancelled = false
    init(directory: URL, binding: MenuBarDispatchWitness.Binding, transaction: String) {
        self.directory = directory; self.binding = binding; self.transaction = transaction
    }
    func read(now: Double = Date().timeIntervalSince1970) throws -> Bool {
        if cancelled { return true }
        var info = stat()
        if lstat(directory.appendingPathComponent("action-request.json").path, &info) == 0 || errno != ENOENT {
            throw Failure.remoteStart
        }
        let file = directory.appendingPathComponent("cancel-preparation.json")
        guard lstat(file.path, &info) == 0 else {
            guard errno == ENOENT else { throw Failure.invalidRequest }; return false
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1, info.st_size <= 4096,
              let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              value["nonce"] as? String == binding.nonce.uuidString,
              value["pid"] as? Int32 == binding.targetPID, value["controllerPID"] as? Int32 == binding.controllerPID,
              value["transaction"] as? String == transaction, value["action"] as? String == "cancel-preparation",
              let at = value["atUnix"] as? Double, at.isFinite, now.isFinite, (0...2).contains(now - at)
        else { throw Failure.invalidRequest }
        cancelled = true; return true
    }
}
