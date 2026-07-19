import AppKit
import Darwin
import os

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

@MainActor
protocol PermissionRecoveryRunningApplication: AnyObject {
    var processIdentifier: pid_t { get }
    var isActive: Bool { get }
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
}

extension NSRunningApplication: PermissionRecoveryRunningApplication {}

@MainActor
protocol PermissionRecoveryActivationWaiter: AnyObject {
    @discardableResult
    func waitUntilActive(
        _ application: any PermissionRecoveryRunningApplication
    ) async throws -> Bool
    func cancel()
}

@MainActor
enum PermissionRecoveryApplicationOpenResult {
    case opened(any PermissionRecoveryRunningApplication)
    case failed
}

struct PermissionRecoveryResult: Equatable, Sendable {
    let didOpenSettings: Bool
    let finderProcessIdentifier: pid_t?
    let didActivateFinder: Bool
}

enum PermissionRecoveryEvent: Equatable, Sendable {
    case openCompleted(processIdentifier: pid_t?, didOpenSettings: Bool)
    case settingsBecameActive(processIdentifier: pid_t, alreadyActive: Bool)
    case finderOpenCompleted(
        processIdentifier: pid_t?,
        bundleIdentifierMatches: Bool,
        canonicalURLMatches: Bool,
        didOpenFinder: Bool
    )
    case finderBecameActive(
        processIdentifier: pid_t,
        alreadyActiveOrBuffered: Bool
    )
}

@MainActor
protocol PermissionRecoveryEventSink: AnyObject {
    func record(_ event: PermissionRecoveryEvent)
}

@MainActor
protocol PermissionRecoveryWorkspace: AnyObject {
    func makeActivationWaiter() -> any PermissionRecoveryActivationWaiter
    func openSettings(
        _ url: URL
    ) async throws -> PermissionRecoveryApplicationOpenResult
    func openFinder() async throws -> PermissionRecoveryApplicationOpenResult
    func activateFileViewerSelecting(_ fileURLs: [URL])
}

private struct PermissionRecoveryUncheckedNotification: @unchecked Sendable {
    let value: Notification
}

private final class PermissionRecoveryMainActorCallback: @unchecked Sendable {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func call() {
        MainActor.assumeIsolated {
            action()
        }
    }
}

private final class PermissionRecoveryObserverRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private let onRemoved: PermissionRecoveryMainActorCallback
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter,
        onRemoved: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.onRemoved = PermissionRecoveryMainActorCallback(onRemoved)
    }

    func install(_ observer: NSObjectProtocol) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    func remove() {
        lock.lock()
        let observer = observer
        self.observer = nil
        lock.unlock()

        guard let observer else {
            return
        }

        notificationCenter.removeObserver(observer)
        onRemoved.call()
    }

    deinit {
        remove()
    }
}

