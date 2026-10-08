// Portions from Ice 0.11.12, Jordan Baird and contributors, GNU GPL version 3.
// Modified by Ryan.AI, 2026-10-03: selected ABI subset, prefixed names, dynamic
// C bindings, throwing failures and bounded reads. See THIRD_PARTY_NOTICES.md.
import Foundation
import CoreGraphics
import Darwin

enum IcePrivateWindowAPI {
    // Adapted from Ice/Bridging/Shims/Private.swift (fixed d567f1ec).
    typealias ConnectionID = Int32
    typealias SpaceID = UInt
    struct SpaceMask: OptionSet {
        let rawValue: UInt32
        static let includesCurrent = SpaceMask(rawValue: 1 << 0)
        static let includesOthers = SpaceMask(rawValue: 1 << 1)
        static let includesUser = SpaceMask(rawValue: 1 << 2)
        static let allSpaces: SpaceMask = [.includesOthers, .includesCurrent, .includesUser]
    }
    enum Failure: Error, Equatable {
        case unavailable(String), native(Int32), invalidCount, invalidSpace, invalidFrame
    }

    // No strong private symbol imports: disabled builds must still load on
    // systems where a symbol disappears. Loading occurs only inside read().
    final class Bindings {
        typealias MainConnection = @convention(c) () -> ConnectionID
        typealias WindowCount = @convention(c) (ConnectionID, ConnectionID, UnsafeMutablePointer<Int32>) -> Int32
        typealias MenuWindows = @convention(c) (ConnectionID, ConnectionID, Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<Int32>) -> Int32
        typealias Frame = @convention(c) (ConnectionID, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
        typealias ActiveSpace = @convention(c) (ConnectionID) -> SpaceID
        typealias WindowSpaces = @convention(c) (ConnectionID, UInt32, CFArray) -> Unmanaged<CFArray>?
        private let handle: UnsafeMutableRawPointer
        private let audit: (String) -> Void
        let mainConnection: MainConnection
        let windowCount: WindowCount
        let menuWindows: MenuWindows
        let frame: Frame
        let activeSpace: ActiveSpace
        let windowSpaces: WindowSpaces

        init(audit: @escaping (String) -> Void = { _ in }) throws {
            self.audit = audit
            guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL) else {
                throw Failure.unavailable("CoreGraphics")
            }
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let address = dlsym(handle, name) else { throw Failure.unavailable(name) }
                return unsafeBitCast(address, to: T.self)
            }
            do {
                mainConnection = try symbol("CGSMainConnectionID", MainConnection.self)
                windowCount = try symbol("CGSGetWindowCount", WindowCount.self)
                menuWindows = try symbol("CGSGetProcessMenuBarWindowList", MenuWindows.self)
                frame = try symbol("CGSGetScreenRectForWindow", Frame.self)
                activeSpace = try symbol("CGSGetActiveSpace", ActiveSpace.self)
                windowSpaces = try symbol("CGSCopySpacesForWindows", WindowSpaces.self)
                self.handle = handle
            } catch { dlclose(handle); throw error }
        }
        deinit { dlclose(handle) }

        // Adapted from Bridging.getMenuBarWindowList/getWindowFrame/getSpaceList.
        // Membership is not a persistent logical-order API.
        func read() throws -> IceMenuBarReadAdapter.Directory {
            audit("CGSMainConnectionID")
            let cid = mainConnection()
            guard cid > 0 else { throw Failure.unavailable("connection") }
            audit("CGSGetActiveSpace")
            let spaceBefore = activeSpace(cid)
            guard spaceBefore > 0 else { throw Failure.invalidSpace }
            var count: Int32 = 0
            audit("CGSGetWindowCount")
            try success(windowCount(cid, 0, &count))
            guard count >= 0, count < 4096 else { throw Failure.invalidCount }
            let ids = try membership(cid: cid, capacity: Int(count) + 1)
            var windows: [IceMenuBarReadAdapter.Member] = []
            for id in ids {
                var rect = CGRect.zero
                audit("CGSGetScreenRectForWindow")
                try success(frame(cid, id, &rect))
                guard Self.valid(rect) else { throw Failure.invalidFrame }
                audit("CGSCopySpacesForWindows")
                guard let value = windowSpaces(cid, SpaceMask.allSpaces.rawValue, [id] as CFArray) else { throw Failure.invalidSpace }
                let array = value.takeRetainedValue()
                guard let numbers = array as? [NSNumber], !numbers.isEmpty,
                      numbers.allSatisfy({ CFGetTypeID($0) == CFNumberGetTypeID()
                          && $0.doubleValue.isFinite && $0.doubleValue > 0
                          && $0.doubleValue.rounded(.towardZero) == $0.doubleValue
                          && $0.doubleValue < Double(UInt64.max) }) else { throw Failure.invalidSpace }
                let spaces = numbers.map(\.uint64Value)
                guard Set(spaces).count == spaces.count else { throw Failure.invalidSpace }
                windows.append(.init(windowID: id, frame: rect, spaces: spaces))
            }
            var countAfter: Int32 = 0
            audit("CGSGetWindowCount")
            try success(windowCount(cid, 0, &countAfter))
            let idsAfter = try membership(cid: cid, capacity: Int(count) + 1)
            audit("CGSGetActiveSpace")
            return .init(memberIDs: ids, members: windows, spaceBefore: UInt64(spaceBefore),
                         spaceAfter: UInt64(activeSpace(cid)), enumerationComplete: countAfter == count && idsAfter == ids)
        }
        private func membership(cid: ConnectionID, capacity: Int) throws -> [UInt32] {
            var list = [UInt32](repeating: 0, count: capacity), actual: Int32 = 0
            audit("CGSGetProcessMenuBarWindowList")
            try list.withUnsafeMutableBufferPointer { buffer in
                try success(menuWindows(cid, 0, Int32(buffer.count), buffer.baseAddress!, &actual))
            }
            guard actual >= 0, actual < list.count, actual <= 512 else { throw Failure.invalidCount }
            let ids = Array(list.prefix(Int(actual)))
            guard !ids.contains(0), Set(ids).count == ids.count else { throw Failure.invalidCount }
            return ids
        }
        private func success(_ result: Int32) throws { if result != 0 { throw Failure.native(result) } }
        private static func valid(_ rect: CGRect) -> Bool {
            !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite
                && rect.maxX.isFinite && rect.maxY.isFinite && rect.width > 0 && rect.height > 0
        }
    }
}
