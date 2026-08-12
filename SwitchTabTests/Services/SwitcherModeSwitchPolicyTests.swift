import CoreGraphics
@testable import SwitchTab
import XCTest

final class SwitcherModeSwitchPolicyTests: XCTestCase {
    private let applicationKeyCode: UInt16 = 48
    private let windowKeyCode: UInt16 = 50

    func testAlternateKeyCodeSwitchesModes() {
        XCTAssertEqual(
            SwitcherOverlayModeSwitchPolicy.command(
                keyCode: windowKeyCode,
                modifiers: [.command],
                alternateModeKeyCode: windowKeyCode
            ),
            .switchMode(reverse: false)
        )
    }

    func testShiftChoosesTheReverseDirection() {
        XCTAssertEqual(
            SwitcherOverlayModeSwitchPolicy.command(
                keyCode: applicationKeyCode,
                modifiers: [.command, .shift],
                alternateModeKeyCode: applicationKeyCode
            ),
            .switchMode(reverse: true)
        )
    }

    func testHeldModifiersDoNotHaveToMatchTheAlternateShortcut() {
        // The window shortcut may be the Option-Control fallback while Command
        // is the modifier actually being held.
        XCTAssertEqual(
            SwitcherOverlayModeSwitchPolicy.command(
                keyCode: windowKeyCode,
                modifiers: [.command],
                alternateModeKeyCode: windowKeyCode
            ),
            .switchMode(reverse: false)
        )
    }

    func testUnavailableAlternateModeProducesNoCommand() {
        XCTAssertNil(
            SwitcherOverlayModeSwitchPolicy.command(
                keyCode: applicationKeyCode,
                modifiers: [.command],
                alternateModeKeyCode: nil
            )
        )
    }

    func testOtherKeysProduceNoCommand() {
        XCTAssertNil(
            SwitcherOverlayModeSwitchPolicy.command(
                keyCode: 49,
                modifiers: [.command],
                alternateModeKeyCode: windowKeyCode
            )
        )
    }

    func testEventTapConsumesTheModeSwitchKey() {
        XCTAssertEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: windowKeyCode,
                isAutorepeat: false,
                modifiers: [.command],
                triggerReleaseModifiers: [.command],
                triggerShortcut: .defaultApplicationSwitching,
                alternateModeKeyCode: windowKeyCode
            ),
            .consume(.switchMode(reverse: false))
        )
    }

    func testEventTapKeepsCommandTabNativeWhileApplicationSwitchingIsUnavailable() {
        XCTAssertEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: applicationKeyCode,
                isAutorepeat: false,
                modifiers: [.command],
                triggerReleaseModifiers: [.command],
                triggerShortcut: .defaultCurrentAppWindowSwitching,
                alternateModeKeyCode: nil
            ),
            .passThrough
        )
    }

    func testActiveTriggerOutranksTheAlternateKey() {
        // A shared key code keeps its in-mode meaning: advance, never switch.
        XCTAssertEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: applicationKeyCode,
                isAutorepeat: false,
                modifiers: [.command],
                triggerReleaseModifiers: [.command],
                triggerShortcut: .defaultApplicationSwitching,
                alternateModeKeyCode: applicationKeyCode
            ),
            .consume(.moveDown)
        )
    }

    func testStateReportsTheSwitchWithoutTouchingTheSession() {
        var state = SwitcherOverlayState()
        state.present(
            mode: .applicationSwitching,
            items: [
                SwitcherListItem(id: "a", title: "A", subtitle: nil),
                SwitcherListItem(id: "b", title: "B", subtitle: nil)
            ],
            selectedIndex: 1
        )

        XCTAssertEqual(state.handle(.switchMode(reverse: true)), .modeSwitchRequested(reverse: true))
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.session?.selectedIndex, 1)
        XCTAssertEqual(state.session?.mode, .applicationSwitching)
    }

    func testSwitchingWithoutASessionIsIgnored() {
        var state = SwitcherOverlayState()

        XCTAssertEqual(state.handle(.switchMode(reverse: false)), .none)
        XCTAssertFalse(state.isPresented)
    }

    func testModeSwitchIsNotTreatedAsADestructiveRepeat() {
        XCTAssertFalse(SwitcherCommand.switchMode(reverse: false).repeatsAreDestructive)
        XCTAssertTrue(SwitcherCommand.switchMode(reverse: false).isModeSwitch)
        XCTAssertFalse(SwitcherCommand.moveDown.isModeSwitch)
    }
}