@MainActor
final class WorkspacePermissionRecoveryActivationWaiter:
    PermissionRecoveryActivationWaiter
{
    private enum TerminalState {
        case succeeded(alreadyActiveOrBuffered: Bool)
        case cancelled
    }

    private let observerRegistration: PermissionRecoveryObserverRegistration
    private var activatedProcessIdentifiers: Set<pid_t> = []
    private var targetProcessIdentifier: pid_t?
    private var continuation: CheckedContinuation<Bool, Error>?
    private var terminalState: TerminalState?

    init(
        notificationCenter: NotificationCenter,
        onObserverRemoved: @escaping @MainActor () -> Void = {}
    ) {
        observerRegistration = PermissionRecoveryObserverRegistration(
            notificationCenter: notificationCenter,
            onRemoved: onObserverRemoved
        )
        let observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notification = PermissionRecoveryUncheckedNotification(
                value: notification
            )
            MainActor.assumeIsolated {
                self?.receive(notification.value)
            }
        }
        observerRegistration.install(observer)
    }

    func waitUntilActive(
        _ application: any PermissionRecoveryRunningApplication
    ) async throws -> Bool {
        try Task.checkCancellation()

        let processIdentifier = application.processIdentifier
        targetProcessIdentifier = processIdentifier

        if application.isActive
            || activatedProcessIdentifiers.contains(processIdentifier)
        {
            finish(.succeeded(alreadyActiveOrBuffered: true))
            return true
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                switch terminalState {
                case .succeeded(let alreadyActiveOrBuffered):
                    continuation.resume(returning: alreadyActiveOrBuffered)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case nil:
                    if application.isActive
                        || activatedProcessIdentifiers.contains(processIdentifier)
                    {
                        self.continuation = continuation
                        finish(.succeeded(alreadyActiveOrBuffered: true))
                    } else {
                        self.continuation = continuation
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    private func receive(_ notification: Notification) {
        guard terminalState == nil,
              let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
              ] as? any PermissionRecoveryRunningApplication
        else {
            return
        }

        let processIdentifier = application.processIdentifier
        if processIdentifier == targetProcessIdentifier {
            finish(.succeeded(alreadyActiveOrBuffered: false))
        } else {
            activatedProcessIdentifiers.insert(processIdentifier)
        }
    }

    private func finish(_ state: TerminalState) {
        guard terminalState == nil else {
            return
        }

        terminalState = state
        removeObserver()

        let continuation = continuation
        self.continuation = nil
        switch state {
        case .succeeded(let alreadyActiveOrBuffered):
            continuation?.resume(returning: alreadyActiveOrBuffered)
        case .cancelled:
            continuation?.resume(throwing: CancellationError())
        }
    }

    private func removeObserver() {
        observerRegistration.remove()
    }

    deinit {
        continuation?.resume(throwing: CancellationError())
    }
}

@MainActor
final class PermissionRecoveryApplicationOpenBridge {
    typealias Completion = @MainActor (PermissionRecoveryApplicationOpenResult) -> Void

    private var continuation:
        CheckedContinuation<PermissionRecoveryApplicationOpenResult, Error>?
    private var isTerminal = false

    func wait(
        _ start: (@escaping Completion) -> Void
    ) async throws -> PermissionRecoveryApplicationOpenResult {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !isTerminal else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation
                start { [weak self] result in
                    self?.complete(with: result)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func complete(with result: PermissionRecoveryApplicationOpenResult) {
        finish(returning: result)
    }

    func cancel() {
        finish(throwing: CancellationError())
    }

    private func finish(returning result: PermissionRecoveryApplicationOpenResult) {
        guard !isTerminal else {
            return
        }

        isTerminal = true
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func finish(throwing error: Error) {
        guard !isTerminal else {
            return
        }

        isTerminal = true
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }

    deinit {
        continuation?.resume(throwing: CancellationError())
    }
}

private struct PermissionRecoveryAppKitOpenCompletion: @unchecked Sendable {
    let application: NSRunningApplication?
    let error: Error?
}

@MainActor
private final class DefaultPermissionRecoveryEventSink: PermissionRecoveryEventSink {
#if DEBUG
    private let logger = Logger(
        subsystem: "com.royjen.switchtab",
        category: "PermissionRecovery"
    )
#endif

    func record(_ event: PermissionRecoveryEvent) {
#if DEBUG
        switch event {
        case .openCompleted(let processIdentifier, let didOpenSettings):
            let publicProcessIdentifier = Int(processIdentifier ?? -1)
            logger.debug(
                "openCompleted pid=\(publicProcessIdentifier, privacy: .public) didOpenSettings=\(didOpenSettings, privacy: .public)"
            )
        case .settingsBecameActive(let processIdentifier, let alreadyActive):
            let publicProcessIdentifier = Int(processIdentifier)
            logger.debug(
                "settingsBecameActive pid=\(publicProcessIdentifier, privacy: .public) alreadyActive=\(alreadyActive, privacy: .public)"
            )
        case .finderOpenCompleted(
            let processIdentifier,
            let bundleIdentifierMatches,
            let canonicalURLMatches,
            let didOpenFinder
        ):
            let publicProcessIdentifier = Int(processIdentifier ?? -1)
            logger.debug(
                "finderOpenCompleted pid=\(publicProcessIdentifier, privacy: .public) bundleIdentifierMatches=\(bundleIdentifierMatches, privacy: .public) canonicalURLMatches=\(canonicalURLMatches, privacy: .public) didOpenFinder=\(didOpenFinder, privacy: .public)"
            )
        case .finderBecameActive(let processIdentifier, let alreadyActiveOrBuffered):
            let publicProcessIdentifier = Int(processIdentifier)
            logger.debug(
                "finderBecameActive pid=\(publicProcessIdentifier, privacy: .public) alreadyActiveOrBuffered=\(alreadyActiveOrBuffered, privacy: .public)"
            )
        }
#endif
    }
}

private let permissionRecoveryFinderURL = URL(
    fileURLWithPath: "/System/Library/CoreServices/Finder.app"
)
private let permissionRecoveryFinderBundleIdentifier = "com.apple.finder"

private func permissionRecoveryDarwinCanonicalPath(for url: URL) -> String? {
    url.path.withCString { path in
        guard let canonicalPath = realpath(path, nil) else {
            return nil
        }
        defer {
            free(canonicalPath)
        }
        return String(cString: canonicalPath)
    }
}

@MainActor
private func permissionRecoveryFinderIdentity(
    _ application: any PermissionRecoveryRunningApplication
) -> (bundleIdentifierMatches: Bool, canonicalURLMatches: Bool) {
    let bundleIdentifierMatches =
        application.bundleIdentifier == permissionRecoveryFinderBundleIdentifier
    guard let applicationURL = application.bundleURL,
          let applicationPath = permissionRecoveryDarwinCanonicalPath(
              for: applicationURL
          ),
          let finderPath = permissionRecoveryDarwinCanonicalPath(
              for: permissionRecoveryFinderURL
          )
    else {
        return (bundleIdentifierMatches, false)
    }

    return (bundleIdentifierMatches, applicationPath == finderPath)
}

extension NSWorkspace: PermissionRecoveryWorkspace {
    func makeActivationWaiter() -> any PermissionRecoveryActivationWaiter {
        WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: NSWorkspace.shared.notificationCenter
        )
    }

    func openSettings(
        _ url: URL
    ) async throws -> PermissionRecoveryApplicationOpenResult {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bridge = PermissionRecoveryApplicationOpenBridge()

        return try await bridge.wait { completion in
            openApplication(at: url, configuration: configuration) {
                application, error in
                let callback = PermissionRecoveryAppKitOpenCompletion(
                    application: application,
                    error: error
                )
                Task { @MainActor in
                    if callback.error == nil,
                       let application = callback.application
                    {
                        completion(.opened(application))
                    } else {
                        completion(.failed)
                    }
                }
            }
        }
    }

    func openFinder() async throws -> PermissionRecoveryApplicationOpenResult {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bridge = PermissionRecoveryApplicationOpenBridge()

        return try await bridge.wait { completion in
            openApplication(
                at: permissionRecoveryFinderURL,
                configuration: configuration
            ) { application, error in
                let callback = PermissionRecoveryAppKitOpenCompletion(
                    application: application,
                    error: error
                )
                Task { @MainActor in
                    if callback.error == nil,
                       let application = callback.application
                    {
                        completion(.opened(application))
                    } else {
                        completion(.failed)
                    }
                }
            }
        }
    }
}

@MainActor
struct PermissionRecoveryCoordinator {
    private let workspace: any PermissionRecoveryWorkspace
    private let applicationURL: @MainActor () -> URL
    private let eventSink: any PermissionRecoveryEventSink

    init(
        workspace: any PermissionRecoveryWorkspace = NSWorkspace.shared,
        applicationURL: @escaping @MainActor () -> URL = { Bundle.main.bundleURL }
    ) {
        self.init(
            workspace: workspace,
            applicationURL: applicationURL,
            eventSink: DefaultPermissionRecoveryEventSink()
        )
    }

    init(
        workspace: any PermissionRecoveryWorkspace,
        applicationURL: @escaping @MainActor () -> URL,
        eventSink: any PermissionRecoveryEventSink
    ) {
        self.workspace = workspace
        self.applicationURL = applicationURL
        self.eventSink = eventSink
    }

    @discardableResult
    func recover(
        _ destination: PermissionSettingsDestination
    ) async throws -> PermissionRecoveryResult {
        let appURL = applicationURL()
        let waiter = workspace.makeActivationWaiter()
        defer {
            waiter.cancel()
        }

        let openResult = try await workspace.openSettings(
            destination.systemSettingsURL
        )
        try Task.checkCancellation()

        let didOpenSettings: Bool
        switch openResult {
        case .opened(let application):
            didOpenSettings = true
            let processIdentifier = application.processIdentifier
            eventSink.record(
                .openCompleted(
                    processIdentifier: processIdentifier,
                    didOpenSettings: true
                )
            )
            let alreadyActive = application.isActive
            _ = try await waiter.waitUntilActive(application)
            try Task.checkCancellation()
            eventSink.record(
                .settingsBecameActive(
                    processIdentifier: processIdentifier,
                    alreadyActive: alreadyActive
                )
            )
        case .failed:
            didOpenSettings = false
            eventSink.record(
                .openCompleted(
                    processIdentifier: nil,
                    didOpenSettings: false
                )
            )
            waiter.cancel()
            try Task.checkCancellation()
        }

        try Task.checkCancellation()
        workspace.activateFileViewerSelecting([appURL])
        let finderWaiter = workspace.makeActivationWaiter()
        defer {
            finderWaiter.cancel()
        }

        let finderOpenResult = try await workspace.openFinder()
        try Task.checkCancellation()

        switch finderOpenResult {
        case .failed:
            eventSink.record(
                .finderOpenCompleted(
                    processIdentifier: nil,
                    bundleIdentifierMatches: false,
                    canonicalURLMatches: false,
                    didOpenFinder: false
                )
            )
            finderWaiter.cancel()
            return PermissionRecoveryResult(
                didOpenSettings: didOpenSettings,
                finderProcessIdentifier: nil,
                didActivateFinder: false
            )
        case .opened(let finderApplication):
            let identity = permissionRecoveryFinderIdentity(finderApplication)
            let didOpenFinder =
                identity.bundleIdentifierMatches && identity.canonicalURLMatches
            eventSink.record(
                .finderOpenCompleted(
                    processIdentifier: finderApplication.processIdentifier,
                    bundleIdentifierMatches: identity.bundleIdentifierMatches,
                    canonicalURLMatches: identity.canonicalURLMatches,
                    didOpenFinder: didOpenFinder
                )
            )

            guard didOpenFinder else {
                finderWaiter.cancel()
                return PermissionRecoveryResult(
                    didOpenSettings: didOpenSettings,
                    finderProcessIdentifier: nil,
                    didActivateFinder: false
                )
            }

            let alreadyActiveOrBuffered = try await finderWaiter.waitUntilActive(
                finderApplication
            )
            try Task.checkCancellation()
            eventSink.record(
                .finderBecameActive(
                    processIdentifier: finderApplication.processIdentifier,
                    alreadyActiveOrBuffered: alreadyActiveOrBuffered
                )
            )

            return PermissionRecoveryResult(
                didOpenSettings: didOpenSettings,
                finderProcessIdentifier: finderApplication.processIdentifier,
                didActivateFinder: true
            )
        }
    }
}
