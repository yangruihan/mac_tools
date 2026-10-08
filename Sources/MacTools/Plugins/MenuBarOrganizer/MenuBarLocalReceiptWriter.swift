// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import Darwin

enum MenuBarLocalReceiptWriter {
    enum Failure: Error { case io(Int32) }
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
