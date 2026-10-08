// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
// Original MacTools observation/recovery contract. No events or runtime wiring.
import Foundation
import CoreGraphics

enum MenuBarHiddenMoveModel {
    static let backendEnabled = false
    static let schemaVersion = 2

    struct Profile: Codable, Equatable {
        let version: String
        let build: String
        let architecture: String
        // One independent Ice trial, not validation of our private ABI adapter.
        static let trial = Profile(version: "15.7.4", build: "24G517", architecture: "arm64")
    }
    struct Scope: Codable, Equatable {
        let profile: Profile
        let continuity: UUID
        let displayUUID: String
        let displayID: UInt32
        let displayFrame: CGRect
        let scale: Double
        let rotation: Double
        let activeSpace: UInt64 // Runtime only; never a durable identity.
        let rightSafe: CGRect
    }
    struct Owner: Codable, Equatable {
        let target: MenuBarRecordedTarget
        let signedIdentifier: String
        let team: String
        let codeHash: String
        let itemKey: String
        let nonce: UUID
        let itemInstance: UUID
    }
    enum OnScreen: String, Codable { case ordered, missing, falseValue, malformed }
    struct Item: Codable, Equatable {
        let identity: MenuBarRecordedTarget
        let frame: CGRect
        let listedOnScreen: Bool
        let onScreen: OnScreen
        let alpha: Double
        let spaces: [UInt64]
        let ownerOcclusionVisible: Bool?
    }
    enum OrderEvidence: String, Codable {
        case observedCoordinates // Not a WindowServer persistent ordering service.
        case unknown
    }
    struct Carrier: Codable, Equatable {
        let windowID: UInt32
        let signature: MenuBarProcessSignature.Proof
        let frame: CGRect
        let layer: Int
        let spaces: [UInt64]
    }
    struct Snapshot: Codable, Equatable {
        let sequence: UInt64
        let uptimeMilliseconds: UInt64
        let scope: Scope
        let owner: Owner
        let items: [Item] // All status members, including hidden/unknown peers and controls.
        let membershipIDs: [UInt32]
        let orderEvidence: OrderEvidence
        let carriers: [Carrier]? // Raw non-item members remain accounted for.
        init(sequence: UInt64, uptimeMilliseconds: UInt64, scope: Scope, owner: Owner,
             items: [Item], membershipIDs: [UInt32], orderEvidence: OrderEvidence, carriers: [Carrier]? = nil) {
            self.sequence = sequence; self.uptimeMilliseconds = uptimeMilliseconds; self.scope = scope
            self.owner = owner; self.items = items; self.membershipIDs = membershipIDs
            self.orderEvidence = orderEvidence; self.carriers = carriers
        }
        var completeLogicalOrderProven: Bool { false }
        func sameFacts(as other: Snapshot) -> Bool {
            scope == other.scope && owner == other.owner && items == other.items
                && membershipIDs == other.membershipIDs && orderEvidence == other.orderEvidence && carriers == other.carriers
        }
    }
    struct Anchor: Codable, Equatable {
        enum Boundary: String, Codable { case interior, leading, trailing }
        let left: MenuBarRecordedTarget?
        let right: MenuBarRecordedTarget?
        let boundary: Boundary
        let capturedOrder: [MenuBarRecordedTarget]
        let evidence: OrderEvidence
    }
    struct Plan: Codable, Equatable {
        let first: Snapshot
        let original: Snapshot
        let anchor: Anchor
        var firstSequence: UInt64 { first.sequence }
        var firstUptimeMilliseconds: UInt64 { first.uptimeMilliseconds }

