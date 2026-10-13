import AppKit
import XCTest
@testable import SwitchTab

@MainActor
final class SettingsWindowLifecycleTests: XCTestCase {
    func testAuxiliaryPanelsDoNotHideWhenTheApplicationDeactivates() {
        _ = NSApplication.shared
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(origin: .zero, size: SettingsWindowSizingPolicy.contentSize))
        let panel = FloatingPanelFactory.panel(
            title: "SwitchTab panel policy test",
            contentSize: SettingsWindowSizingPolicy.contentSize,
            contentViewController: controller
        )

        XCTAssertFalse(panel.hidesOnDeactivate)
        panel.close()
    }

    func testCancelClearsOwnershipBeforeStoppingRecordingExactlyOnce() {
        let coordinator = ShortcutRecordingCoordinator()
        var stops = 0
        coordinator.begin(mode: .currentAppWindowSwitching) {
            XCTAssertNil(coordinator.activeMode)
            stops += 1
            coordinator.end(mode: .currentAppWindowSwitching)
        }

        coordinator.cancel()
        coordinator.cancel()

        XCTAssertEqual(stops, 1)
        XCTAssertNil(coordinator.activeMode)
    }

    func testCancelWithoutRecordingDoesNotStopAFutureRecording() {
        let coordinator = ShortcutRecordingCoordinator()
        coordinator.cancel()
        var stops = 0
        coordinator.begin(mode: .applicationSwitching) { stops += 1 }

        XCTAssertEqual(stops, 0)
        XCTAssertEqual(coordinator.activeMode, .applicationSwitching)
        coordinator.cancel()
        XCTAssertEqual(stops, 1)
    }

    func testClosingRetainedSettingsPanelStopsRecording() throws {
        _ = NSApplication.shared
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let coordinator = ShortcutRecordingCoordinator()
        let controller = SettingsWindowController(
            activationCoordinator: SettingsActivationPolicyCoordinator(policyApplier: FakeActivationPolicyApplier()),
            recordingCoordinator: coordinator
        )
        let window = try XCTUnwrap(NSApp.windows.first { !previousWindows.contains(ObjectIdentifier($0)) })
        var stops = 0
        coordinator.begin(mode: .currentAppWindowSwitching) { stops += 1 }
        controller.show()

        window.performClose(nil)

        XCTAssertEqual(stops, 1)
        XCTAssertNil(coordinator.activeMode)
        XCTAssertFalse(window.isVisible)
        withExtendedLifetime(controller) {}
    }

    func testHidingSettingsForPracticeStopsRecording() {
        _ = NSApplication.shared
        let coordinator = ShortcutRecordingCoordinator()
        let controller = SettingsWindowController(
            activationCoordinator: SettingsActivationPolicyCoordinator(policyApplier: FakeActivationPolicyApplier()),
            recordingCoordinator: coordinator
        )
        var stops = 0
        coordinator.begin(mode: .applicationSwitching) { stops += 1 }

        controller.hideForPractice()
        controller.hideForPractice()

        XCTAssertEqual(stops, 1)
        XCTAssertNil(coordinator.activeMode)
    }
}
