public enum PermissionGrantState: Equatable, Sendable {
    case granted
    case missing

    public var blocksCapability: Bool {
        self != .granted
    }
}

public struct PermissionStatusItem: Equatable, Sendable {
    public let permissionName: String
    public let isGranted: Bool
    public let detailText: String
    public let recoveryActionTitle: String
    public let settingsDestination: PermissionSettingsDestination

    public init(
        permissionName: String,
        settingsDestination: PermissionSettingsDestination,
        grantState: PermissionGrantState,
        blockedCapability: String,
        settingsStep: String,
        recoveryActionTitle: String = "Allow"
    ) {
        self.permissionName = permissionName
        self.settingsDestination = settingsDestination
        self.recoveryActionTitle = recoveryActionTitle
        let isGranted = grantState == .granted
        self.isGranted = isGranted
        if isGranted {
            self.detailText = "\(permissionName) enabled."
        } else {
            self.detailText = "\(blockedCapability)\n\(settingsStep)"
        }
    }
}

public struct PermissionState: Equatable, Sendable {
    public let accessibility: PermissionGrantState
    public let screenRecording: PermissionGrantState
    public let permissionStatusItems: [PermissionStatusItem]

    public init(accessibility: PermissionGrantState, screenRecording: PermissionGrantState) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.permissionStatusItems = Self.permissionStatusItems(
            accessibility: accessibility,
            screenRecording: screenRecording
        )
    }

    public var blocksFocusChanges: Bool {
        accessibility.blocksCapability
    }

    public var blocksWindowPreviews: Bool {
        screenRecording.blocksCapability
    }

    private static func permissionStatusItems(
        accessibility: PermissionGrantState,
        screenRecording: PermissionGrantState
    ) -> [PermissionStatusItem] {
        switch (accessibility, screenRecording) {
        case (.granted, .granted):
            grantedPermissionStatusItems
        case (.granted, .missing):
            grantedAccessibilityMissingScreenRecordingStatusItems
        case (.missing, .granted):
            missingAccessibilityGrantedScreenRecordingStatusItems
        case (.missing, .missing):
            missingPermissionStatusItems
        }
    }

    private static let accessibilityCopy = PermissionCopy(
        permissionName: "Accessibility",
        settingsDestination: .accessibility,
        blockedCapability: "Window observation and focus changes are blocked.",
        settingsStep: "Open System Settings > Privacy & Security > Accessibility and enable SwitchTab."
    )

    private static let screenRecordingCopy = PermissionCopy(
        permissionName: "Screen Recording",
        settingsDestination: .screenRecording,
        blockedCapability: "Current window previews are blocked.",
        settingsStep: "Open System Settings > Privacy & Security > Screen Recording and enable SwitchTab."
    )

    private static let grantedPermissionStatusItems = [
        accessibilityCopy.statusItem(grantState: .granted),
        screenRecordingCopy.statusItem(grantState: .granted)
    ]
    private static let grantedAccessibilityMissingScreenRecordingStatusItems = [
        accessibilityCopy.statusItem(grantState: .granted),
        screenRecordingCopy.statusItem(grantState: .missing)
    ]
    private static let missingAccessibilityGrantedScreenRecordingStatusItems = [
        accessibilityCopy.statusItem(grantState: .missing),
        screenRecordingCopy.statusItem(grantState: .granted)
    ]
    private static let missingPermissionStatusItems = [
        accessibilityCopy.statusItem(grantState: .missing),
        screenRecordingCopy.statusItem(grantState: .missing)
    ]
}

private struct PermissionCopy {
    let permissionName: String
    let settingsDestination: PermissionSettingsDestination
    let blockedCapability: String
    let settingsStep: String

    func statusItem(grantState: PermissionGrantState) -> PermissionStatusItem {
        PermissionStatusItem(
            permissionName: permissionName,
            settingsDestination: settingsDestination,
            grantState: grantState,
            blockedCapability: blockedCapability,
            settingsStep: settingsStep
        )
    }
}
