// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation
import Security
import CryptoKit
import Darwin

enum MenuBarProcessSignature {
    struct Proof: Codable, Equatable {
        let pid: Int32
        let launch: Double? // Required for an app target, unnecessary for carrier role.
        let executable: String
        let identifier: String
        let team: String?
        let sha256: String
        let appleAnchor: Bool
    }
    enum Failure: Error { case process(String, Int32, Int32), signature, changed }
    /// Carrier classification is not target authorization. Validate the live
    /// guest itself before/after reading its signed executable; no proc_pidinfo
    /// call, static-name substitute, privilege change or denied-read retry.
    static func readCarrier(_ pid: Int32) throws -> Proof {
        guard pid > 0 else { throw Failure.signature }
        var guest: SecCode?, code: SecStaticCode?, data: CFDictionary?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &guest) == errSecSuccess,
              let guest,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.WindowServer\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCheckValidity(guest, [], requirement) == errSecSuccess,
              SecCodeCopyStaticCode(guest, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &data) == errSecSuccess,
              let info = data as? [String: Any], let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let executable = info[kSecCodeInfoMainExecutable as String] as? URL,
              executable.resolvingSymlinksInPath().path == "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer" else { throw Failure.signature }
        let sha = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        guard SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else { throw Failure.changed }
        return .init(pid: pid, launch: nil, executable: executable.resolvingSymlinksInPath().path,
            identifier: identifier, team: info[kSecCodeInfoTeamIdentifier as String] as? String, sha256: sha, appleAnchor: true)
    }
    static func read(_ pid: Int32) throws -> Proof {
        func process() throws -> (String, Double) {
            var bsd = proc_bsdinfo(), bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let infoCount = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard pid > 0, infoCount == MemoryLayout<proc_bsdinfo>.size, bsd.pbi_start_tvsec > 0 else {
                throw Failure.process("bsd-start", infoCount, errno)
            }
            let pathCount = bytes.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            guard pathCount > 0 else { throw Failure.process("path", pathCount, errno) }
            return (URL(fileURLWithPath: String(cString: bytes)).resolvingSymlinksInPath().path,
                    Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1_000_000)
        }
        let before = try process()
        var dynamic: SecCode?, code: SecStaticCode?, data: CFDictionary?, apple: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &dynamic) == errSecSuccess,
              let dynamic, SecCodeCheckValidity(dynamic, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopyStaticCode(dynamic, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &data) == errSecSuccess,
              let info = data as? [String: Any], let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let signedExecutable = info[kSecCodeInfoMainExecutable as String] as? URL,
              signedExecutable.resolvingSymlinksInPath().path == before.0 else { throw Failure.signature }
        let anchor = SecRequirementCreateWithString("anchor apple" as CFString, [], &apple) == errSecSuccess
            && apple != nil && SecCodeCheckValidity(dynamic, [], apple!) == errSecSuccess
        let sha = SHA256.hash(data: try Data(contentsOf: signedExecutable)).map { String(format: "%02x", $0) }.joined()
        let after = try process()
        guard before.0 == after.0, before.1 == after.1 else { throw Failure.changed }
        return .init(pid: pid, launch: before.1, executable: before.0, identifier: identifier,
                     team: info[kSecCodeInfoTeamIdentifier as String] as? String, sha256: sha, appleAnchor: anchor)
    }
}
