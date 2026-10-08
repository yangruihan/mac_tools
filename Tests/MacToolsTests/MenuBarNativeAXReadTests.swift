import AppKit
import ApplicationServices
import XCTest
@testable import MacTools

/// Only opaque AX handles and injected public API responses. No AX server,
/// application registration, windows, status items, permission or real IPC.
final class MenuBarNativeAXReadTests: XCTestCase {
    private let application = MenuBarApplicationIdentity(bundleID: "fixture.ax", bundlePath: "/FixtureAX.app", launch: 1)
    private func client(_ overrides: [String: (AXError, CFTypeRef?)] = [:]) -> MenuBarNativeAXGeometry.Client {
        let element = AXUIElementCreateApplication(20)
        var point = CGPoint(x: 10, y: 0), size = CGSize(width: 120, height: 37)
        let values: [String: CFTypeRef] = [kAXMenuBarAttribute: element, kAXExtrasMenuBarAttribute: element,
            kAXChildrenAttribute: [element] as CFArray, kAXRoleAttribute: kAXMenuBarItemRole as CFString,
            kAXPositionAttribute: AXValueCreate(.cgPoint, &point)!, kAXSizeAttribute: AXValueCreate(.cgSize, &size)!]
        return .init(owner: { _ in (.success, 20) }, timeout: { _, value in
            XCTAssertGreaterThan(value, 0); XCTAssertLessThanOrEqual(value, 0.25); return .success
        }, copy: { _, key in overrides[key] ?? (.success, values[key]) }, application: { _ in self.application })
    }
    private func failure(_ client: MenuBarNativeAXGeometry.Client, extras: Bool = false,
                         scope: String = "frontMenu") throws -> MenuBarNativeAXReadFailure {
        do {
            _ = try MenuBarNativeAXGeometry.frames(pid: 20, extras: extras, deadline: ContinuousClock.now.advanced(by: .seconds(2)),
                scope: scope, expectedApplication: application, client: client)
            XCTFail("Unverified AX results cannot produce geometry")
        } catch let error as MenuBarNativeAXReadFailure { return error }
        throw MenuBarNativeObservationFailure.target
    }
    func testTargetPositionMessagingFailureIdentifiesExactCallAndIdentity() throws {
        let error = try failure(client([kAXPositionAttribute: (.cannotComplete, nil)]), extras: true, scope: "targetExtras")
        XCTAssertEqual(error.diagnosticCode, "ax.targetExtras.AXPosition.apiError")
        XCTAssertEqual(error.detail.operation, "AXUIElementCopyAttributeValue")
        XCTAssertEqual(error.detail.elementPath, "bar.children[0]")
        XCTAssertEqual(error.detail.axError, AXError.cannotComplete.rawValue)
        XCTAssertEqual(error.detail.elementPID, 20); XCTAssertEqual(error.detail.pid, 20)
        XCTAssertEqual(error.detail.application, application); XCTAssertEqual(error.detail.expectedApplication, application)
        XCTAssertEqual(error.detail.callerPID, ProcessInfo.processInfo.processIdentifier)
    }
    func testUnreadableMenuEmptyMenuAndSuccessWithNilAreDifferentRefusals() throws {
        let unavailable = try failure(client([kAXMenuBarAttribute: (.noValue, nil)]))
        let empty = try failure(client([kAXChildrenAttribute: (.success, [] as CFArray)]))
        let nilValue = try failure(client([kAXMenuBarAttribute: (.success, nil)]))
        XCTAssertEqual(unavailable.detail.attribute, "AXMenuBar"); XCTAssertEqual(unavailable.detail.axError, AXError.noValue.rawValue)
        XCTAssertEqual(unavailable.detail.outcome, "apiError")
        XCTAssertEqual(empty.detail.attribute, "AXChildren"); XCTAssertEqual(empty.detail.axError, 0)
        XCTAssertEqual(empty.detail.outcome, "emptyChildren"); XCTAssertEqual(empty.detail.childrenCount, 0)
        XCTAssertEqual(nilValue.detail.outcome, "nilValue"); XCTAssertEqual(nilValue.detail.axError, 0)
        XCTAssertNotEqual(unavailable.diagnosticCode, empty.diagnosticCode)
        XCTAssertNotEqual(unavailable.diagnosticCode, nilValue.diagnosticCode)
    }
    func testRecoveryMissingExtrasIsNotReportedAsFrontMenuFailure() throws {
        let error = try failure(client([kAXExtrasMenuBarAttribute: (.attributeUnsupported, nil)]), extras: true, scope: "recoveryExtras")
        XCTAssertEqual(error.detail.scope, "recoveryExtras"); XCTAssertEqual(error.detail.attribute, "AXExtrasMenuBar")
        XCTAssertEqual(error.detail.axError, AXError.attributeUnsupported.rawValue)
    }
    func testWrongOwnerAndTimeoutSetterFailureCannotProceedToCopy() throws {
        for wrongOwner in [true, false] {
            var calls = 0; var transport = client()
            transport.owner = { _ in (.success, wrongOwner ? 21 : 20) }
            transport.timeout = { _, _ in .cannotComplete }
            transport.copy = { _, _ in calls += 1; return (.success, nil) }
            let error = try failure(transport)
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(error.detail.operation, wrongOwner ? "AXUIElementGetPid" : "AXUIElementSetMessagingTimeout")
            XCTAssertEqual(error.detail.outcome, wrongOwner ? "wrongOwner" : "apiError")
            XCTAssertEqual(error.detail.axError, wrongOwner ? 0 : AXError.cannotComplete.rawValue)
        }
    }
    func testWrongValueShapeAndDisallowedMenuRoleStayRefused() throws {
        let type = try failure(client([kAXSizeAttribute: (.success, "invalid" as CFString)]))
        XCTAssertEqual(type.detail.attribute, "AXSize"); XCTAssertEqual(type.detail.outcome, "unexpectedType")
        XCTAssertEqual(type.detail.actualType, "string")
        let button = client([kAXRoleAttribute: (.success, kAXButtonRole as CFString)])
        XCTAssertEqual(try failure(button).detail.outcome, "unexpectedRole")
        let frames = try MenuBarNativeAXGeometry.frames(pid: 20, extras: true, deadline: ContinuousClock.now.advanced(by: .seconds(2)), client: button)
        XCTAssertEqual(frames, [CGRect(x: 10, y: 0, width: 120, height: 37)])
    }
    func testHistoricalGenericFailureDoesNotInventAXDetailsAndNewDetailRoundTrips() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(MenuBarNativeRevealDiagnostic.self, from: Data(contentsOf: root.appendingPathComponent("docs/evidence/menu-bar-native-user-click-2026-10-03/internal-diagnostic.json")))
        XCTAssertEqual(old.firstFailure?.errorCode, "observation.menu"); XCTAssertNil(old.firstFailure?.axRead)
        let error = try failure(client([kAXMenuBarAttribute: (.noValue, nil)]))
        var trace = MenuBarNativeRevealDiagnostic(transaction: UUID())
        trace.append(stage: "before.first.observe", event: "failure", state: "preparing", elapsed: 66, error: error)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let saved = try decoder.decode(MenuBarNativeRevealDiagnostic.self, from: encoder.encode(trace))
        XCTAssertEqual(saved.firstFailure?.axRead, error.detail)
        XCTAssertNotEqual(saved.firstFailure?.errorCode, old.firstFailure?.errorCode)
    }
}

