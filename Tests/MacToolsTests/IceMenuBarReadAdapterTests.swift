// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import XCTest
import CoreGraphics
@testable import MacTools

final class IceMenuBarReadAdapterTests: XCTestCase {
    private typealias A = IceMenuBarReadAdapter
    private final class Source: IceMenuBarWindowSource {
        var profile: MenuBarHiddenMoveModel.Profile = .trial
        var reads = 0
        var result: A.Directory
        var error: Error?
        init(_ result: A.Directory) { self.result = result }
        func read() throws -> A.Directory {
            reads += 1
            if let error { throw error }
            return result
        }
    }
    private func directory(ids: [UInt32] = [1, 2], members: [A.Member]? = nil,
                           before: UInt64 = 7, after: UInt64 = 7, complete: Bool = true) -> A.Directory {
        .init(memberIDs: ids, members: members ?? [
            .init(windowID: 1, frame: CGRect(x: -4341, y: 0, width: 29, height: 37), spaces: [7]),
            .init(windowID: 2, frame: CGRect(x: 1500, y: 0, width: 30, height: 37), spaces: [8])
        ], spaceBefore: before, spaceAfter: after, enumerationComplete: complete)
    }
    func testDefaultAndInjectedDisabledPolicyNeverReadPrivateSource() {
        XCTAssertThrowsError(try A().read()) { XCTAssertEqual($0 as? A.Failure, .disabled) }
        let source = Source(directory())
        XCTAssertThrowsError(try A(policy: .disabled, source: source).read())
        XCTAssertEqual(source.reads, 0)
    }
    func testUnsupportedProfileStopsBeforeReadingDirectory() {
        let source = Source(directory())
        source.profile = .init(version: "future", build: "unknown", architecture: "arm64")
        XCTAssertThrowsError(try A(policy: .isolatedReadOnly, source: source).read()) {
            XCTAssertEqual($0 as? A.Failure, .unsupportedProfile)
        }
        XCTAssertEqual(source.reads, 0)
    }
    func testHiddenAndOffSpaceMembersRemainWithoutClaimingLogicalOrder() throws {
        let source = Source(directory()), adapter = A(policy: .isolatedReadOnly, source: source)
        let value = try adapter.read()
        XCTAssertEqual(value, source.result); XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(value.members[0].frame.minX, -4341)
        XCTAssertEqual(value.members[1].spaces, [8]); XCTAssertFalse(value.logicalOrderProven)
    }
    func testTruncationSpaceChangeMissingDuplicateAndZeroMembersFailClosed() {
        let valid = directory()
        let values = [directory(complete: false), directory(after: 8), directory(before: 0, after: 0),
            directory(ids: [1]), directory(ids: [1, 1, 2]), directory(ids: [0, 1, 2]),
            directory(members: valid.members + [valid.members[0]])]
        for value in values {
            let source = Source(value)
            XCTAssertThrowsError(try A(policy: .isolatedReadOnly, source: source).read())
            XCTAssertEqual(source.reads, 1)
        }
    }
    func testUnknownGeometryAndInvalidSpacesAreNotSilentlyFiltered() {
        let frames = [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 29, height: 37),
                      CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 37)]
        for frame in frames {
            let value = directory(ids: [1], members: [.init(windowID: 1, frame: frame, spaces: [7])])
            XCTAssertThrowsError(try A(policy: .isolatedReadOnly, source: Source(value)).read())
        }
        for spaces: [UInt64] in [[], [0], [7, 7]] {
            let value = directory(ids: [1], members: [.init(windowID: 1,
                frame: CGRect(x: -4341, y: 0, width: 29, height: 37), spaces: spaces)])
            XCTAssertThrowsError(try A(policy: .isolatedReadOnly, source: Source(value)).read())
        }
    }
    func testNativeFailureIsPreservedWithoutFallbackOrRetry() {
        let source = Source(directory()); source.error = IcePrivateWindowAPI.Failure.native(-1)
        XCTAssertThrowsError(try A(policy: .isolatedReadOnly, source: source).read()) {
            XCTAssertEqual($0 as? IcePrivateWindowAPI.Failure, .native(-1))
        }
        XCTAssertEqual(source.reads, 1)
    }
    func testNonStatusCarrierMemberIsRetainedWithoutInventingCompleteItemOrder() throws {
        let original = directory()
        let carrier = A.Member(windowID: 3, frame: CGRect(x: 0, y: 0, width: 1728, height: 37), spaces: [7])
        let raw = directory(ids: [1, 2, 3], members: original.members + [carrier])
        let returned = try A(policy: .isolatedReadOnly, source: Source(raw)).read()
        XCTAssertEqual(returned.memberIDs, [1, 2, 3])
        XCTAssertEqual(returned.members.last, carrier)
        XCTAssertFalse(returned.logicalOrderProven)
    }
}
