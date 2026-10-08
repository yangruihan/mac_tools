import Foundation

struct MenuBarOwnedWidthBinding: Codable, Equatable {
    let itemKey: String
    let instance: UUID
    let pid: Int32
    let application: MenuBarApplicationIdentity
}
struct MenuBarOwnedWidthRecord: Codable, Equatable {
    let schemaVersion: Int
    let transaction: UUID
    let binding: MenuBarOwnedWidthBinding
    let originalLength: Double
    let originalBackingWidth: Double
    let environment: UUID
    func validate() throws {
        guard schemaVersion == 1, !binding.itemKey.isEmpty, binding.pid > 0,
              !binding.application.bundleID.isEmpty, !binding.application.bundlePath.isEmpty,
              binding.application.launch.isFinite,
              originalLength == -1 || (originalLength.isFinite && originalLength >= 0 && originalLength <= 2048),
              originalBackingWidth.isFinite, originalBackingWidth > 0, originalBackingWidth <= 4096 else {
            throw MenuBarNativeRevealController.Failure.recoveryRequired
        }
    }
}
@MainActor
protocol MenuBarOwnedWidthJournal: AnyObject {
    func load() throws -> MenuBarOwnedWidthRecord?
    func save(_ record: MenuBarOwnedWidthRecord) throws
    func clear() throws
}
@MainActor
final class MenuBarOwnedWidthFileJournal: MenuBarOwnedWidthJournal {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> MenuBarOwnedWidthRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16_384 else {
            throw MenuBarNativeRevealController.Failure.recoveryRequired
        }
        let record = try JSONDecoder().decode(MenuBarOwnedWidthRecord.self, from: Data(contentsOf: url))
        try record.validate(); return record
    }
    func save(_ record: MenuBarOwnedWidthRecord) throws {
        try record.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
