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

public protocol WindowFocusServicing {
    func focus(_ window: WindowItem, permissionState: PermissionState) -> WindowFocusResult
}

public protocol WindowSelectionRecencyRecording: AnyObject {
    func recordSelection(id: String)
    func flush()
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

extension WindowFocusService: WindowFocusServicing {}

extension SwitcherRecencyStore: WindowSelectionRecencyRecording {}

public struct WindowSelectionCoordinator {
    private let focusService: any WindowFocusServicing
    private let recencyStore: any WindowSelectionRecencyRecording

    public init(
        focusService: any WindowFocusServicing,
        recencyStore: any WindowSelectionRecencyRecording
    ) {
        self.focusService = focusService
        self.recencyStore = recencyStore
    }

    @discardableResult
    public func confirm(
        _ window: WindowItem,
        permissionState: PermissionState
    ) -> WindowFocusResult {
        let result = focusService.focus(window, permissionState: permissionState)
        guard result == .focused else {
            return result
        }

        recencyStore.recordSelection(id: window.id)
        recencyStore.flush()
        return result
    }
}

public enum AXWindowFocusResultPolicy {
    public static func didFocus(
        didActivateApplication: Bool,
        didSetFocusedWindow: Bool,
        didSetMainWindow: Bool,
        didRaiseWindow: Bool
    ) -> Bool {
        guard didActivateApplication else {
            return false
        }

        return didSetFocusedWindow || (didSetMainWindow && didRaiseWindow)
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
            return false
        }

        if window.isMinimized {
            guard AXUIElementSetAttributeValue(
                windowElement,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            ) == .success else {
                return false
            }
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        let didSetFocusedWindow = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            windowElement
        ) == .success
        let didSetMainWindow = AXUIElementSetAttributeValue(
            windowElement,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        ) == .success
        let didRaiseWindow = AXUIElementPerformAction(
            windowElement,
            kAXRaiseAction as CFString
        ) == .success
        let didActivateApplication = didActivateBeforeRaise || activate(application)

        return AXWindowFocusResultPolicy.didFocus(
            didActivateApplication: didActivateApplication,
            didSetFocusedWindow: didSetFocusedWindow,
            didSetMainWindow: didSetMainWindow,
            didRaiseWindow: didRaiseWindow
        )
    }

    private func activate(_ application: NSRunningApplication) -> Bool {
        application.activate(options: .activateAllWindows)
    }
}
