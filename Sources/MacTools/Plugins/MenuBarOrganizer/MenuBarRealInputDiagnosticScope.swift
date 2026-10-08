// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import Darwin

/// A separate diagnostic namespace; no path points at a real action/session.
enum MenuBarRealInputDiagnosticScope {
    #if REQUEST_WARMUP_DIAGNOSTIC
    static let mode = "--request-warmup-diagnostic"
    static let root = URL(fileURLWithPath: "/tmp/mac-tools-request-warmup-diagnostic")
    #else
    static let mode = "--real-input-diagnostic"
    static let root = URL(fileURLWithPath: "/tmp/mac-tools-real-input-diagnostic")
    #endif
    static let executable = root.appendingPathComponent("Real Input Diagnostic.app/Contents/MacOS/RealInputDiagnostic")
    enum Failure: Error { case scope, permission, output }
    static func validate(_ directory: URL, nonce: UUID) throws {
        var st = stat(), parent = stat()
        guard directory.deletingLastPathComponent().resolvingSymlinksInPath() == root.resolvingSymlinksInPath(),
              directory.lastPathComponent == "session-" + nonce.uuidString.lowercased(),
              lstat(root.path, &parent) == 0, parent.st_mode & S_IFMT == S_IFDIR, parent.st_uid == getuid(),
              lstat(directory.path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR,
              st.st_uid == getuid(), st.st_mode & 0o777 == 0o700 else { throw Failure.scope }
    }
}
