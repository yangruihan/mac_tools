import Foundation
import CryptoKit
import Darwin

/// Isolated synchronous storage. No runtime uses this adapter or executes model actions.
/// The caller owns a trusted parent directory and supplies an authenticated Owner.
/// A checksum detects accidental damage; it does not authenticate another same-user process.
final class MenuBarTemporaryMoveJournal {
    typealias Record = MenuBarTemporaryMoveModel.Record
    typealias Owner = MenuBarTemporaryMoveModel.Owner
    enum Failure: Error, Equatable {
        case busy, unsafeFile, tooLarge, corrupt, identity, stale, transition, io(Int32)
    }
    enum Point { case temporaryCreated, fileSynced, renamed, directorySynced, removed }
    private struct Envelope: Codable {
        let version: Int
        let checksum: String
        let payload: Data
    }
    private let directory: URL
    private let mutex = NSLock()
    private let fault: (Point) throws -> Void
    private var directoryIdentity: (dev_t, ino_t)?
    private let filename = "temporary-move-v1.json" // Separate from existing width journals.
    private let limit = 524_288

    init(directory: URL, fault: @escaping (Point) throws -> Void = { _ in }) {
        // Canonicalize only the trusted parent. The leaf itself must not be a symlink.
        self.directory = directory.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(directory.lastPathComponent, isDirectory: true)
        self.fault = fault
    }
    func inspect() throws -> Record? { try locked { try read($0) } }
    func load(boundTo owner: Owner) throws -> Record? {
        try locked { fd in
            guard let record = try read(fd) else { return nil }
            guard record.plan.original.owner == owner else { throw Failure.identity }
            return record
        }
    }
    /// Compare-and-swap. An exact repeated save is idempotent, never a new action.
    func persist(_ record: Record, replacing expected: Record?, boundTo owner: Owner) throws -> Record {
        try validate(record)
        guard record.plan.original.owner == owner else { throw Failure.identity }
        let bytes = try encode(record)
        return try locked { fd in
            // The private leaf may have just been created. Persist its parent
            // entry as well before returning a receipt, including exact retries.
            let parent = open(directory.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parent >= 0 else { throw Failure.unsafeFile }
            defer { Darwin.close(parent) }
            try sync(parent)
            let current = try read(fd) // Corruption/unsafe files are never overwritten.
            if current == record {
                try syncExisting(fd)
                return record
            }
            guard current == expected else { throw Failure.stale }
            if let current {
                guard current.plan.original.owner == owner else { throw Failure.identity }
                guard current.transaction == record.transaction, current.plan == record.plan,
                      Self.canAdvance(current.phase, record.phase) else { throw Failure.transition }
            } else {
                guard record.phase == .prepared else { throw Failure.transition }
            }
            let temporary = ".temporary-move-\(UUID().uuidString).tmp"
            let output = openat(fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard output >= 0 else { throw Failure.io(errno) }
            defer { Darwin.close(output); unlinkat(fd, temporary, 0) }
            try fault(.temporaryCreated)
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(output, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw Failure.io(count == 0 ? EIO : errno) }
                    offset += count
                }
            }
            try sync(output); try fault(.fileSynced)
            guard renameat(fd, temporary, fd, filename) == 0 else { throw Failure.io(errno) }
            try fault(.renamed)
            try sync(fd); try fault(.directorySynced)
            return record
        }
    }
    /// Only the matching restored record may be removed. No arbitrary clear API.
    func clear(_ restored: Record, boundTo owner: Owner) throws {
        try validate(restored)
        guard restored.phase == .restored else { throw Failure.transition }
        guard restored.plan.original.owner == owner else { throw Failure.identity }
        try locked { fd in
            if let current = try read(fd) {
                guard current == restored else { throw Failure.stale }
                guard unlinkat(fd, filename, 0) == 0 else { throw Failure.io(errno) }
                try fault(.removed)
            }
            try sync(fd) // A repeated clear acknowledges durable absence, not a move.
        }
    }
    private func locked<T>(_ body: (Int32) throws -> T) throws -> T {
        guard mutex.try() else { throw Failure.busy }
        defer { mutex.unlock() }
        guard mkdir(directory.path, mode_t(0o700)) == 0 || errno == EEXIST else { throw Failure.io(errno) }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_mode & 0o777 == 0o700 else { throw Failure.unsafeFile }
        if let previous = directoryIdentity {
            guard previous.0 == info.st_dev, previous.1 == info.st_ino else { throw Failure.unsafeFile }
        } else { directoryIdentity = (info.st_dev, info.st_ino) }
        let lockFD = openat(fd, ".temporary-move.lock", O_RDWR | O_CREAT | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard lockFD >= 0 else { throw Failure.unsafeFile }
        defer { Darwin.close(lockFD) }
        try safeRegular(lockFD)
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(lockFD, LOCK_UN) }
        return try body(fd)
    }
    private func safeRegular(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_mode & 0o777 == 0o600 else { throw Failure.unsafeFile }
        guard info.st_size >= 0, info.st_size <= limit else { throw Failure.tooLarge }
    }
    private func read(_ directoryFD: Int32) throws -> Record? {
        let input = openat(directoryFD, filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if input < 0 {
            if errno == ENOENT { return nil }
            throw Failure.unsafeFile
        }
        defer { Darwin.close(input) }
        try safeRegular(input)
        var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.io(errno) }
            if count == 0 { break }
            guard bytes.count + count <= limit else { throw Failure.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            guard envelope.version == 1, envelope.checksum == Self.checksum(envelope.payload) else { throw Failure.corrupt }
            let record = try JSONDecoder().decode(Record.self, from: envelope.payload)
            try validate(record); return record
        } catch { throw Failure.corrupt }
    }
    private func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(record)
        let bytes = try encoder.encode(Envelope(version: 1, checksum: Self.checksum(payload), payload: payload))
        guard bytes.count <= limit else { throw Failure.tooLarge }
        return bytes
    }
    private func validate(_ record: Record) throws {
        guard record.schemaVersion == 1 else { throw Failure.corrupt }
        do { try record.plan.validateStructure() } catch { throw Failure.corrupt }
    }
    private func sync(_ fd: Int32) throws {
        while fsync(fd) != 0 { if errno != EINTR { throw Failure.io(errno) } }
    }
    private func syncExisting(_ fd: Int32) throws {
        let input = openat(fd, filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { throw Failure.unsafeFile }
        defer { Darwin.close(input) }
        try safeRegular(input); try sync(input); try sync(fd)
    }
    private static func checksum(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func canAdvance(_ a: Record.Phase, _ b: Record.Phase) -> Bool {
        switch a {
        case .prepared: return [.moved, .restorePrepared, .restored].contains(b)
        case .moved: return [.restorePrepared, .restored].contains(b)
        case .restorePrepared: return b == .restored
        case .restored: return false
        }
    }
}
