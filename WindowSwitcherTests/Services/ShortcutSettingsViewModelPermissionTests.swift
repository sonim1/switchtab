import Combine
import Foundation
import WindowSwitcher

enum ShortcutSettingsViewModelPermissionTests {
    static func run() throws {
        try testViewModelRefreshesPermissionState()
        try testViewModelDoesNotPublishUnchangedPermissionState()
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

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "WindowSwitcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
