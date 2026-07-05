import ApplicationServices
import CoreGraphics

public struct PermissionService: Sendable {
    public init() {}

    public func currentState() -> PermissionState {
        PermissionState(
            accessibility: currentAccessibilityState(),
            screenRecording: currentScreenRecordingState()
        )
    }

    public func currentState(accessibility: PermissionGrantState) -> PermissionState {
        PermissionState(
            accessibility: accessibility,
            screenRecording: currentScreenRecordingState()
        )
    }

    public func currentAccessibilityState() -> PermissionGrantState {
        AXIsProcessTrusted() ? .granted : .missing
    }

    public func currentScreenRecordingState() -> PermissionGrantState {
        CGPreflightScreenCaptureAccess() ? .granted : .missing
    }
}
