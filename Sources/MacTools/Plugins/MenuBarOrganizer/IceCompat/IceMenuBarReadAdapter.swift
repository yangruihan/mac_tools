// Portions adapted from Ice 0.11.12, Jordan Baird and contributors, GNU GPL v3.
// Ryan.AI modifications, 2026-10-03. See THIRD_PARTY_NOTICES.md/COPYING.GPL-3.0.
import Foundation
import CoreGraphics
import Darwin

protocol IceMenuBarWindowSource {
    var profile: MenuBarHiddenMoveModel.Profile { get }
    func read() throws -> IceMenuBarReadAdapter.Directory
}

struct IceMenuBarReadAdapter {
    enum Policy: Equatable { case disabled, isolatedReadOnly }
    enum Failure: Error, Equatable { case disabled, unsupportedProfile, incomplete, unstableSpace, geometry, membership }
    struct Member: Equatable {
        let windowID: UInt32
        let frame: CGRect // Hidden negative coordinates are preserved.
        let spaces: [UInt64]
    }
    struct Directory: Equatable {
        let memberIDs: [UInt32] // Original native enumeration, not a rank claim.
        let members: [Member]
        let spaceBefore: UInt64
        let spaceAfter: UInt64
        let enumerationComplete: Bool
        var logicalOrderProven: Bool { false }
    }
    private let policy: Policy
    private let source: any IceMenuBarWindowSource
    init() { policy = .disabled; source = NativeSource(audit: { _ in }) }
    init(policy: Policy, source: any IceMenuBarWindowSource) { self.policy = policy; self.source = source }
    static func isolatedReadOnly(audit: @escaping (String) -> Void = { _ in }) -> Self {
        Self(policy: .isolatedReadOnly, source: NativeSource(audit: audit))
    }

    // There is no event sender, relocation API, permission request or app hook.
    // Tests inject a source; no test creates or calls the native bindings.
    func read() throws -> Directory {
        guard policy == .isolatedReadOnly else { throw Failure.disabled }
        guard source.profile == .trial else { throw Failure.unsupportedProfile }
        let value = try source.read()
        guard value.enumerationComplete else { throw Failure.incomplete }
        guard value.spaceBefore > 0, value.spaceBefore == value.spaceAfter else { throw Failure.unstableSpace }
        guard value.members.count <= 512, !value.memberIDs.contains(0),
              Set(value.memberIDs).count == value.memberIDs.count,
              Set(value.members.map(\.windowID)).count == value.members.count,
              Set(value.members.map(\.windowID)) == Set(value.memberIDs) else { throw Failure.membership }
        guard value.members.allSatisfy({ member in
            let f = member.frame
            return !f.isNull && !f.isInfinite && f.minX.isFinite && f.minY.isFinite
                && f.maxX.isFinite && f.maxY.isFinite && f.width > 0 && f.height > 0
                && !member.spaces.isEmpty && !member.spaces.contains(0)
                && Set(member.spaces).count == member.spaces.count
        }) else { throw Failure.geometry }
        return value // No filtering off-Space or hidden members to manufacture success.
    }

    private struct NativeSource: IceMenuBarWindowSource {
        let audit: (String) -> Void
        var profile: MenuBarHiddenMoveModel.Profile {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            var size = 0
            guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0, size <= 256 else {
                return .init(version: "unknown", build: "unknown", architecture: "unknown")
            }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else {
                return .init(version: "unknown", build: "unknown", architecture: "unknown")
            }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "unsupported"
            #endif
            return .init(version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                         build: String(cString: bytes), architecture: architecture)
        }
        func read() throws -> Directory { try IcePrivateWindowAPI.Bindings(audit: audit).read() }
    }
}
