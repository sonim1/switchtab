import XCTest
@testable import SwitchTab

@MainActor
final class AuxiliaryWindowActivationTests: XCTestCase {
    func testClosingSettingsKeepsAboutRegularUntilItsClose() {
        let applier = FakeActivationPolicyApplier()
        let coordinator = SettingsActivationPolicyCoordinator(policyApplier: applier)
        coordinator.settingsWindowWillShow()
        coordinator.aboutWindowWillShow()

        coordinator.settingsWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular])
        coordinator.aboutWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular, .accessory])
    }

    func testClosingAboutKeepsSettingsRegularUntilItsClose() {
        let applier = FakeActivationPolicyApplier()
        let coordinator = SettingsActivationPolicyCoordinator(policyApplier: applier)
        coordinator.aboutWindowWillShow()
        coordinator.settingsWindowWillShow()

        coordinator.aboutWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular])
        coordinator.settingsWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular, .accessory])
    }

    func testRepeatedShowsAndClosesDoNotApplyDuplicatePolicies() {
        let applier = FakeActivationPolicyApplier()
        let coordinator = SettingsActivationPolicyCoordinator(policyApplier: applier)
        coordinator.settingsWindowDidClose()
        coordinator.aboutWindowDidClose()
        XCTAssertTrue(applier.appliedPolicies.isEmpty)

        coordinator.settingsWindowWillShow()
        coordinator.settingsWindowWillShow()
        coordinator.aboutWindowWillShow()
        coordinator.settingsWindowDidClose()
        coordinator.settingsWindowDidClose()
        coordinator.aboutWindowDidClose()
        coordinator.aboutWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular, .accessory])

        coordinator.aboutWindowWillShow()
        coordinator.aboutWindowDidClose()
        XCTAssertEqual(applier.appliedPolicies, [.regular, .accessory, .regular, .accessory])
    }
}