        // Captures an OBSERVED return anchor. It does not authorize a move.
        static func capture(_ first: Snapshot, _ second: Snapshot, now: UInt64) throws -> Plan {
            try stable(first, second)
            guard now >= second.uptimeMilliseconds, now - second.uptimeMilliseconds <= 250 else { throw Failure.stale }
            try validate(second)
            let order = second.items.map(\.identity)
            guard let index = order.firstIndex(of: second.owner.target) else { throw Failure.identity }
            let anchor = Anchor(left: index > 0 ? order[index - 1] : nil,
                right: index + 1 < order.count ? order[index + 1] : nil,
                boundary: index == 0 ? .leading : (index == order.count - 1 ? .trailing : .interior),
                capturedOrder: order, evidence: second.orderEvidence)
            let plan = Plan(first: first, original: second, anchor: anchor)
            try plan.validateStructure()
            return plan
        }
        func validateStructure() throws {
            try Self.stable(first, original)
            try Self.validate(original)
            guard firstSequence < original.sequence, original.uptimeMilliseconds >= firstUptimeMilliseconds,
                  (100...500).contains(original.uptimeMilliseconds - firstUptimeMilliseconds),
                  anchor.capturedOrder == original.items.map(\.identity), anchor.evidence == original.orderEvidence,
                  let index = anchor.capturedOrder.firstIndex(of: original.owner.target) else { throw Failure.anchor }
            let order = anchor.capturedOrder
            guard anchor.left == (index > 0 ? order[index - 1] : nil),
                  anchor.right == (index + 1 < order.count ? order[index + 1] : nil),
                  anchor.boundary == (index == 0 ? .leading : (index == order.count - 1 ? .trailing : .interior)),
                  anchor.left != nil || anchor.right != nil else { throw Failure.anchor }
        }
        func verifyReturned(_ first: Snapshot, _ second: Snapshot, now: UInt64) throws {
            try validateStructure()
            try Self.stable(first, second)
            try Self.validate(second)
            guard now >= second.uptimeMilliseconds, now - second.uptimeMilliseconds <= 250 else { throw Failure.stale }
            guard first.sequence > original.sequence, first.uptimeMilliseconds > original.uptimeMilliseconds,
                  second.sameFacts(as: original) else { throw Failure.returnChanged }
        }
        private static func stable(_ a: Snapshot, _ b: Snapshot) throws {
            guard b.sequence > a.sequence, b.uptimeMilliseconds >= a.uptimeMilliseconds,
                  (100...500).contains(b.uptimeMilliseconds - a.uptimeMilliseconds), a.sameFacts(as: b) else {
                throw Failure.unstable
            }
        }
        private static func validate(_ sample: Snapshot) throws {
            let scope = sample.scope
            guard scope.profile == .trial, !scope.displayUUID.isEmpty, scope.displayID > 0,
                  scope.activeSpace > 0, scope.scale.isFinite, scope.scale > 0, scope.rotation.isFinite,
                  valid(scope.displayFrame), valid(scope.rightSafe), scope.displayFrame.contains(scope.rightSafe) else { throw Failure.environment }
            let owner = sample.owner
            guard identity(owner.target), owner.signedIdentifier == "com.ryanai.mactools.nativetargets",
                  owner.target.application?.bundleID == owner.signedIdentifier, !owner.team.isEmpty,
                  owner.codeHash.count == 64, owner.codeHash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  ["mactools_native_acceptance_T", "mactools_native_acceptance_N"].contains(owner.itemKey) else { throw Failure.identity }
            guard (2...512).contains(sample.items.count), sample.orderEvidence == .observedCoordinates,
                  Set(sample.membershipIDs).count == sample.membershipIDs.count,
                  Set(sample.items.map { $0.identity.windowID } + (sample.carriers ?? []).map(\.windowID)) == Set(sample.membershipIDs),
                  Set(sample.items.map { $0.identity.windowID }).count == sample.items.count,
                  sample.items.allSatisfy({ item in
                      identity(item.identity) && valid(item.frame) && item.frame.height < 64
                          && abs(item.frame.minY - scope.displayFrame.minY) < 1
                          && item.alpha.isFinite && item.alpha > 0 && item.alpha <= 1
                          && !item.spaces.isEmpty && Set(item.spaces).count == item.spaces.count
                          && item.spaces.contains(scope.activeSpace) && !item.spaces.contains(0)
                          && item.onScreen != .malformed
                          && (item.listedOnScreen ? item.onScreen == .ordered : item.onScreen != .ordered)
                  }) else { throw Failure.inventory }
            let carriers = sample.carriers ?? []
            guard carriers.count <= 1, Set(carriers.map(\.windowID)).count == carriers.count,
                  carriers.allSatisfy({ c in
                      let p = c.signature
                      return c.windowID > 0 && !sample.items.contains { $0.identity.windowID == c.windowID }
                          && p.pid > 0 && (p.launch.map { $0.isFinite && $0 > 0 } ?? true) && p.appleAnchor
                          && p.identifier == "com.apple.WindowServer"
                          && p.executable == "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer"
                          && p.sha256.count == 64 && p.sha256.allSatisfy { "0123456789abcdef".contains($0) }
                          && c.layer == Int(CGWindowLevelForKey(.mainMenuWindow)) && valid(c.frame)
                          && c.frame.minX == scope.displayFrame.minX && c.frame.minY == scope.displayFrame.minY
                          && c.frame.width == scope.displayFrame.width && c.frame.height < 64
                          && !c.spaces.isEmpty && Set(c.spaces).count == c.spaces.count
                          && c.spaces.contains(scope.activeSpace) && !c.spaces.contains(0)
                  }) else { throw Failure.inventory }
            // Record unknown visibility explicitly; never filter it away.
            guard let target = sample.items.first(where: { $0.identity == owner.target }),
                  !target.listedOnScreen, [.missing, .falseValue].contains(target.onScreen),
                  target.ownerOcclusionVisible == false else { throw Failure.targetNotHidden }
            for (left, right) in zip(sample.items, sample.items.dropFirst()) {
                guard left.frame.maxX <= right.frame.minX else { throw Failure.orderUnknown }
            }
        }
        private static func identity(_ value: MenuBarRecordedTarget) -> Bool {
            guard let app = value.application else { return false }
            return value.pid > 0 && value.windowID > 0 && !app.bundleID.isEmpty && !app.bundlePath.isEmpty
                && app.bundlePath.hasPrefix("/") && app.launch.isFinite && app.launch > 0
        }
        private static func valid(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite
                && frame.maxX.isFinite && frame.maxY.isFinite
                && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
        }
    }
    struct Record: Codable, Equatable {
        enum Phase: String, Codable { case prepared, moved, restorePrepared, restored }
        let schemaVersion: Int
        let transaction: UUID
        let plan: Plan
        var phase: Phase
        var returnEvidence: [Snapshot]?

