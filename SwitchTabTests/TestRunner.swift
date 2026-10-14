import XCTest

final class SwitchTabTests: XCTestCase {
    @MainActor
    func testCoreModels() throws {
        try CoreModelsTests.run()
    }

    @MainActor
    func testApplicationSwitching() throws {
        try ApplicationSwitchingTests.run()
    }

    @MainActor
    func testSwitcherItem() throws {
        try SwitcherItemTests.run()
    }

    @MainActor
    func testPermissionService() throws {
        try PermissionServiceTests.run()
    }

    @MainActor
    func testShortcutValidation() throws {
        try ShortcutValidationTests.run()
    }

    @MainActor
    func testSwitcherOverlayState() throws {
        try SwitcherOverlayStateTests.run()
    }

    @MainActor
    func testSwitcherOverlayPresentationModel() throws {
        try SwitcherOverlayPresentationModelTests.run()
    }

    @MainActor
    func testSwitcherOverlayPresentation() throws {
        try SwitcherOverlayPresentationTests.run()
    }

    @MainActor
    func testSwitcherOverlayConfirmation() throws {
        try SwitcherOverlayConfirmationTests.run()
    }

    @MainActor
    func testAccessibilityWindowProvider() throws {
        try AccessibilityWindowProviderTests.run()
    }

    @MainActor
    func testWindowThumbnail() async throws {
        try await WindowThumbnailTests.run()
    }

    @MainActor
    func testWindowFocusService() throws {
        try WindowFocusServiceTests.run()
    }

    @MainActor
    func testWindowCloseService() throws {
        try WindowCloseServiceTests.run()
    }

    @MainActor
    func testSwitchTabSession() throws {
        try SwitchTabSessionTests.run()
    }

    @MainActor
    func testWindowEdgeCase() throws {
        try WindowEdgeCaseTests.run()
    }

    @MainActor
    func testShortcutCapture() throws {
        try ShortcutCaptureTests.run()
    }

    @MainActor
    func testShortcutSettingsStore() throws {
        try ShortcutSettingsStoreTests.run()
    }

    @MainActor
    func testSwitcherRecencyStore() throws {
        try SwitcherRecencyStoreTests.run()
    }

    @MainActor
    func testSwitcherPresentationSnapshot() throws {
        try SwitcherPresentationSnapshotTests.run()
    }

    @MainActor
    func testApplicationIconStore() throws {
        try ApplicationIconStoreTests.run()
    }

    @MainActor
    func testApplicationSettingsStore() throws {
        try ApplicationSettingsStoreTests.run()
    }

    @MainActor
    func testUsageMetricsStore() throws {
        try UsageMetricsStoreTests.run()
    }

    @MainActor
    func testAboutSwitchTabContent() throws {
        try AboutSwitchTabContentTests.run()
    }

    @MainActor
    func testMenuBarIconAsset() throws {
        try MenuBarIconAssetTests.run()
    }

    @MainActor
    func testAppStoreDistributionSettings() throws {
        try AppStoreDistributionSettingsTests.run()
    }

    @MainActor
    func testUpdateDiagnostic() throws {
        try UpdateDiagnosticTests.run()
    }

    @MainActor
    func testUpdateController() throws {
        try UpdateControllerTests.run()
    }

    @MainActor
    func testSwitcherOverlayPresentationPolicy() throws {
        try SwitcherOverlayPresentationPolicyTests.run()
    }

    @MainActor
    func testShortcutSettingsViewModelPermission() throws {
        try ShortcutSettingsViewModelPermissionTests.run()
    }

    @MainActor
    func testHotkeyService() throws {
        try HotkeyServiceTests.run()
    }

    @MainActor
    func testSettingsActivationPolicy() throws {
        try SettingsActivationPolicyTests.run()
    }

    @MainActor
    func testSwitcherPerformance() throws {
        try SwitcherPerformanceTests.run()
    }

    @MainActor
    func testPermissionRecoveryCopy() throws {
        try PermissionRecoveryCopyTests.run()
    }
}
