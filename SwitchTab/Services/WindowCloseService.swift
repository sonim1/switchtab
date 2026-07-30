import AppKit
import ApplicationServices

public enum WindowCloseResult: Equatable, Sendable {
    case requestAccepted
    case unavailableTarget
    case permissionBlocked
}

@MainActor
public protocol WindowCloseObservation: AnyObject {
    func cancel()
}

@MainActor
public protocol WindowCloseDriving: AnyObject {
    func observeDestruction(
        of window: WindowItem,
        onDestroyed: @escaping @MainActor () -> Void
    ) -> (any WindowCloseObservation)?

    func pressCloseButton(of window: WindowItem) -> Bool
}

/// Requests the target app's native close action, but only reports the window
/// as gone after Accessibility confirms that its UI element was destroyed.
@MainActor
public final class WindowCloseService {
    private struct PendingObservation {
        let token: UUID
        let observation: any WindowCloseObservation
    }

    private let driver: any WindowCloseDriving
    private var pendingObservations: [String: PendingObservation] = [:]

    public init() {
        self.driver = AXWindowCloseDriver()
    }

    public init(driver: any WindowCloseDriving) {
        self.driver = driver
    }

    public func close(
        _ window: WindowItem,
        permissionState: PermissionState,
        onDestroyed: @escaping @MainActor () -> Void
    ) -> WindowCloseResult {
        guard !permissionState.blocksFocusChanges else {
            cancelObservation(for: window.id)
            return .permissionBlocked
        }

        // A retry after cancelling an app-owned save prompt gets a fresh
        // one-shot callback while still pressing the same native close button.
        cancelObservation(for: window.id)
        let token = UUID()
        guard let observation = driver.observeDestruction(
            of: window,
            onDestroyed: { [weak self] in
                self?.completeClose(for: window.id, token: token, onDestroyed: onDestroyed)
            }
        ) else {
            return .unavailableTarget
        }

        pendingObservations[window.id] = PendingObservation(
            token: token,
            observation: observation
        )
        guard driver.pressCloseButton(of: window) else {
            cancelObservation(for: window.id, matching: token)
            return .unavailableTarget
        }

        // AXPress success means the request was accepted. The target app may
        // still be presenting a save confirmation, so callers must not remove
        // the tile until `onDestroyed` runs.
        return .requestAccepted
    }

    public func cancelAll() {
        let observations = pendingObservations.values.map(\.observation)
        pendingObservations.removeAll()
        observations.forEach { $0.cancel() }
    }

    private func completeClose(
        for id: String,
        token: UUID,
        onDestroyed: @escaping @MainActor () -> Void
    ) {
        guard let pending = pendingObservations[id], pending.token == token else {
            return
        }

        pendingObservations.removeValue(forKey: id)
        pending.observation.cancel()
        onDestroyed()
    }

    private func cancelObservation(for id: String, matching token: UUID? = nil) {
        guard let pending = pendingObservations[id],
              token == nil || pending.token == token else {
            return
        }

        pendingObservations.removeValue(forKey: id)
        pending.observation.cancel()
    }
}

/// Registers for destruction before pressing the close control, preventing a
/// fast-closing window from disappearing between those operations.
@MainActor
public final class AXWindowCloseDriver: WindowCloseDriving {
    public init() {}

    public func observeDestruction(
        of window: WindowItem,
        onDestroyed: @escaping @MainActor () -> Void
    ) -> (any WindowCloseObservation)? {
        guard let windowElement = AXWindowElementRegistry.shared.element(for: window.windowIdentifier) else {
            return nil
        }

        let context = AXWindowDestructionContext(onDestroyed: onDestroyed)
        var observer: AXObserver?
        guard AXObserverCreate(
            pid_t(window.ownerProcessIdentifier),
            axWindowDestroyedCallback,
            &observer
        ) == .success,
            let observer else {
            return nil
        }

        let refcon = Unmanaged.passUnretained(context).toOpaque()
        guard AXObserverAddNotification(
            observer,
            windowElement,
            kAXUIElementDestroyedNotification as CFString,
            refcon
        ) == .success else {
            return nil
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return AXWindowDestructionObservation(
            observer: observer,
            source: source,
            windowElement: windowElement,
            context: context
        )
    }

    public func pressCloseButton(of window: WindowItem) -> Bool {
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

private let axWindowDestroyedCallback: AXObserverCallback = { _, _, notification, refcon in
    guard notification as String == kAXUIElementDestroyedNotification as String,
          let refcon else {
        return
    }

    Unmanaged<AXWindowDestructionContext>
        .fromOpaque(refcon)
        .takeUnretainedValue()
        .deliver()
}

private final class AXWindowDestructionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var isActive = true
    private let onDestroyed: @MainActor () -> Void

    init(onDestroyed: @escaping @MainActor () -> Void) {
        self.onDestroyed = onDestroyed
    }

    func deliver() {
        lock.lock()
        let shouldDeliver = isActive
        isActive = false
        lock.unlock()
        guard shouldDeliver else {
            return
        }

        Task { @MainActor [onDestroyed] in
            onDestroyed()
        }
    }

    func cancel() {
        lock.lock()
        isActive = false
        lock.unlock()
    }
}

@MainActor
private final class AXWindowDestructionObservation: WindowCloseObservation {
    private let observer: AXObserver
    private let source: CFRunLoopSource
    private let windowElement: AXUIElement
    private let context: AXWindowDestructionContext
    private var isCancelled = false

    init(
        observer: AXObserver,
        source: CFRunLoopSource,
        windowElement: AXUIElement,
        context: AXWindowDestructionContext
    ) {
        self.observer = observer
        self.source = source
        self.windowElement = windowElement
        self.context = context
    }

    func cancel() {
        guard !isCancelled else {
            return
        }

        isCancelled = true
        context.cancel()
        AXObserverRemoveNotification(
            observer,
            windowElement,
            kAXUIElementDestroyedNotification as CFString
        )
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