        static func prepared(plan: Plan) throws -> Record {
            try plan.validateStructure()
            return Record(schemaVersion: MenuBarHiddenMoveModel.schemaVersion, transaction: UUID(),
                          plan: plan, phase: .prepared, returnEvidence: nil)
        }
        func confirmedReturned(_ first: Snapshot, _ second: Snapshot, now: UInt64) throws -> Record {
            try plan.verifyReturned(first, second, now: now)
            var copy = self; copy.phase = .restored; copy.returnEvidence = [first, second]
            return copy
        }
        func validateStructure() throws {
            guard schemaVersion == MenuBarHiddenMoveModel.schemaVersion else { throw Failure.schema }
            try plan.validateStructure()
            if phase == .restored {
                guard let proof = returnEvidence, proof.count == 2 else { throw Failure.returnChanged }
                // Structural proof only. A live acknowledgement must supply a
                // current monotonic clock, not reuse this stored timestamp.
                try plan.verifyReturned(proof[0], proof[1], now: proof[1].uptimeMilliseconds)
            } else if returnEvidence != nil { throw Failure.returnChanged }
        }
    }
    enum RecoveryDisposition: Equatable {
        case retained // First batch has no move dispatcher, even for a valid record.
        case identityChanged, environmentChanged, originalStateObserved
    }
    static func inspectRecovery(_ record: Record, first: Snapshot, second: Snapshot, now: UInt64) throws -> RecoveryDisposition {
        try record.validateStructure()
        let old = record.plan.original
        guard [first, second].allSatisfy({ sample in
            sample.owner == old.owner && sample.items.count == old.items.count
                && sample.items.allSatisfy({ item in old.items.contains { $0.identity == item.identity } })
        }) else { return .identityChanged }
        guard first.scope == old.scope, second.scope == old.scope else { return .environmentChanged }
        do { try record.plan.verifyReturned(first, second, now: now); return .originalStateObserved }
        catch { return .retained }
    }
    enum Failure: Error, Equatable {
        case identity, environment, inventory, targetNotHidden, orderUnknown, unstable, stale, anchor, schema, returnChanged
    }
}
