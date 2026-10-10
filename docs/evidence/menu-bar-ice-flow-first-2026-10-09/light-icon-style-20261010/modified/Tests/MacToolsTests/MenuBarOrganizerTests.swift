import XCTest
import CoreGraphics
import AppKit
@testable import MacTools

final class MenuBarOrganizerTests: XCTestCase {
    func testLightShelfGlyphAdaptsWhiteAndPreservesColorDarkPixelsAndAlpha() throws {
        let rgba:[UInt8]=[255,255,255,255, 255,128,0,255, 32,32,32,255, 128,128,128,128]
        let provider=try XCTUnwrap(CGDataProvider(data:Data(rgba) as CFData))
        let image=try XCTUnwrap(CGImage(width:4,height:1,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:16,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let adapted=try XCTUnwrap(MenuBarOrganizerPlugin.lightShelfGlyph(image))
        let data=try XCTUnwrap(adapted.dataProvider?.data)
        let bytes=Array(UnsafeBufferPointer(start:CFDataGetBytePtr(data),count:CFDataGetLength(data)))
        XCTAssertEqual(Array(bytes[0..<4]),[45,45,45,255])
        XCTAssertEqual(Array(bytes[4..<8]),[255,128,0,255])
        XCTAssertEqual(Array(bytes[8..<12]),[32,32,32,255])
        XCTAssertEqual(Array(bytes[12..<16]),[23,23,23,128])
        XCTAssertEqual(adapted.width,image.width);XCTAssertEqual(adapted.height,image.height)
    }

    func testPanelDropBeforeFirstResidentTileUsesFirstPeerInsteadOfDivider() {
        let frames:[CGWindowID:CGRect]=[1:CGRect(x:20,y:0,width:30,height:40),2:CGRect(x:80,y:0,width:30,height:40),3:CGRect(x:140,y:0,width:30,height:40)]
        XCTAssertEqual(MenuBarOrganizerPlugin.panelDropPeer(source:3,at:CGPoint(x:5,y:20),candidates:[1,2,3],frames:frames),1)
        XCTAssertEqual(MenuBarOrganizerPlugin.panelDropPeer(source:3,at:CGPoint(x:58,y:20),candidates:[1,2,3],frames:frames),1)
    }
    func testPanelDropGapRespectsWrappedRowAndMissingGeometry() {
        let frames:[CGWindowID:CGRect]=[1:CGRect(x:20,y:0,width:30,height:40),2:CGRect(x:20,y:80,width:30,height:40)]
        XCTAssertEqual(MenuBarOrganizerPlugin.panelDropPeer(source:3,at:CGPoint(x:5,y:100),candidates:[1,2],frames:frames),2)
        XCTAssertNil(MenuBarOrganizerPlugin.panelDropPeer(source:3,at:CGPoint(x:5,y:20),candidates:[1,2],frames:[:]))
    }
    func testPanelDropOntoSourceIsNoOpAndEmptyRowHasNoPeer() {
        let frames:[CGWindowID:CGRect]=[1:CGRect(x:20,y:0,width:30,height:40),2:CGRect(x:80,y:0,width:30,height:40)]
        XCTAssertNil(MenuBarOrganizerPlugin.panelDropPeer(source:1,at:CGPoint(x:30,y:20),candidates:[1,2],frames:frames))
        XCTAssertNil(MenuBarOrganizerPlugin.panelDropPeer(source:1,at:CGPoint(x:30,y:100),candidates:[],frames:frames))
    }
    #if ICE_MENU_BAR_INTEGRATED
    func testObservedSpotlightZeroPostLayoutReceiptIsAlreadySatisfied() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory=root.appendingPathComponent("docs/evidence/menu-bar-ice-flow-first-2026-10-09/resident-first-slot-20261010/user-session-7938969F-3C95-4B28-A075-54A29681BF21")
        let request=try JSONDecoder().decode(MenuBarIceLayoutRequest.self,from:Data(contentsOf:directory.appendingPathComponent("layout-request.json")))
        let value=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("result.json"))) as? [String:Any])
        XCTAssertTrue(try MenuBarIceInterfaceProductBridge.layoutResult(value,request:request,sourceID:39))
    }
    #endif

    func testShelfAdmissionAllowsEitherEmptyReceivingSectionButNotBothEmpty() {
        XCTAssertTrue(MenuBarOrganizerPlugin.canShowShelf(hiddenCount:0,residentCount:2))
        XCTAssertTrue(MenuBarOrganizerPlugin.canShowShelf(hiddenCount:2,residentCount:0))
        XCTAssertTrue(MenuBarOrganizerPlugin.canShowShelf(hiddenCount:1,residentCount:1))
        XCTAssertFalse(MenuBarOrganizerPlugin.canShowShelf(hiddenCount:0,residentCount:0))
    }

    @MainActor
    func testShelfPanelDoesNotActivateToolboxAndInheritsLightAndDarkAppearance() {
        let panel=ShelfDragPanel(shelfRect:NSRect(x:0,y:0,width:320,height:200))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor,.clear)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertNil(panel.appearance)
        let app=NSApplication.shared, original=NSApplication.shared.appearance
        defer { app.appearance=original }
        for name in [NSAppearance.Name.aqua,.darkAqua] {
            app.appearance=NSAppearance(named:name)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]),name)
        }
    }

    @MainActor
    func testRepeatedManualEntriesAndModeSwitchesPreserveOptOutAndLegacyConfiguration() throws {
        let name = "MenuOrganizerManualEntries.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults)
        let optedOut = try JSONEncoder().encode(false), limit = try JSONEncoder().encode(9)
        settings.set(optedOut, forKey: "optedIn")
        settings.set(limit, forKey: "visibleLimit")
        defaults.set(648.0, forKey: "NSStatusItem Preferred Position Item-0")
        let context = PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        plugin.start()
        for _ in 0..<20 {
            for mode in OrganizerPresentationMode.allCases {
                plugin.setPresentationMode(mode)
                plugin.arrangeNativeIcons()
                plugin.toggleNative()
                plugin.openShelf()
                plugin.expand()
                XCTAssertFalse(plugin.isOrganizing, "Manual entries must not silently opt in or create status items")
                XCTAssertFalse(plugin.isCapturing)
                XCTAssertFalse(plugin.allowsPanelEditing)
                XCTAssertTrue(plugin.icons.isEmpty && plugin.visibleIcons.isEmpty)
                XCTAssertEqual(settings.data(forKey: "optedIn"), optedOut)
                XCTAssertEqual(settings.data(forKey: "visibleLimit"), limit)
                XCTAssertEqual(defaults.double(forKey: "NSStatusItem Preferred Position Item-0"), 648)
                XCTAssertEqual(MenuBarOrganizerPlugin(context: context).presentationMode, mode)
            }
        }
        plugin.stop()
        XCTAssertEqual(settings.data(forKey: "optedIn"), optedOut)
        XCTAssertEqual(settings.data(forKey: "visibleLimit"), limit)
    }

    @MainActor
    func testFormerAutomaticEditingEntriesAreInertAndPreserveSettings() async {
        let name = "MenuOrganizerAXOnly.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults)
        settings.set(try! JSONEncoder().encode(7), forKey: "visibleLimit")
        let plugin = MenuBarOrganizerPlugin(context: PluginContext(settings: settings, hotkeys: HotKeyService(), report: { _ in }))
        let before = defaults.dictionaryRepresentation(), generation = plugin.gallery.generation
        plugin.beginPanelEditing(); plugin.moveIcon(1, intoShelf: true); plugin.reorderIcon(1, nextTo: 2); plugin.applyVisibleLimit()
        let moved = await plugin.postDrag(from: CGPoint(x: 500, y: 20), to: CGPoint(x: 600, y: 20), token: generation)
        XCTAssertFalse(moved)
        XCTAssertFalse(plugin.allowsPanelEditing)
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertEqual(plugin.gallery.generation, generation)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertEqual(plugin.status, MenuBarOperationFailure.movementUnavailable.message)
    }
    func testLeftClickRouteDoesNotUseInvisibleNativeToggleInIntegratedBuild() {
        #if ICE_MENU_BAR_INTEGRATED
        XCTAssertTrue(MenuBarOrganizerPlugin.opensPanelOnLeftClick(.native))
        XCTAssertTrue(MenuBarOrganizerPlugin.opensPanelOnLeftClick(.panel))
        #else
        XCTAssertFalse(MenuBarOrganizerPlugin.opensPanelOnLeftClick(.native))
        XCTAssertTrue(MenuBarOrganizerPlugin.opensPanelOnLeftClick(.panel))
        #endif
    }

    func testResidentPartitionIncludesAllSevenAppsBetweenDividerAndControl() {
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let divider = CGRect(x: 1314, y: 0, width: 24, height: 43)
        let resident: [(id: CGWindowID, frame: CGRect)] = (0..<7).map {
            (CGWindowID($0 + 100), CGRect(x: 1338 + $0 * 39, y: 0, width: 38, height: 43))
        }
        let other: [(id: CGWindowID, frame: CGRect)] = [(1, CGRect(x: 1232, y: 0, width: 38, height: 43)),
            (2, CGRect(x: 1690, y: 0, width: 33, height: 43)), (3, CGRect(x: 1370, y: 200, width: 38, height: 43))]
        let ids = MenuBarOrganizerPlugin.residentWindows(resident + other, after: divider, in: screen, statusBarY: 0).map(\.id)
        XCTAssertEqual(Set(ids), Set(resident.map(\.id) + [2]))
        XCTAssertTrue(ids.contains(106), "The seventh configured app must not disappear")
        XCTAssertEqual(MenuBarOrganizerPlugin.hiddenWindows(resident + other, leftOf: divider.minX, in: screen, statusBarY: 0).map(\.id), [1])
        XCTAssertNotNil(MenuBarOrganizerPlugin.reorderTarget(source: resident[0].frame, target: resident[1].frame,
            dividerX: divider.minX, controlX: divider.maxX, screen: screen))
    }

    func testShelfDragRoutesAcrossRowsAndReordersWithinRow() {
        let hidden = CGRect(x: 0, y: 0, width: 200, height: 40)
        let visible = CGRect(x: 0, y: 70, width: 200, height: 40)
        let frames: [CGWindowID: CGRect] = [1: CGRect(x: 10, y: 0, width: 30, height: 40),
                                            2: CGRect(x: 60, y: 0, width: 30, height: 40),
                                            3: CGRect(x: 10, y: 70, width: 30, height: 40)]
        func drop(_ id: CGWindowID, _ point: CGPoint) -> ShelfDropAction? {
            MenuBarOrganizerPlugin.shelfDrop(source: id, at: point, hidden: [1, 2], visible: [3],
                                             hiddenRow: hidden, visibleRow: visible, iconFrames: frames)
        }
        XCTAssertEqual(drop(1, CGPoint(x: 20, y: 80)), .move(1, false))
        XCTAssertEqual(drop(3, CGPoint(x: 20, y: 20)), .move(3, true))
        XCTAssertEqual(drop(1, CGPoint(x: 75, y: 20)), .reorder(1, 2))
        XCTAssertNil(drop(1, CGPoint(x: 20, y: 55)))
        XCTAssertNil(drop(99, CGPoint(x: 20, y: 20)))
    }
    func testStatusItemSlotsStayVisibleAndOrdered() {
        XCTAssertTrue(MenuBarOrganizerPlugin.sanePositions(control: 250, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: nil, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: 290, divider: 250))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: -4000, divider: 290))
        XCTAssertFalse(MenuBarOrganizerPlugin.sanePositions(control: .nan, divider: 290))
    }
    func testMainTrayPositionRestoresOnDisable() throws {
        let name = "MenuOrganizerPosition.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let main = "NSStatusItem Preferred Position Item-0"
        defaults.set(648.0, forKey: main)
        defaults.set(try JSONEncoder().encode(true), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
        XCTAssertEqual(defaults.double(forKey: "plugin.menu-bar-organizer.priorMainPosition"), 648)
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
        defaults.set(try JSONEncoder().encode(false), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 648)
        XCTAssertNil(defaults.object(forKey: "plugin.menu-bar-organizer.priorMainPosition"))
        defaults.set(450.0, forKey: main)
        defaults.set(648.0, forKey: "plugin.menu-bar-organizer.priorMainPosition")
        defaults.set(try JSONEncoder().encode(true), forKey: "plugin.menu-bar-organizer.optedIn")
        MenuBarOrganizerPlugin.prepareMainStatusPosition(defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: main), 200)
    }
    func testFailOpenGeometryAndHiddenWindowSelection() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        XCTAssertTrue(MenuBarOrganizerPlugin.canCollapse(dividerX: 700, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: 770, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: -100, controlX: 760, screen: screen))
        XCTAssertFalse(MenuBarOrganizerPlugin.canCollapse(dividerX: 700, controlX: 1300, screen: screen))
        let windows: [(id: CGWindowID, frame: CGRect)] = [
            (1, CGRect(x: 640, y: 0, width: 28, height: 24)),
            (2, CGRect(x: 670, y: 0, width: 28, height: 24)),
            (3, CGRect(x: 760, y: 0, width: 28, height: 24)),
            (4, CGRect(x: 650, y: 300, width: 28, height: 24)),
            (5, CGRect(x: 400, y: 0, width: 3000, height: 24))
        ]
        let first = MenuBarOrganizerPlugin.hiddenWindows(windows, leftOf: 710, in: screen, statusBarY: 0).map(\.id)
        XCTAssertEqual(first, [1, 2])
        var moved = windows
        moved[0] = (1, CGRect(x: 680, y: 0, width: 28, height: 24))
        moved[1] = (2, CGRect(x: 640, y: 0, width: 28, height: 24))
        XCTAssertNotEqual(MenuBarOrganizerPlugin.hiddenWindows(moved, leftOf: 710, in: screen, statusBarY: 0).map(\.id), first)
        let visible = MenuBarOrganizerPlugin.visibleWindows(windows, rightOf: 750, in: screen, statusBarY: 0).map(\.id)
        XCTAssertEqual(visible, [3])
        print("MENU BAR: only candidate status windows left of separator; recovery control geometry fail-closed")
    }
    func testActivationIsOptInAndDoesNotTouchSystemAtStartup() throws {
        let name = "MenuOrganizerTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = HotKeyService()
        let context = PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults), hotkeys: service, report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        let registry = try PluginRegistry(plugins: [plugin], defaults: defaults, report: { _ in })
        registry.startAll()
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertFalse(plugin.isCollapsed)
        registry.stopAll()
        XCTAssertFalse(plugin.isOrganizing)
        XCTAssertNil(defaults.data(forKey: "plugin.menu-bar-organizer.optedIn"))
        XCTAssertNil(service.error(owner: plugin.info.id, id: "emergency-reveal"))
        print("MENU BAR: load/stop inert until user opts in; no status icons created")
    }
    func testVisibleLimitIsClampedAndPersistedWithoutTouchingSystem() {
        let name = "MenuOrganizerTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let context = PluginContext(settings: PluginSettings(id: MenuBarOrganizerPlugin.id, defaults: defaults),
                                    hotkeys: HotKeyService(), report: { _ in })
        let plugin = MenuBarOrganizerPlugin(context: context)
        plugin.setVisibleLimit(0)
        XCTAssertEqual(plugin.visibleLimit, 1)
        plugin.setVisibleLimit(500)
        XCTAssertEqual(plugin.visibleLimit, 30)
        let reopened = MenuBarOrganizerPlugin(context: context)
        reopened.start()
        XCTAssertEqual(reopened.visibleLimit, 30)
        XCTAssertFalse(reopened.isOrganizing)
        reopened.stop()
    }
    func testReorderStaysInsideItsLane() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let a = CGRect(x: 400, y: 0, width: 28, height: 24)
        let b = CGRect(x: 460, y: 0, width: 28, height: 24)
        let hidden = MenuBarOrganizerPlugin.reorderTarget(source: a, target: b, dividerX: 600, controlX: 650, screen: screen)
        XCTAssertEqual(hidden?.x, 496)
        XCTAssertEqual(hidden?.after, true)
        XCTAssertNil(MenuBarOrganizerPlugin.reorderTarget(source: a, target: CGRect(x: 700, y: 0, width: 28, height: 24),
                                                          dividerX: 600, controlX: 650, screen: screen))
    }
}
