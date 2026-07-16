import SwitchTab

enum PermissionRecoveryCopyTests {
    static func run() throws {
        try testPermissionStatusItemsNamePermissionCapabilityAndSettingsStep()
        try testPermissionStatusItemDetailCombinesBlockedCapabilityAndSettingsStep()
        try testPermissionStatusItemsIncludeGrantedAndMissingPermissions()
        try testPermissionStatusItemsMapToSystemSettingsDestinations()
        try testPermissionStatusItemsExposeAllowActionTitle()
    }

    static func testPermissionStatusItemsNamePermissionCapabilityAndSettingsStep() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        for item in state.permissionStatusItems {
            try expectFalse(item.permissionName.isEmpty)
            try expectFalse(item.detailText.isEmpty)
            try expectTrue(item.detailText.contains("System Settings"))
        }
    }

    static func testPermissionStatusItemDetailCombinesBlockedCapabilityAndSettingsStep() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .granted)
        guard let item = state.permissionStatusItems.first else {
            throw TestFailure.failed("Expected permission status item")
        }

        try expectTrue(item.detailText.contains("Window observation and focus changes are blocked."))
        try expectTrue(item.detailText.contains("System Settings"))
    }

    static func testPermissionStatusItemsIncludeGrantedAndMissingPermissions() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .granted)

        try expectEqual(state.permissionStatusItems.map(\.permissionName), ["Accessibility", "Screen Recording"])
        try expectFalse(state.permissionStatusItems[0].isGranted)
        try expectTrue(state.permissionStatusItems[0].detailText.contains("System Settings"))
        try expectTrue(state.permissionStatusItems[1].isGranted)
        try expectTrue(state.permissionStatusItems[1].detailText.contains("enabled"))
    }

    static func testPermissionStatusItemsMapToSystemSettingsDestinations() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        let destinations = state.permissionStatusItems.map(\.settingsDestination)

        try expectEqual(destinations, [.accessibility, .screenRecording])
        try expectEqual(
            PermissionSettingsDestination.accessibility.systemSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        try expectEqual(
            PermissionSettingsDestination.screenRecording.systemSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    static func testPermissionStatusItemsExposeAllowActionTitle() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        try expectEqual(state.permissionStatusItems.map(\.recoveryActionTitle), ["Allow", "Allow"])
    }
}
