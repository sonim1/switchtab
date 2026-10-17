import AppKit
import XCTest
@testable import SwitchTab

@MainActor
final class SwitchingFeedbackTests: XCTestCase {
    func testPanelIsPassiveAndContentIsReadable() {
        let controller = SwitchingFeedbackController(announce: { _ in })
        controller.show(.noWindows)
        defer { controller.dismiss() }
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertFalse(controller.panel.canBecomeMain)
        XCTAssertTrue(controller.panel.ignoresMouseEvents)
        XCTAssertTrue(controller.panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(controller.label.stringValue, SwitchingFeedbackController.Notice.noWindows.message)
        XCTAssertEqual(controller.label.accessibilityRole(), .staticText)
        XCTAssertEqual(controller.label.accessibilityIdentifier(), "switching-feedback")
    }

    func testRepeatedNoticeDoesNotAnnounceOrReplaceItsTimer() {
        var announcements: [String] = []
        let controller = SwitchingFeedbackController(announce: { announcements.append($0) })
        controller.show(.noWindows)
        let generation = controller.generation
        controller.show(.noWindows)
        XCTAssertEqual(controller.generation, generation)
        XCTAssertEqual(announcements.count, 1)
        controller.dismiss()
    }

    func testStaleDismissalCannotHideReplacement() {
        let controller = SwitchingFeedbackController(announce: { _ in })
        controller.show(.noWindows)
        let previous = controller.generation
        controller.show(.practiceCompleted)
        controller.dismiss(generation: previous)
        XCTAssertEqual(controller.notice, .practiceCompleted)
        controller.dismiss(generation: controller.generation)
        XCTAssertNil(controller.notice)
        XCTAssertFalse(controller.panel.isVisible)
    }

    func testNoticeAutomaticallyDismisses() async throws {
        let controller = SwitchingFeedbackController(announce: { _ in })
        controller.show(.noWindows)
        try await Task.sleep(for: .milliseconds(3200))
        XCTAssertNil(controller.notice)
        XCTAssertFalse(controller.panel.isVisible)
    }

    func testPlacementStaysInsidePointerScreenAndAboveOverlay() {
        let screen = CGRect(x: -1200, y: 30, width: 1200, height: 800)
        let overlay = CGRect(x: -1000, y: 200, width: 800, height: 300)
        let frame = SwitchingFeedbackController.frame(in: screen, above: overlay)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertGreaterThan(frame.minY, overlay.maxY)
        XCTAssertEqual(frame.midX, screen.midX)
        let crowded = SwitchingFeedbackController.frame(in: screen, above: screen)
        XCTAssertTrue(screen.contains(crowded))
        let nearTop = CGRect(x: -1000, y: 400, width: 800, height: 400)
        let below = SwitchingFeedbackController.frame(in: screen, above: nearTop)
        XCTAssertTrue(screen.contains(below))
        XCTAssertLessThan(below.maxY, nearTop.minY)
    }
}
