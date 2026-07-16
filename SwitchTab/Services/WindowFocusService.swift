import AppKit
import ApplicationServices

public enum WindowFocusResult: Equatable, Sendable {
    case focused
    case unavailableTarget
    case permissionBlocked
}

public protocol WindowFocusing {
    func focus(window: WindowItem) -> Bool
}

public struct WindowFocusService {
    private let focuser: any WindowFocusing

    public init(focuser: any WindowFocusing = AXWindowFocuser()) {
        self.focuser = focuser
    }

    public func focus(
        _ window: WindowItem,
        permissionState: PermissionState
    ) -> WindowFocusResult {
        guard !permissionState.blocksFocusChanges else {
            return .permissionBlocked
        }

        guard window.canFocus else {
            return .unavailableTarget
        }

        guard focuser.focus(window: window) else {
            return .unavailableTarget
        }

        return .focused
    }
}

public final class AXWindowFocuser: WindowFocusing {
    public init() {}

    public func focus(window: WindowItem) -> Bool {
        let processIdentifier = pid_t(window.ownerProcessIdentifier)
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated else {
            return false
        }

        let didActivateBeforeRaise = activate(application)

        guard let windowElement = AXWindowElementRegistry.shared.element(for: window.windowIdentifier) else {
            return didActivateBeforeRaise
        }

        if window.isMinimized {
            AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, windowElement)
        AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)

        guard !didActivateBeforeRaise else {
            return true
        }

        return activate(application)
    }

    private func activate(_ application: NSRunningApplication) -> Bool {
        application.activate(options: .activateAllWindows)
    }
}
