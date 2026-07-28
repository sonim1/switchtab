import XCTest

final class SwitchTabTests: XCTestCase {
    @MainActor
    func testAllSuites() async throws {
        try CoreModelsTests.run()
        try SwitcherItemTests.run()
        try PermissionServiceTests.run()
        try ShortcutValidationTests.run()
        try SwitcherOverlayStateTests.run()
        try SwitcherOverlayPresentationModelTests.run()
        try SwitcherOverlayPresentationTests.run()
        try SwitcherOverlayConfirmationTests.run()
        try AccessibilityWindowProviderTests.run()
        try await WindowThumbnailTests.run()
        try WindowFocusServiceTests.run()
        try WindowCloseServiceTests.run()
        try SwitchTabSessionTests.run()
        try WindowEdgeCaseTests.run()
        try ShortcutCaptureTests.run()
        try ShortcutSettingsStoreTests.run()
        try SwitcherRecencyStoreTests.run()
        try SwitcherPresentationSnapshotTests.run()
        try ApplicationIconStoreTests.run()
        try ApplicationSettingsStoreTests.run()
        try UsageMetricsStoreTests.run()
        try AboutSwitchTabContentTests.run()
        try MenuBarIconAssetTests.run()
        try AppStoreDistributionSettingsTests.run()
        try UpdateControllerTests.run()
        try SwitcherOverlayPresentationPolicyTests.run()
        try ShortcutSettingsViewModelPermissionTests.run()
        try HotkeyServiceTests.run()
        try SettingsActivationPolicyTests.run()
        try SwitcherPerformanceTests.run()
        try PermissionRecoveryCopyTests.run()
    }
}
