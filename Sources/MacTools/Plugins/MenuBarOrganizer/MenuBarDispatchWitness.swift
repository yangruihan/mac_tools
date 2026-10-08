// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import Darwin

/// Every native post must first persist a possible-effect marker. Missing
/// counters are never proof of zero. A sealed, armed witness with no marker is.
final class MenuBarDispatchWitness {
    struct Binding: Codable, Equatable {
        let nonce: UUID, targetPID: Int32, controllerPID: Int32, controllerLaunch: Double, controllerSHA256: String
    }
    struct NoDispatchProof: Codable, Equatable {
        let binding: Binding, transaction: UUID, owner: MenuBarHiddenMoveModel.Owner
        fileprivate init(binding: Binding, transaction: UUID, owner: MenuBarHiddenMoveModel.Owner) {
            self.binding = binding; self.transaction = transaction; self.owner = owner
        }
    }
    enum Failure: Error { case unsafe, sealed, possibleEffect, binding, io(Int32) }
    let directory: URL, binding: Binding
    private(set) var sealed = false
    private(set) var attempts = 0
    private var proof: NoDispatchProof?
    private let afterPersist: (String) -> Void
    init(directory: URL, binding: Binding, afterPersist: @escaping (String) -> Void = { _ in }) throws {
        self.directory = directory; self.binding = binding
        self.afterPersist = afterPersist
        var st = stat()
        guard lstat(directory.path, &st) == 0, st.st_uid == getuid(),
              st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), st.st_mode & 0o777 == 0o700,
              binding.targetPID > 0, binding.controllerPID > 0, binding.controllerLaunch > 0,
              binding.controllerSHA256.count == 64 else { throw Failure.unsafe }
        try Self.writeNew(try JSONEncoder().encode(binding), to: directory.appendingPathComponent("emission-guard-ready.json"))
    }
    func beforePost(route: String, windowID: UInt32) throws {
        guard !sealed else { throw Failure.sealed }
        if attempts == 0 {
            // Durable before any system call, including emergency release.
            let value: [String: Any] = ["nonce": binding.nonce.uuidString, "controllerPID": binding.controllerPID,
                "targetPID": binding.targetPID, "route": route, "windowID": windowID, "possibleEffect": true]
            try Self.writeNew(try JSONSerialization.data(withJSONObject: value), to: directory.appendingPathComponent("dispatch-started.json"))
        }
        attempts += 1
        afterPersist(route)
    }
    func sealNoDispatch(_ record: MenuBarHiddenMoveModel.Record) throws -> NoDispatchProof {
        guard record.phase == .prepared, record.plan.original.owner.nonce == binding.nonce,
              record.plan.original.owner.target.pid == binding.targetPID else { throw Failure.binding }
        var marker = stat()
        let markerStatus = lstat(directory.appendingPathComponent("dispatch-started.json").path, &marker)
        guard attempts == 0, markerStatus == -1, errno == ENOENT else { throw Failure.possibleEffect }
        if let proof { guard proof.transaction == record.transaction else { throw Failure.binding }; return proof }
        sealed = true
        let value = NoDispatchProof(binding: binding, transaction: record.transaction, owner: record.plan.original.owner)
        try Self.writeNew(try JSONEncoder().encode(value), to: directory.appendingPathComponent("no-dispatch-sealed.json"))
        proof = value; return value
    }
    static func writeNew(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure.io(errno) }; defer { close(fd) }
        try data.withUnsafeBytes { p in
            var offset = 0
            while offset < p.count {
                let n = write(fd, p.baseAddress!.advanced(by: offset), p.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.io(errno) }; offset += n
            }
        }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }
        let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw Failure.io(errno) }; defer { close(parent) }
        guard fsync(parent) == 0 else { throw Failure.io(errno) }
    }
}
