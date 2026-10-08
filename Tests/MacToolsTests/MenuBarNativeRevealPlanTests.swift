import XCTest
import CoreGraphics
@testable import MacTools

final class MenuBarNativeRevealPlanTests: XCTestCase {
    private let generation = UUID()
    private let application = MenuBarApplicationIdentity(bundleID: "test", bundlePath: "/Test.app", launch: 1)
    private func sample(shift: CGFloat = 0, spacerGrowth: CGFloat? = nil,
                        menuWidth: CGFloat = 300, recoveryShift: CGFloat = 0,
                        launch: Double = 1, onScreen: Bool = true,
                        order: [UInt32] = [1, 2, 3], generation: UUID? = nil) -> MenuBarNativeRevealPlan.Observation {
        let growth = spacerGrowth ?? shift
        return .init(generation: generation ?? self.generation, displayID: 1,
            target: MenuBarStatusTarget(id: 1, pid: 10,
                frame: CGRect(x: 963 - shift, y: 0, width: 42, height: 43), onScreen: onScreen,
                application: MenuBarApplicationIdentity(bundleID: application.bundleID, bundlePath: application.bundlePath, launch: launch)),
            targetButton: CGRect(x: 971 - shift, y: 10.5, width: 26, height: 22),
            ownedSpacer: CGRect(x: 1586 - growth, y: 0, width: 38 + growth, height: 43),
            recoveryButton: CGRect(x: 1632 + recoveryShift, y: 9.5, width: 17, height: 24),
            safeAreas: [CGRect(x: 0, y: 0, width: 918, height: 38), CGRect(x: 1138, y: 0, width: 918, height: 38)],
            applicationMenu: CGRect(x: 0, y: 0, width: menuWidth, height: 38), orderedWindowIDs: order)
    }
    func testPlansOwnWidthIncreaseAndVerifiesMeasuredNativeReflow() throws {
        let plan = try MenuBarNativeRevealPlan.make(sample())
        XCTAssertEqual(plan.requestedExtraLength, 83)
        // Native backing width may grow more than requested NSStatusItem length.
        XCTAssertNoThrow(try plan.verify(sample(shift: plan.requestedExtraLength + 16)))
        XCTAssertNoThrow(try plan.verify(sample(shift: plan.requestedExtraLength)))
    }
    func testApplicationMenusAndBoundedSpaceAreRequired() {
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(menuWidth: 900))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .noSpace)
        }
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(), maximumExtraLength: 50)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .noSpace)
        }
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(), maximumExtraLength: .nan)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .invalidObservation)
        }
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(shift: 700))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .noSpace, "Left of app menus cannot be rescued by more leftward reflow")
        }
    }
    func testAlreadyVisibleTargetDoesNotRequestReflow() {
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(shift: 200))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .alreadyVisible)
        }
    }
    func testRejectsReflowWithoutVisibilityCorrespondenceAndRecoveryAnchor() throws {
        let plan = try MenuBarNativeRevealPlan.make(sample())
        for after in [sample(shift: 20), sample(shift: 100, spacerGrowth: 20),
                      sample(shift: 100, recoveryShift: -100),
                      sample(shift: 800)] {
            XCTAssertThrowsError(try plan.verify(after)) {
                XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .unverifiedReflow)
            }
        }
    }
    func testHiddenTargetMayAttemptOwnWidthButInteractionRequiresOrderedOnScreen() throws {
        let plan = try MenuBarNativeRevealPlan.make(sample())
        XCTAssertThrowsError(try plan.verify(sample(shift: 100, onScreen: false))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .targetNotOnScreen)
        }
        let attempt = try MenuBarNativeRevealPlan.make(sample(shift: 200, onScreen: false))
        XCTAssertEqual(attempt.purpose, .attemptUnorderedTarget)
        XCTAssertEqual(attempt.requestedExtraLength, 26)
        XCTAssertThrowsError(try attempt.verify(sample(shift: 226, onScreen: false))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .targetNotOnScreen)
        }
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(shift: 660, onScreen: false))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .noSpace)
        }
    }
    func testEnvironmentIdentityAndRelativeOrderCannotChange() throws {
        let plan = try MenuBarNativeRevealPlan.make(sample())
        XCTAssertThrowsError(try plan.verify(sample(shift: 100, generation: UUID()))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedEnvironment)
        }
        XCTAssertThrowsError(try plan.verify(sample(shift: 100, menuWidth: 320))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedEnvironment)
        }
        XCTAssertThrowsError(try plan.verify(sample(shift: 100, launch: 2))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedIdentity)
        }
        XCTAssertThrowsError(try plan.verify(sample(shift: 100, order: [2, 1, 3]))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .changedOrder)
        }
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(order: [1, 1, 3]))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .invalidObservation)
        }
    }
    func testRecoveryAnchorAlreadyHiddenOrNoNotchGeometryIsRejected() {
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(sample(recoveryShift: -620))) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .unsupportedLayout)
        }
        let normal = sample()
        let ambiguous = MenuBarNativeRevealPlan.Observation(generation: normal.generation, displayID: 1,
            target: normal.target, targetButton: normal.targetButton, ownedSpacer: normal.ownedSpacer,
            recoveryButton: normal.recoveryButton, safeAreas: [], applicationMenu: normal.applicationMenu,
            orderedWindowIDs: normal.orderedWindowIDs)
        XCTAssertThrowsError(try MenuBarNativeRevealPlan.make(ambiguous)) {
            XCTAssertEqual($0 as? MenuBarNativeRevealPlan.Failure, .unsupportedLayout)
        }
    }
}
