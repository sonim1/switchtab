import AppKit
import ApplicationServices

public enum WindowCloseResult: Equatable, Sendable {
    case closed
    case unavailableTarget
    case permissionBlocked
}

public protocol WindowClosing {
    func close(window: WindowItem) -> Bool
}

public protocol WindowCloseServicing {
    func close(_ window: WindowItem, permissionState: PermissionState) -> WindowCloseResult
}

public struct WindowCloseService {
    private let closer: any WindowClosing

    public init(closer: any WindowClosing = AXWindowCloser()) {
        self.closer = closer
    }

    public func close(
        _ window: WindowItem,
        permissionState: PermissionState
    ) -> WindowCloseResult {
        // Closing drives the same Accessibility control path as focusing, so it
        // is blocked by the same missing permission.
        guard !permissionState.blocksFocusChanges else {
            return .permissionBlocked
        }

        guard closer.close(window: window) else {
            return .unavailableTarget
        }

        return .closed
    }
}

extension WindowCloseService: WindowCloseServicing {}

/// Presses the window's Accessibility close button, which is what the window's
/// own red traffic-light button does — the app keeps its save/confirm behaviour.
public final class AXWindowCloser: WindowClosing {
    public init() {}

    public func close(window: WindowItem) -> Bool {
        guard let windowElement = AXWindowElementRegistry.shared.element(for: window.windowIdentifier) else {
            return false
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowElement,
            kAXCloseButtonAttribute as CFString,
            &value
        ) == .success,
            let closeButtonValue = value,
            CFGetTypeID(closeButtonValue) == AXUIElementGetTypeID() else {
            return false
        }

        let closeButton = unsafeDowncast(closeButtonValue as AnyObject, to: AXUIElement.self)
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }
}
