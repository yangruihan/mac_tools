import Foundation
import CoreGraphics

protocol MenuBarNativeDiagnosticError: Error { var diagnosticCode: String { get } }

/// Preview-only bounded metadata. No titles, pixels, AX actions or preferences.
struct MenuBarNativeRevealDiagnostic: Codable {
    /// API metadata only. A zero AX code with emptyChildren is distinct from
    /// noValue/attributeUnsupported/cannotComplete; none can authorize effects.
    struct AXReadDetail: Codable, Equatable {
        struct CompletedGroup: Codable, Equatable {
            let scope: String
            let pid: Int32
            let application: MenuBarApplicationIdentity?
            let frames: [CGRect]
        }
        let scope: String
        let pid: Int32
        let callerPID: Int32
        let application: MenuBarApplicationIdentity?
        let expectedApplication: MenuBarApplicationIdentity?
        let operation: String
        let attribute: String
        let elementPath: String
        let outcome: String
        let axError: Int32?
        var elementPID: Int32? = nil
        var expectedType: String? = nil
        var actualType: String? = nil
        var childrenCount: Int? = nil
        var completedGroups: [CompletedGroup] = []
    }
    struct Window: Codable {
        let id: UInt32
        let pid: Int32
        let frame: CGRect
        let onScreen: Bool
        let application: MenuBarApplicationIdentity?
        init(_ target: MenuBarStatusTarget) {
            id = target.id; pid = target.pid; frame = target.frame
            onScreen = target.onScreen; application = target.application
        }
    }
    /// Evidence only: a mixed visible/hidden CG coordinate rank change is not
    /// proof of a persistent logical reorder. Never used to authorize effects.
    struct PostcheckDetail: Codable {
        struct Peer: Codable {
            let id: UInt32
            let before: Window?
            let after: Window?
            let beforeRank: Int?
            let afterRank: Int?
        }
        let beforeOrder: [UInt32]
        let afterOrder: [UInt32]
        let peerIdentitySetStable: Bool?
        let peers: [Peer]
        let measuredSpacerGrowth: Double?
        let targetShiftMatchesMeasuredGrowth: Bool
        let targetOnScreen: Bool
        let targetButtonInsideSafeArea: Bool
        let targetButtonClearOfApplicationMenu: Bool
        init(before: MenuBarNativeRevealPlan.Observation, after: MenuBarNativeRevealPlan.Observation) {
            let oldOrder = before.orderedWindowIDs, newOrder = after.orderedWindowIDs
            beforeOrder = oldOrder; afterOrder = newOrder
            let ids = Set(before.peers.map(\.id)).union(after.peers.map(\.id)).sorted()
            let capturedPeers: [Peer] = ids.map { id in
                .init(id: id, before: before.peers.first { $0.id == id }.map(Window.init),
                    after: after.peers.first { $0.id == id }.map(Window.init),
                    beforeRank: oldOrder.firstIndex(of: id), afterRank: newOrder.firstIndex(of: id))
            }
            peers = capturedPeers
            if before.peers.isEmpty || after.peers.isEmpty { peerIdentitySetStable = nil }
            else {
                peerIdentitySetStable = ids.count == before.peers.count && ids.count == after.peers.count && capturedPeers.allSatisfy {
                    guard let old = $0.before, let new = $0.after, old.application != nil else { return false }
                    return old.pid == new.pid && old.application == new.application
                }
            }
            let measured = after.ownedSpacer.width - before.ownedSpacer.width
            measuredSpacerGrowth = measured.isFinite ? Double(measured) : nil
            let expected = before.targetButton.offsetBy(dx: -measured, dy: 0)
            targetShiftMatchesMeasuredGrowth = measured.isFinite && measured > 0
                && zip([expected.minX, expected.minY, expected.width, expected.height],
                       [after.targetButton.minX, after.targetButton.minY, after.targetButton.width, after.targetButton.height])
                    .allSatisfy { abs($0 - $1) <= 1 }
            targetOnScreen = after.target.onScreen
            targetButtonInsideSafeArea = after.safeAreas.contains { $0.contains(after.targetButton) }
            targetButtonClearOfApplicationMenu = !after.applicationMenu.intersects(after.targetButton)
        }
    }
    struct Sample: Codable {
        let generation: UUID
        let frontPID: Int32?
        let frontApplication: MenuBarApplicationIdentity?
        let safeAreas: [CGRect]
        let windows: [Window]
        let orderedWindowIDs: [UInt32]
        let target: Window?
        let targetButton: CGRect?
        let ownedSpacer: CGRect?
        let recoveryButton: CGRect?
        let applicationMenu: CGRect?
        let overlays: [CGRect]
        let unprovenPixelWindowIDs: [UInt32]
        let targetAX: [CGRect]
        let recoveryAX: [CGRect]
        let menuAX: [CGRect]
        init(_ observation: MenuBarNativeRevealPlan.Observation) {
            generation = observation.generation; frontPID = observation.frontPID
            frontApplication = observation.frontApplication; safeAreas = observation.safeAreas
            windows = observation.peers.map(Window.init); orderedWindowIDs = observation.orderedWindowIDs
            target = Window(observation.target); targetButton = observation.targetButton
            ownedSpacer = observation.ownedSpacer; recoveryButton = observation.recoveryButton
            applicationMenu = observation.applicationMenu
            overlays = []; unprovenPixelWindowIDs = []; targetAX = []; recoveryAX = []; menuAX = []
        }
        init(generation: UUID, frontPID: Int32, frontApplication: MenuBarApplicationIdentity,
             safeAreas: [CGRect], windows: [MenuBarStatusTarget], overlays: [CGRect],
             unprovenPixelWindowIDs: [UInt32], targetAX: [CGRect] = [],
             recoveryAX: [CGRect] = [], menuAX: [CGRect] = []) {
            self.generation = generation; self.frontPID = frontPID; self.frontApplication = frontApplication
            self.safeAreas = safeAreas; self.windows = windows.map(Window.init)
            self.overlays = overlays; self.unprovenPixelWindowIDs = unprovenPixelWindowIDs
            self.targetAX = targetAX; self.recoveryAX = recoveryAX; self.menuAX = menuAX
            orderedWindowIDs = []; target = nil; targetButton = nil; ownedSpacer = nil
            recoveryButton = nil; applicationMenu = nil
        }
    }
    struct Entry: Codable {
        let sequence: Int
        let elapsedMilliseconds: Double
        let at: Date
        let stage: String
        let event: String
        let state: String
        let errorCode: String?
        let axRead: AXReadDetail?
        let postcheck: PostcheckDetail?
        let sample: Sample?
        let length: Double?
        let backingFrame: CGRect?
    }
    private(set) var schemaVersion = 1
    let transaction: UUID
    var targetWindowID: UInt32? = nil
    var targetPID: Int32? = nil
    private(set) var entries: [Entry] = []
    private(set) var firstFailure: Entry?
    private(set) var droppedEntries = 0
    mutating func append(stage: String, event: String, state: String, elapsed: Double,
                         error: Error? = nil, sample: Sample? = nil, width: MenuBarOwnedWidthState? = nil,
                         postcheck: PostcheckDetail? = nil) {
        let entry = Entry(sequence: entries.count + droppedEntries + 1,
            elapsedMilliseconds: elapsed, at: Date(), stage: stage, event: event, state: state,
            errorCode: error.map(Self.code), axRead: (error as? MenuBarNativeAXReadFailure)?.detail,
            postcheck: postcheck, sample: sample,
            length: width.map { Double($0.length) }, backingFrame: width?.backingFrame)
        if error != nil && firstFailure == nil { firstFailure = entry }
        // Keep preflight evidence and the latest recovery events after a long session.
        if entries.count == 128 { entries.remove(at: 32); droppedEntries += 1 }
        entries.append(entry)
    }
    static func code(_ error: Error) -> String {
        if let typed = error as? MenuBarNativeDiagnosticError { return typed.diagnosticCode }
        if error is CancellationError { return "task.cancelled" }
        let other = error as NSError
        return "other.\(other.domain).\(other.code)"
    }
}

struct MenuBarNativeAXReadFailure: LocalizedError, MenuBarNativeDiagnosticError {
    var detail: MenuBarNativeRevealDiagnostic.AXReadDetail
    var diagnosticCode: String { "ax.\(detail.scope).\(detail.attribute).\(detail.outcome)" }
    var errorDescription: String? {
        let code = detail.axError.map { "，AXError \($0)" } ?? ""
        return "AX几何核实失败：\(detail.scope) / \(detail.attribute) / \(detail.outcome)\(code)。露出验证停止。"
    }
}