@MainActor
private final class AXFailureAfterEffectDriver: MenuBarNativeRevealWidthDriver {
    let base = MenuBarNativeRevealFixtureDriver()
    let failure: MenuBarNativeAXReadFailure
    private var reads = 0
    init(_ failure: MenuBarNativeAXReadFailure) { self.failure = failure }
    func widthState() throws -> MenuBarOwnedWidthState { try base.widthState() }
    func setLength(_ length: CGFloat, matching binding: MenuBarOwnedWidthBinding) throws { try base.setLength(length, matching: binding) }
    func verifyRestorationSafety() async throws { try await base.verifyRestorationSafety() }
    func observe(_ identity: MenuBarIconIdentity) async throws -> MenuBarNativeRevealPlan.Observation {
        reads += 1
        if reads == 3 { throw failure }
        return try await base.observe(identity)
    }
}

@MainActor
final class MenuBarNativeAXFailureRestoreTests: XCTestCase {
    func testTypedAXCallFailureSurvivesAcknowledgedPhysicalRestoration() async throws {
        var detail = MenuBarNativeRevealDiagnostic.AXReadDetail(scope: "frontMenu", pid: 30, callerPID: 10,
            application: nil, expectedApplication: nil, operation: "AXUIElementCopyAttributeValue", attribute: "AXMenuBar",
            elementPath: "application", outcome: "apiError", axError: AXError.noValue.rawValue)
        detail.completedGroups = [.init(scope: "targetExtras", pid: 20, application: nil, frames: [CGRect(x: 880, y: 10, width: 26, height: 22)])]
        let driver = AXFailureAfterEffectDriver(.init(detail: detail)), journal = MenuBarMemoryOwnedWidthJournal()
        let flow = MenuBarNativeRevealController(driver: driver, journal: journal, sampleDelay: .zero)
        let entered = await flow.begin(driver.base.identity)
        XCTAssertFalse(entered); XCTAssertEqual(flow.state, .idle); XCTAssertEqual(driver.base.writes, [105, -1])
        XCTAssertEqual(driver.base.spacer.frame.width, 38); XCTAssertNil(journal.record)
        XCTAssertEqual(flow.diagnostic.firstFailure?.stage, "after.first.observe")
        XCTAssertEqual(flow.diagnostic.firstFailure?.axRead, detail)
        XCTAssertEqual(flow.diagnostic.entries.last?.event, "restored")
    }
}
