import XCTest
import CoreGraphics
import Combine
@testable import MacTools

final class MenuBarVisibilityTests: XCTestCase {
    func testRejectedMovePublishesRecoveryOnMainThreadWhenCalledFromBackground() async throws {
        let name = "MenuBarMoveActorTests.\(UUID())"
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        let probe = MainThreadDeliveryProbe()
        let (plugin, observation, token) = await MainActor.run {
            let plugin = MenuBarOrganizerPlugin(context: PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: prefs), hotkeys: HotKeyService(), report: { _ in }))
            let observation = plugin.$status.dropFirst().sink { _ in probe.record(Thread.isMainThread) }
            return (plugin, observation, plugin.gallery.generation)
        }
        let moved = await Task.detached {
            await plugin.postDrag(from: CGPoint(x: -100_000, y: -100_000), to: CGPoint(x: -100_000, y: -100_000), token: token)
        }.value
        XCTAssertFalse(moved)
        XCTAssertFalse(probe.deliveries.isEmpty)
        XCTAssertTrue(probe.deliveries.allSatisfy { $0 }, "Rejected movement must present and publish recovery on the main thread")
        await MainActor.run { observation.cancel() }
    }

    func testNormalPopoverDismissalKeepsConfirmedCollapseAndIncompleteWorkFailsOpen() throws {
        var strip = MenuBarVisibility(); strip.enable()
        let token = try XCTUnwrap(strip.beginCollapse())
        XCTAssertTrue(strip.finishCollapse(token, recoveryVisible: true))
        XCTAssertTrue(strip.dismissPopover())
        XCTAssertEqual(strip.state, .collapsed)
        XCTAssertTrue(strip.dismissPopover())
        XCTAssertEqual(strip.state, .collapsed)
        strip.expand(); XCTAssertEqual(strip.state, .expanded)
        _ = strip.beginCollapse()
        XCTAssertFalse(strip.dismissPopover())
        XCTAssertEqual(strip.state, .expanded)
        strip.disable(); XCTAssertFalse(strip.dismissPopover()); XCTAssertEqual(strip.state, .disabled)
    }

    func testSixSevenAndManyResidentsKeepIdentityWhenThumbnailIsUnavailable() {
        for count in [6, 7, 17, 40] {
            let residents = (0..<count).map { ShelfIcon(id: CGWindowID($0 + 1), frame: CGRect(x: $0 * 40, y: 0, width: 38, height: 43), image: nil) }
            var gallery = MenuBarGallerySession(); let token = gallery.beginCapture()
            XCTAssertTrue(gallery.finishCapture(token, icons: [], visible: residents))
            XCTAssertEqual(gallery.visibleIcons.map(\.id), residents.map(\.id))
            XCTAssertEqual(gallery.visibleIcons.count, count)
            let columns = MenuBarPopoverLayout.columns(width: MenuBarPopoverLayout.width(iconCount: count, screenWidth: 2056))
            let pages = max(1, (count + columns * 2 - 1) / (columns * 2))
            XCTAssertEqual((0..<pages).flatMap { MenuBarPopoverLayout.pageRange(count: count, page: $0, columns: columns) }, Array(0..<count))
            gallery.clear(); XCTAssertTrue(gallery.visibleIcons.isEmpty)
        }
    }

    func testCollapseConfirmationAndInterruptedTransitions() throws {
        var strip = MenuBarVisibility()
        XCTAssertNil(strip.beginCollapse())
        strip.enable()
        let first = try XCTUnwrap(strip.beginCollapse())
        XCTAssertEqual(strip.state, .collapsing)
        XCTAssertNil(strip.beginCollapse())
        strip.expand()
        XCTAssertFalse(strip.finishCollapse(first, recoveryVisible: true))
        XCTAssertEqual(strip.state, .expanded)
        let second = try XCTUnwrap(strip.beginCollapse())
        XCTAssertTrue(strip.finishCollapse(second, recoveryVisible: true))
        XCTAssertEqual(strip.state, .collapsed)
        strip.expand()
        let third = try XCTUnwrap(strip.beginCollapse())
        strip.disable()
        XCTAssertFalse(strip.finishCollapse(third, recoveryVisible: true))
        XCTAssertEqual(strip.state, .disabled)
        strip.enable()
        XCTAssertFalse(strip.finishCollapse(third, recoveryVisible: true))
        XCTAssertEqual(strip.state, .expanded)
    }

    func testFailedRecoveryKeepsStripExpanded() throws {
        var strip = MenuBarVisibility(); strip.enable()
        let token = try XCTUnwrap(strip.beginCollapse())
        XCTAssertFalse(strip.finishCollapse(token, recoveryVisible: false))
        XCTAssertEqual(strip.state, .expanded)
        XCTAssertFalse(strip.finishCollapse(token, recoveryVisible: true))
    }

    func testRecoveryGeometryRejectsNotchAndPartiallyOffscreenControl() {
        let areas = [CGRect(x: -1440, y: 900, width: 600, height: 30),
                     CGRect(x: -700, y: 900, width: 700, height: 30)]
        XCTAssertTrue(MenuBarVisibility.recoveryVisible(CGRect(x: -60, y: 900, width: 28, height: 24), safeAreas: areas))
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(CGRect(x: -800, y: 900, width: 28, height: 24), safeAreas: areas))
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(CGRect(x: -10, y: 900, width: 28, height: 24), safeAreas: areas))
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(.null, safeAreas: areas))
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(.zero, safeAreas: areas))
        XCTAssertEqual(MenuBarVisibility.collapsedLength(screenWidths: [1440, 2560]), 5120)
        XCTAssertEqual(MenuBarVisibility.collapsedLength(screenWidths: [8000]), 10_000)
        XCTAssertEqual(MenuBarVisibility.collapsedLength(screenWidths: [.nan, .infinity, -20]), 3456)
    }

    func testNotchRecoveryUsesVisibleButtonInsteadOfTallerStatusWindow() {
        let rightArea = CGRect(x: 956, y: 1085, width: 772, height: 32)
        let statusWindow = CGRect(x: 1291, y: 1080, width: 38, height: 37)
        let visibleButton = CGRect(x: 1290, y: 1086.5, width: 39.5, height: 24)
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(statusWindow, safeAreas: [rightArea]))
        XCTAssertTrue(MenuBarVisibility.recoveryVisible(visibleButton, safeAreas: [rightArea]))
        XCTAssertFalse(MenuBarVisibility.recoveryVisible(CGRect(x: 945, y: 1086.5, width: 39.5, height: 24), safeAreas: [rightArea]))
    }

    func testGalleryReleasesImagesAndRejectsLateOrDuplicateCapture() {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let icon = ShelfIcon(id: 42, frame: CGRect(x: 10, y: 0, width: 24, height: 24), image: context.makeImage()!)
        var gallery = MenuBarGallerySession()
        let first = gallery.beginCapture()
        XCTAssertTrue(gallery.finishCapture(first, icons: [icon], visible: [icon]))
        XCTAssertFalse(gallery.isCapturing)
        XCTAssertFalse(gallery.finishCapture(first, icons: [], visible: []))
        XCTAssertEqual(gallery.icons.count, 1)
        gallery.clear()
        XCTAssertTrue(gallery.icons.isEmpty); XCTAssertTrue(gallery.visibleIcons.isEmpty)
        let cancelled = gallery.beginCapture()
        gallery.clear()
        XCTAssertFalse(gallery.finishCapture(cancelled, icons: [icon], visible: [icon]))
        let current = gallery.beginCapture()
        XCTAssertFalse(gallery.finishCapture(cancelled, icons: [icon], visible: [icon]))
        XCTAssertTrue(gallery.isCapturing)
        XCTAssertTrue(gallery.finishCapture(current, icons: [icon], visible: []))
    }

    func testCaptureHandlesSmallGroupsPreservesOrderAndBoundsConcurrency() async throws {
        for count in 0...7 {
            let probe = CaptureProbe()
            let images = try await MenuBarCapture.ordered(count: count) { index in
                await probe.enter(index)
                try await Task.sleep(nanoseconds: UInt64(8 - index) * 1_000_000)
                await probe.leave()
                return index
            }
            XCTAssertEqual(images, Array(0..<count))
            let peak = await probe.peak
            XCTAssertLessThanOrEqual(peak, 4)
            let started = await probe.started
            XCTAssertEqual(started.sorted(), Array(0..<count))
        }
    }

    func testCancellationStopsCaptureBeforeRefillingBatch() async throws {
        let probe = CaptureProbe()
        let task = Task {
            try await MenuBarCapture.ordered(count: 12) { index in
                await probe.enter(index)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return index
            }
        }
        await probe.waitForStart()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled capture must not return images")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let started = await probe.started
        XCTAssertLessThanOrEqual(started.count, 4)
    }

    func testCaptureFailureDoesNotReturnPartialGallery() async throws {
        enum CaptureError: Error { case failed }
        do {
            _ = try await MenuBarCapture.ordered(count: 3) { index in
                if index == 1 { throw CaptureError.failed }
                try await Task.sleep(nanoseconds: 10_000_000)
                return index
            }
            XCTFail("A partial capture must fail")
        } catch CaptureError.failed {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testToolboxCallbackSelectsOrganizerAndExposesEditingWithoutDelegateCast() throws {
        let name = "MenuBarToolboxTests.\(UUID())"; let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        let model = AppModel(defaults: prefs)
        var opens = 0
        model.showToolbox = { opens += 1 }
        let plugin = try XCTUnwrap(model.plugins.plugins.first(where: { $0.info.id == MenuBarOrganizerPlugin.id }) as? MenuBarOrganizerPlugin)
        plugin.openToolbox()
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(model.selectedPluginID, MenuBarOrganizerPlugin.id)
        XCTAssertTrue(plugin.showsAdvancedOptions)
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertTrue(plugin.icons.isEmpty)
        plugin.openToolbox()
        XCTAssertEqual(opens, 2)
    }

    func testPopoverWidthFitsSmallAndLargeCollections() {
        XCTAssertEqual(MenuBarPopoverLayout.width(iconCount: 1, screenWidth: 1440), 240)
        XCTAssertEqual(MenuBarPopoverLayout.width(iconCount: 7, screenWidth: 1440), 448)
        XCTAssertEqual(MenuBarPopoverLayout.width(iconCount: 30, screenWidth: 1440), 510)
        XCTAssertEqual(MenuBarPopoverLayout.width(iconCount: 30, screenWidth: 320), 288)
    }

    func testInteractionRejectsNotchAndAcceptsSafePointOnBothDisplays() {
        let areas = [CGRect(x: 0, y: 1085, width: 771, height: 32), CGRect(x: 956, y: 1085, width: 772, height: 32), CGRect(x: -533, y: 1117, width: 3360, height: 1890)]
        XCTAssertFalse(MenuBarVisibility.interactionPointVisible(CGPoint(x: 850, y: 1100), safeAreas: areas))
        XCTAssertTrue(MenuBarVisibility.interactionPointVisible(CGPoint(x: 1310, y: 1100), safeAreas: areas))
        XCTAssertTrue(MenuBarVisibility.interactionPointVisible(CGPoint(x: -500, y: 1140), safeAreas: areas))
        XCTAssertFalse(MenuBarVisibility.interactionPointVisible(CGPoint(x: -550, y: 1100), safeAreas: areas))
    }

    func testGridPagingKeepsEveryIconReachableWithLargeHitAreas() {
        XCTAssertEqual(MenuBarPopoverLayout.columns(width: 510), 8)
        XCTAssertEqual(MenuBarPopoverLayout.columns(width: 288), 4)
        XCTAssertGreaterThanOrEqual(MenuBarPopoverLayout.tile, 44)
        for columns in [1, 4, 8] {
            for count in [0, 1, 3, 6, 7, 12, 17, 40] {
                let pages = max(1, (count + columns * 2 - 1) / (columns * 2))
                let indices = (0..<pages).flatMap { MenuBarPopoverLayout.pageRange(count: count, page: $0, columns: columns) }
                XCTAssertEqual(indices, Array(0..<count))
                XCTAssertEqual(MenuBarPopoverLayout.pageRange(count: count, page: 999, columns: columns).upperBound, count)
            }
        }
    }

    func testNewUsersStayNativeAfterFirstOptInAndExplicitModePersists() throws {
        let name = "MenuBarModeTests.\(UUID())"; let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: prefs)
        let context = PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        XCTAssertEqual(plugin.presentationMode, .native)
        XCTAssertFalse(plugin.isOrganizing)
        // Simulate the saved opt-in bit without creating a real status item.
        settings.set(try JSONEncoder().encode(true), forKey: "optedIn")
        XCTAssertEqual(MenuBarOrganizerPlugin(context: context).presentationMode, .native)
        plugin.setPresentationMode(.panel)
        XCTAssertEqual(MenuBarOrganizerPlugin(context: context).presentationMode, .panel)
        plugin.setPresentationMode(.native)
        XCTAssertEqual(MenuBarOrganizerPlugin(context: context).presentationMode, .native)
        XCTAssertFalse(plugin.isOrganizing)
    }

    func testLegacyPanelChoiceAndVisibleLimitRemainIntact() throws {
        for optedIn in [false, true] {
            let name = "MenuBarLegacyTests.\(UUID())"; let prefs = UserDefaults(suiteName: name)!
            defer { prefs.removePersistentDomain(forName: name) }
            let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: prefs)
            let legacy = try JSONEncoder().encode(optedIn)
            let limit = try JSONEncoder().encode(9)
            settings.set(legacy, forKey: "optedIn"); settings.set(limit, forKey: "visibleLimit")
            let context = PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in })
            let plugin = MenuBarOrganizerPlugin(context: context)
            XCTAssertEqual(plugin.presentationMode, .panel)
            XCTAssertFalse(plugin.isOrganizing)
            XCTAssertFalse(plugin.allowsPanelEditing)
            XCTAssertEqual(settings.data(forKey: "optedIn"), legacy)
            XCTAssertEqual(settings.data(forKey: "visibleLimit"), limit)
            XCTAssertEqual(OrganizerPresentationMode.load(from: settings), .panel)
        }
    }
}

private actor CaptureProbe {
    private var active = 0
    private(set) var peak = 0
    private(set) var started: [Int] = []
    private var waiter: CheckedContinuation<Void, Never>?
    func enter(_ index: Int) {
        active += 1; peak = max(peak, active); started.append(index)
        waiter?.resume(); waiter = nil
    }
    func leave() { active -= 1 }
    func waitForStart() async {
        if !started.isEmpty { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private final class MainThreadDeliveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func record(_ value: Bool) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var deliveries: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
}
