// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

/// A diagnostic receipt, never an authorization input. The scalar context stays
/// encodable even if an invalid floating-point value breaks the full snapshot.
enum MenuBarLocalDiagnosticReceipt {
    struct Context: Codable {
        let nonce: UUID, controllerPID: Int32, scope: String, failure: String?
        let state, startupStage: String
        let nodeCount: Int, firstFailure: MenuBarLocalContinuityLedger.FirstFailure?
    }
    struct Envelope: Codable {
        let schemaVersion: Int, context: Context
        let payload: Data?, payloadEncodingFailure: String?
        let primaryWriteFailure: String?
    }
    static func encode<T: Encodable>(_ value: T, context: Context, primaryWriteFailure: String? = nil) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload: Data?, failure: String?
        do { payload = try encoder.encode(value); failure = nil }
        catch { payload = nil; failure = String(describing: error) }
        return try encoder.encode(Envelope(schemaVersion: 1, context: context, payload: payload,
            payloadEncodingFailure: failure, primaryWriteFailure: primaryWriteFailure))
    }
}
