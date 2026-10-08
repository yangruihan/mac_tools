// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import CryptoKit
import Foundation
import Darwin

/// Durable, append-only, bound stage evidence. A failed or ambiguous write
/// poisons the recorder; it cannot retry under another filename and pass.
final class MenuBarMoveStageRecorder {
    struct Record: Codable {
        let schemaVersion: Int, sequence: Int
        let nonce: UUID, controllerPID: Int32
        let stage: String, previousSHA256: String?
        let payload: Data
    }
    struct Pair: Codable { let first, second: MenuBarHiddenMoveModel.Snapshot }
    enum Failure: Error { case poisoned, stage, directory }
    let directory: URL, nonce: UUID, controllerPID: Int32
    private(set) var count = 0, poisoned = false
    private(set) var head: String?
    private let write: (Data, URL) throws -> Void
    init(directory: URL, nonce: UUID, controllerPID: Int32,
         write: @escaping (Data, URL) throws -> Void = MenuBarDispatchWitness.writeNew) throws {
        self.directory = directory; self.nonce = nonce; self.controllerPID = controllerPID; self.write = write
        guard controllerPID > 0, mkdir(directory.path, 0o700) == 0 else { throw Failure.directory }
    }
    func append<T: Encodable>(_ stage: String, _ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        do { try appendPayload(stage, encoder.encode(value)) }
        catch { poisoned = true; throw error }
    }
    func appendJSON(_ stage: String, _ value: [String: Any]) throws {
        do { try appendPayload(stage, JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) }
        catch { poisoned = true; throw error }
    }
    private func appendPayload(_ stage: String, _ payload: Data) throws {
        guard !poisoned else { throw Failure.poisoned }
        guard !stage.isEmpty, stage.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw Failure.stage }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let record = Record(schemaVersion: 1, sequence: count + 1, nonce: nonce, controllerPID: controllerPID,
                stage: stage, previousSHA256: head, payload: payload)
            let data = try encoder.encode(record)
            try write(data, directory.appendingPathComponent(String(format: "%04d-", count + 1) + stage + ".json"))
            head = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); count += 1
        } catch { poisoned = true; throw error }
    }
}
