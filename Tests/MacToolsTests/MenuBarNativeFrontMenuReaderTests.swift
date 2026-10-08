import AppKit
import ApplicationServices
import XCTest
@testable import MacTools

@MainActor
final class MenuBarNativeFrontMenuReaderTests: XCTestCase {
    private let application = MenuBarApplicationIdentity(bundleID: "fixture.menu", bundlePath: "/FixtureMenu.app", launch: 1)
    private func client(pid: Int32, expectMain: Bool, childError: AXError = .success,
                        size: CGSize = CGSize(width: 100, height: 37)) -> MenuBarNativeAXGeometry.Client {
        let element = AXUIElementCreateApplication(pid)
        var point = CGPoint(x: 10, y: 0), size = size
        let values: [String: CFTypeRef] = [kAXMenuBarAttribute: element,
            kAXChildrenAttribute: [element] as CFArray, kAXRoleAttribute: kAXMenuBarItemRole as CFString,
            kAXPositionAttribute: AXValueCreate(.cgPoint, &point)!, kAXSizeAttribute: AXValueCreate(.cgSize, &size)!]
        let expectedApplication = application
        return .init(owner: { _ in (.success, pid) }, timeout: { _, timeout in
            XCTAssertGreaterThan(timeout, 0); XCTAssertLessThanOrEqual(timeout, 0.25); return .success
        }, copy: { _, key in
            XCTAssertEqual(Thread.isMainThread, expectMain)
            if key == kAXChildrenAttribute, childError != .success { return (childError, nil) }
            return (.success, values[key])
        }, application: { _ in expectedApplication })
    }
    func testSelfMenuReadsEveryAXAttributeOnMainThread() async throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let frames = try await MenuBarNativeFrontMenuReader.frames(pid: pid,
            deadline: ContinuousClock.now.advanced(by: .seconds(2)), expectedApplication: application,
            client: client(pid: pid, expectMain: true))
        XCTAssertEqual(frames, [CGRect(x: 10, y: 0, width: 100, height: 37)])
    }
    func testExternalMenuKeepsBoundedBackgroundAXRead() async throws {
        let frames = try await MenuBarNativeFrontMenuReader.frames(pid: 20,
            deadline: ContinuousClock.now.advanced(by: .seconds(2)), expectedApplication: application,
            client: client(pid: 20, expectMain: false))
        XCTAssertEqual(frames, [CGRect(x: 10, y: 0, width: 100, height: 37)])
    }
    func testSelfAndExternalReadFailuresRemainTypedRefusalsWithoutFallback() async throws {
        for pid in [ProcessInfo.processInfo.processIdentifier, 20] {
            do {
                _ = try await MenuBarNativeFrontMenuReader.frames(pid: pid,
                    deadline: ContinuousClock.now.advanced(by: .seconds(2)), expectedApplication: application,
                    client: client(pid: pid, expectMain: pid != 20, childError: .failure))
                XCTFail("Failed children must not become an empty or fabricated menu")
            } catch let error as MenuBarNativeAXReadFailure {
                XCTAssertEqual(error.detail.pid, pid); XCTAssertEqual(error.detail.axError, -25200)
                XCTAssertEqual(error.detail.attribute, kAXChildrenAttribute)
                XCTAssertEqual(error.detail.expectedApplication, application)
            }
        }
    }
    func testSharedExpiredBudgetDoesNotReadOrResetDeadline() async throws {
        for pid in [ProcessInfo.processInfo.processIdentifier, 20] {
            var transport = client(pid: pid, expectMain: pid != 20)
            transport.copy = { _, _ in XCTFail("Expired shared budget must not read"); return (.success, nil) }
            do {
                _ = try await MenuBarNativeFrontMenuReader.frames(pid: pid,
                    deadline: ContinuousClock.now.advanced(by: .seconds(-1)), expectedApplication: application, client: transport)
                XCTFail("Expired budget must refuse")
            } catch let error as MenuBarNativeAXReadFailure { XCTAssertEqual(error.detail.outcome, "deadline") }
        }
    }
    func testPrecancelledMenuReadNeverQueriesEitherProcess() async throws {
        for pid in [ProcessInfo.processInfo.processIdentifier, 20] {
            var transport = client(pid: pid, expectMain: pid != 20)
            transport.copy = { _, _ in XCTFail("Cancelled request must not read"); return (.success, nil) }
            let readClient = transport
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await MenuBarNativeFrontMenuReader.frames(pid: pid,
                    deadline: ContinuousClock.now.advanced(by: .seconds(2)), expectedApplication: application, client: readClient)
            }
            do { _ = try await task.value; XCTFail("Cancelled request must refuse") }
            catch is CancellationError { /* Refused before a detached worker can start. */ }
        }
    }
    func testFinalSuccessfulAXSizeAfterSharedDeadlineCannotReturnGeometry() async throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let start = ContinuousClock.now, deadline = start.advanced(by: .seconds(2))
        var now = start
        var transport = client(pid: pid, expectMain: true)
        let copy = transport.copy
        transport.now = { now }
        transport.copy = { element, key in
            let value = copy(element, key)
            if key == kAXSizeAttribute { now = deadline.advanced(by: .milliseconds(1)) }
            return value
        }
        do {
            _ = try await MenuBarNativeFrontMenuReader.frames(pid: pid, deadline: deadline,
                expectedApplication: application, client: transport)
            XCTFail("A successful final call cannot accept geometry after the shared deadline")
        } catch let error as MenuBarNativeAXReadFailure {
            XCTAssertEqual(error.detail.outcome, "deadline")
            XCTAssertEqual(error.detail.attribute, kAXSizeAttribute)
        }
    }
    func testCancelledDuringFinalSuccessfulAXSizeCannotReturnGeometry() async throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        var transport = client(pid: pid, expectMain: true)
        let copy = transport.copy
        transport.copy = { element, key in
            let value = copy(element, key)
            if key == kAXSizeAttribute { withUnsafeCurrentTask { $0?.cancel() } }
            return value
        }
        let readClient = transport, expectedApplication = application
        let task = Task { @MainActor in
            try await MenuBarNativeFrontMenuReader.frames(pid: pid,
                deadline: ContinuousClock.now.advanced(by: .seconds(2)),
                expectedApplication: expectedApplication, client: readClient)
        }
        do { _ = try await task.value; XCTFail("Cancellation during final call cannot accept geometry") }
        catch let error as MenuBarNativeAXReadFailure {
            XCTAssertEqual(error.detail.outcome, "cancelled")
            XCTAssertEqual(error.detail.attribute, kAXSizeAttribute)
        }
    }
}
