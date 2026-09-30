import Foundation
import CoreGraphics

enum OrganizerPresentationMode: String, Codable, CaseIterable {
    case native, panel
    var title: String { self == .native ? "原生展开（推荐）" : "图标面板" }

    static func load(from settings: PluginSettings) -> Self {
        if let data = settings.data(forKey: "presentationMode"),
           let mode = try? JSONDecoder().decode(Self.self, from: data) { return mode }
        // An existing opt-in choice, including false, identifies the old panel workflow.
        return settings.data(forKey: "optedIn") == nil ? .native : .panel
    }
}

// Pure transitions: AppKit effects are performed by the plugin, never by a test fixture.
struct MenuBarVisibility {
    enum State: Equatable { case disabled, expanded, collapsing, collapsed }
    private(set) var state: State = .disabled
    private(set) var generation = UUID()

    mutating func enable() { generation = UUID(); state = .expanded }
    mutating func expand() {
        generation = UUID()
        if state != .disabled { state = .expanded }
    }
    // Normal dismissal preserves a confirmed collapse; incomplete capture/confirmation fails open.
    @discardableResult mutating func dismissPopover() -> Bool {
        if state == .collapsed { generation = UUID(); return true }
        expand(); return false
    }
    mutating func disable() { generation = UUID(); state = .disabled }
    mutating func beginCollapse() -> UUID? {
        guard state == .expanded else { return nil }
        generation = UUID(); state = .collapsing
        return generation
    }
    @discardableResult mutating func finishCollapse(_ token: UUID, recoveryVisible: Bool) -> Bool {
        guard state == .collapsing, generation == token else { return false }
        state = recoveryVisible ? .collapsed : .expanded
        return recoveryVisible
    }

    static func collapsedLength(screenWidths: [CGFloat]) -> CGFloat {
        let width = screenWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 1728
        return max(500, min(width * 2, 10_000))
    }
    static func interactionPointVisible(_ point: CGPoint, safeAreas: [CGRect]) -> Bool {
        safeAreas.contains { $0.contains(point) }
    }
    static func recoveryVisible(_ frame: CGRect, safeAreas: [CGRect]) -> Bool {
        guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0 else { return false }
        return safeAreas.contains { $0.contains(frame) }
    }
}

// The gallery owns only this opening's images. Window IDs and pixels are never persisted.
struct MenuBarGallerySession {
    private(set) var generation = UUID()
    private(set) var isCapturing = false
    private(set) var icons: [ShelfIcon] = []
    private(set) var visibleIcons: [ShelfIcon] = []

    mutating func clear() {
        generation = UUID(); isCapturing = false
        icons = []; visibleIcons = []
    }
    mutating func beginCapture() -> UUID {
        clear(); isCapturing = true
        return generation
    }
    @discardableResult mutating func finishCapture(_ token: UUID, icons: [ShelfIcon], visible: [ShelfIcon]) -> Bool {
        guard generation == token, isCapturing else { return false }
        self.icons = icons; visibleIcons = visible; isCapturing = false
        return true
    }
}

// Keep one opening bounded to four requests; injectable snapshots need no screen permission in tests.
enum MenuBarCapture {
    static func ordered<Item: Sendable>(count: Int,
        snapshot: @escaping @Sendable (Int) async throws -> Item) async throws -> [Item] {
        guard count > 0 else { return [] }
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Int, Item).self) { group in
            func add(_ index: Int) {
                group.addTask {
                    try Task.checkCancellation()
                    return (index, try await snapshot(index))
                }
            }
            let initial = min(4, count)
            for index in 0..<initial { add(index) }
            var next = initial
            var results = [Item?](repeating: nil, count: count)
            while let (index, item) = try await group.next() {
                try Task.checkCancellation()
                results[index] = item
                if next < count { add(next); next += 1 }
            }
            return try results.map {
                guard let item = $0 else { throw Failure.message("图标采集不完整") }
                return item
            }
        }
    }
}

// Fixed hit areas and at most two grid rows per page; no clipped icons or scrollbars.
enum MenuBarPopoverLayout {
    static let tile: CGFloat = 56
    static let gap: CGFloat = 6
    static func width(iconCount: Int, screenWidth: CGFloat) -> CGFloat {
        let columns = min(8, max(1, iconCount))
        return min(max(48, screenWidth - 32), max(240, CGFloat(columns) * (tile + gap) - gap + 20))
    }
    static func columns(width: CGFloat) -> Int {
        max(1, min(8, Int((max(0, width - 20) + gap) / (tile + gap))))
    }
    static func pageRange(count: Int, page: Int, columns: Int) -> Range<Int> {
        let count = max(0, count), capacity = max(1, columns) * 2
        let page = max(0, min(page, max(0, (count - 1) / capacity)))
        let start = min(count, page * capacity)
        return start..<min(count, start + capacity)
    }
}
