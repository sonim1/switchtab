import Foundation

public enum PermissionSettingsDestination: Equatable, Sendable {
    private static let accessibilitySystemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    private static let screenRecordingSystemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    case accessibility
    case screenRecording

    public var systemSettingsURL: URL {
        switch self {
        case .accessibility:
            Self.accessibilitySystemSettingsURL
        case .screenRecording:
            Self.screenRecordingSystemSettingsURL
        }
    }
}
