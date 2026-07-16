import SwitchTab

enum SettingsActivationPolicyTests {
    @MainActor
    static func run() throws {
        try testSettingsWindowShowMakesApplicationRegular()
        try testSettingsWindowCloseRestoresApplicationAccessoryPolicy()
        try testSettingsWindowUsesVisibleContentSize()
    }

    @MainActor
    static func testSettingsWindowShowMakesApplicationRegular() throws {
        let applier = FakeActivationPolicyApplier()
        let coordinator = SettingsActivationPolicyCoordinator(policyApplier: applier)

        coordinator.settingsWindowWillShow()

        try expectEqual(applier.appliedPolicies, [.regular])
    }

    @MainActor
    static func testSettingsWindowCloseRestoresApplicationAccessoryPolicy() throws {
        let applier = FakeActivationPolicyApplier()
        let coordinator = SettingsActivationPolicyCoordinator(policyApplier: applier)

        coordinator.settingsWindowDidClose()

        try expectEqual(applier.appliedPolicies, [.accessory])
    }

    static func testSettingsWindowUsesVisibleContentSize() throws {
        try expectEqual(SettingsWindowSizingPolicy.contentSize.width, 620)
        try expectEqual(SettingsWindowSizingPolicy.contentSize.height, 500)
    }
}

@MainActor
final class FakeActivationPolicyApplier: ApplicationActivationPolicyApplying {
    private(set) var appliedPolicies: [ApplicationActivationPolicy] = []

    func apply(_ policy: ApplicationActivationPolicy) {
        appliedPolicies.append(policy)
    }
}
