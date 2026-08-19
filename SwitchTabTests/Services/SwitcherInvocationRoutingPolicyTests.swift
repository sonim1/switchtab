@testable import SwitchTab
import XCTest

final class SwitcherInvocationRoutingPolicyTests: XCTestCase {
    func testRoutesOppositeActiveModeToHeldSessionSwitch() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .applicationSwitching,
                requestedMode: .currentAppWindowSwitching
            ),
            .switchMode
        )
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .currentAppWindowSwitching,
                requestedMode: .applicationSwitching
            ),
            .switchMode
        )
    }

    func testRoutesSameActiveModeToAdvance() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .applicationSwitching,
                requestedMode: .applicationSwitching
            ),
            .advance
        )
    }

    func testRoutesMissingOverlayToFreshPresentation() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: nil,
                requestedMode: .currentAppWindowSwitching
            ),
            .present
        )
    }
}
