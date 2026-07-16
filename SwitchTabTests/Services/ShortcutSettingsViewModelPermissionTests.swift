import Combine
import Foundation
import SwitchTab

enum ShortcutSettingsViewModelPermissionTests {
    static func run() throws {
        try testViewModelRefreshesPermissionState()
        try testViewModelDoesNotPublishUnchangedPermissionState()
        try testPermissionSummaryReportsReadyWhenAllPermissionsGranted()
        try testPermissionSummaryCountsMissingPermissions()
    }

    static func testViewModelRefreshesPermissionState() throws {
        var state = PermissionState(accessibility: .missing, screenRecording: .granted)
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: makeDefaults()),
            permissionStateProvider: { state }
        )

        try expectEqual(viewModel.permissionState, state)

        state = PermissionState(accessibility: .granted, screenRecording: .missing)
        viewModel.refreshPermissionState()

        try expectEqual(viewModel.permissionState, state)
    }

    static func testViewModelDoesNotPublishUnchangedPermissionState() throws {
        let state = PermissionState(accessibility: .granted, screenRecording: .granted)
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: makeDefaults()),
            permissionStateProvider: { state }
        )
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
        }

        viewModel.refreshPermissionState()

        try expectEqual(viewModel.permissionState, state)
        try expectEqual(publishCount, 0)
    }

    static func testPermissionSummaryReportsReadyWhenAllPermissionsGranted() throws {
        let summary = SettingsPermissionSummary(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(summary.title, "Ready")
        try expectEqual(summary.detail, "Focus and previews enabled.")
        try expectEqual(summary.symbolName, "checkmark.circle.fill")
        try expectEqual(summary.isReady, true)
    }

    static func testPermissionSummaryCountsMissingPermissions() throws {
        let summary = SettingsPermissionSummary(
            permissionState: PermissionState(accessibility: .missing, screenRecording: .missing)
        )

        try expectEqual(summary.title, "Needs 2 permissions")
        try expectEqual(summary.detail, "Focus and previews need access.")
        try expectEqual(summary.symbolName, "exclamationmark.triangle.fill")
        try expectEqual(summary.isReady, false)
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
