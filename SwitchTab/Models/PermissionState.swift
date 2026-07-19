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

    public var recoveryActionHelp: String {
        "Open \(permissionName) Settings and show SwitchTab in Finder."
    }

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

public struct SettingsPermissionSummary: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let symbolName: String
    public let isReady: Bool

    public init(permissionState: PermissionState) {
        let missingCount = [
            permissionState.blocksFocusChanges,
            permissionState.blocksWindowPreviews
        ].filter { $0 }.count

        self.isReady = missingCount == 0
        self.symbolName = isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"

        switch (permissionState.blocksFocusChanges, permissionState.blocksWindowPreviews) {
        case (false, false):
            self.title = "Ready"
            self.detail = "Focus and previews enabled."
        case (true, false):
            self.title = "Needs Accessibility"
            self.detail = "Focus needs access."
        case (false, true):
            self.title = "Needs Screen Recording"
            self.detail = "Previews need access."
        case (true, true):
            self.title = "Needs 2 permissions"
            self.detail = "Focus and previews need access."
        }
    }
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
