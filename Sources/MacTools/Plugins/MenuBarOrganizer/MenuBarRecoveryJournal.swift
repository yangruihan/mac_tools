import Foundation
import CoreGraphics

struct MenuBarRecordedTarget: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
    let application: MenuBarApplicationIdentity?
    init(_ target: MenuBarStatusTarget) {
        windowID = target.id; pid = target.pid; application = target.application
    }
}
struct MenuBarRestoreAnchor: Codable, Equatable {
    enum Section: String, Codable { case hidden, visible }
    let displayID: UInt32
    let section: Section
    let left: MenuBarRecordedTarget?
    let right: MenuBarRecordedTarget?
}
struct MenuBarRecoveryRecord: Codable, Equatable {
    enum Phase: String, Codable { case prepared, moved }
    let schemaVersion: Int
    let transactionID: UUID
    let target: MenuBarRecordedTarget
    let anchor: MenuBarRestoreAnchor
    var phase: Phase
    init(transactionID: UUID, target: MenuBarRecordedTarget, anchor: MenuBarRestoreAnchor, phase: Phase) {
        schemaVersion = 1; self.transactionID = transactionID; self.target = target; self.anchor = anchor; self.phase = phase
    }
}
protocol MenuBarRecoveryJournal {
    func load() throws -> MenuBarRecoveryRecord?
    func save(_ record: MenuBarRecoveryRecord) throws
    func clear() throws
}
final class MenuBarFileRecoveryJournal: MenuBarRecoveryJournal {
    enum Failure: Error { case invalidRecord }
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> MenuBarRecoveryRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 65_536 else { throw Failure.invalidRecord }
        let record = try JSONDecoder().decode(MenuBarRecoveryRecord.self, from: Data(contentsOf: url))
        try validate(record)
        return record
    }
    func save(_ record: MenuBarRecoveryRecord) throws {
        try validate(record)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func validate(_ record: MenuBarRecoveryRecord) throws {
        guard record.schemaVersion == 1, let application = record.target.application,
              application.launch.isFinite, !application.bundleID.isEmpty,
              record.target.windowID > 0, record.target.pid > 0 else { throw Failure.invalidRecord }
        let neighbors = [record.anchor.left, record.anchor.right].compactMap { $0 }
        guard !neighbors.isEmpty, neighbors.allSatisfy({ neighbor in
            neighbor.application != nil && neighbor.windowID > 0 && neighbor.pid > 0
                && neighbor.windowID != record.target.windowID
        }) else { throw Failure.invalidRecord }
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

