import XCTest
import SwiftUI
@testable import MacTools

final class FloatingPreviewTests: XCTestCase {
    private func frame() -> CGImage {
        let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 400,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        return context.makeImage()!
    }
    func testPixelSizeBoundAndAspect() {
        XCTAssertEqual(FloatingPreview.pixelSize(for: CGSize(width: 400, height: 200)), CGSize(width: 800, height: 400))
        XCTAssertEqual(FloatingPreview.pixelSize(for: CGSize(width: 4000, height: 2000)), CGSize(width: 1600, height: 800))
        XCTAssertEqual(FloatingPreview.pixelSize(for: .zero), CGSize(width: 640, height: 400))
        XCTAssertEqual(FloatingPreview.pixelSize(for: CGSize(width: CGFloat.infinity, height: 2)), CGSize(width: 640, height: 400))
    }
    @MainActor
    func testFloatingResizablePanelAndPluginStop() async throws {
        _ = NSApplication.shared
        let suite = "WindowPreviewTests.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let context = PluginContext(settings: PluginSettings(id: WindowPreviewPlugin.id, defaults: defaults), hotkeys: HotKeyService(), report: { _ in })
        let plugin = WindowPreviewPlugin(context: context)
        let registry = try PluginRegistry(plugins: [plugin], defaults: defaults, report: { _ in })
        registry.startAll()
        let image = frame()
        plugin.preview.begin(title: "fixture", showPanel: false, capture: { image })
        defer { plugin.stop() }
        for _ in 0..<100 where plugin.preview.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(plugin.preview.image)
        let panel = try XCTUnwrap(plugin.preview.panel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        for size in [NSSize(width: 900, height: 300), NSSize(width: 300, height: 500)] {
            panel.setContentSize(size); panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(try XCTUnwrap(panel.contentView).bounds.width, size.width, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(panel.contentView).bounds.height, size.height, accuracy: 1)
        }
        XCTAssertTrue(registry.setEnabled(false, id: plugin.info.id))
        XCTAssertNil(plugin.preview.panel); XCTAssertNil(plugin.preview.image); XCTAssertFalse(plugin.preview.isRunning)
        print("PREVIEW: floating + resizable; landscape/portrait sizes verified; disabling plugin clears panel and pixels")
    }
    @MainActor
    func testStopDiscardsLateFrameAndErrorsClearImage() async throws {
        _ = NSApplication.shared
        let preview = FloatingPreview(); let image = frame()
        var pending: CheckedContinuation<CGImage, Error>?
        preview.begin(title: "delayed", showPanel: false) {
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        defer { preview.stop() }
        for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let continuation = try XCTUnwrap(pending)
        preview.stop(); continuation.resume(returning: image)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(preview.image); XCTAssertNil(preview.panel)
        preview.begin(title: "failed", showPanel: false) { throw Failure.message("test source closed") }
        for _ in 0..<100 where preview.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(preview.isRunning); XCTAssertNil(preview.image)
        XCTAssertTrue(preview.status.contains("test source closed"))
        print("PREVIEW: cancelled in-flight frame discarded; source failure clears stale pixels")
    }
}
