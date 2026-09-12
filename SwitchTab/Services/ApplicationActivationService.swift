import AppKit
import ApplicationServices
import Foundation

struct ApplicationForegroundWindow {
    let identifier: UInt32
    let processIdentifier: Int
    let layer: Int
    let bounds: CGRect
    let alpha: Double
}

enum ApplicationForegroundCorrectionPolicy {
    static func isOccluded(
        windowIdentifier: UInt32,
        processIdentifier: Int,
        windows: [ApplicationForegroundWindow]
    ) -> Bool {
        guard let frontWindow = windows.first(where: {
            $0.layer == 0 && $0.alpha > 0 && !$0.bounds.isEmpty
        }), frontWindow.processIdentifier != processIdentifier,
        let index = windows.firstIndex(where: {
            $0.identifier == windowIdentifier && $0.processIdentifier == processIdentifier
        }), windows[index].layer == 0, windows[index].alpha > 0,
        !windows[index].bounds.isEmpty else { return false }

        return windows[..<index].contains {
            $0.processIdentifier != processIdentifier && $0.layer == 0 && $0.alpha > 0
                && !$0.bounds.intersection(windows[index].bounds).isEmpty
        }
    }
}

@MainActor
protocol ApplicationForegroundCorrecting {
    func focusedWindowIdentifier(processIdentifier: Int) -> UInt32?
    func inputEventCounts() -> [UInt32]
    func raiseIfOccluded(processIdentifier: Int, windowIdentifier: UInt32)
}

@MainActor
final class ApplicationForegroundCorrectionCoordinator {
    private let corrector: any ApplicationForegroundCorrecting
    private var pendingTask: Task<Void, Never>?
    private var pendingProcessIdentifier: Int?

    convenience init() {
        self.init(corrector: AXApplicationForegroundCorrector())
    }

    init(corrector: any ApplicationForegroundCorrecting) {
        self.corrector = corrector
    }

    func schedule(processIdentifier: Int) {
        cancel()
        guard let windowIdentifier = corrector.focusedWindowIdentifier(
            processIdentifier: processIdentifier
        ) else { return }
        let inputCounts = corrector.inputEventCounts()
        pendingProcessIdentifier = processIdentifier
        pendingTask = Task { @MainActor [weak self] in
            // Activation stays immediate; only the window-order observation waits for it to settle.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingTask = nil
            self.pendingProcessIdentifier = nil
            guard self.corrector.inputEventCounts() == inputCounts else { return }
            self.corrector.raiseIfOccluded(
                processIdentifier: processIdentifier, windowIdentifier: windowIdentifier
            )
        }
    }

    func applicationDidActivate(processIdentifier: Int) {
        if pendingProcessIdentifier != processIdentifier { cancel() }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingProcessIdentifier = nil
    }
}

@MainActor
struct AXApplicationForegroundCorrector: ApplicationForegroundCorrecting {
    private let windowNumberResolver = PrivateAXWindowNumberResolver()

    func inputEventCounts() -> [UInt32] {
        // Poll counts instead of installing another global event monitor. Release of the
        // confirming shortcut is intentionally excluded; any new input invalidates the check.
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].map {
            CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
        }
    }

    func focusedWindowIdentifier(processIdentifier: Int) -> UInt32? {
        guard let window = focusedWindow(processIdentifier: processIdentifier) else { return nil }
        return windowNumberResolver.windowNumber(for: window)
    }

    func raiseIfOccluded(processIdentifier: Int, windowIdentifier: UInt32) {
        let inputCounts = inputEventCounts()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(processIdentifier),
              let window = focusedWindow(processIdentifier: processIdentifier),
              windowNumberResolver.windowNumber(for: window) == windowIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return }

        let windows = windowInfo.compactMap { info -> ApplicationForegroundWindow? in
            guard let identifier = info[kCGWindowNumber as String] as? NSNumber,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rectangle = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return ApplicationForegroundWindow(
                identifier: identifier.uint32Value, processIdentifier: owner.intValue,
                layer: layer.intValue, bounds: rectangle, alpha: alpha.doubleValue
            )
        }
        guard ApplicationForegroundCorrectionPolicy.isOccluded(
            windowIdentifier: windowIdentifier, processIdentifier: processIdentifier, windows: windows
        ), let currentWindow = focusedWindow(processIdentifier: processIdentifier),
        CFEqual(currentWindow, window),
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(processIdentifier),
        inputEventCounts() == inputCounts else { return }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private func focusedWindow(processIdentifier: Int) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid_t(processIdentifier))
        AXUIElementSetMessagingTimeout(application, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeDowncast(value, to: AXUIElement.self)
        guard AXUIElementSetMessagingTimeout(window, 0.05) == .success else { return nil }
        var minimized: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
              let isMinimized = minimized as? Bool, !isMinimized else { return nil }
        return window
    }
}

public enum ApplicationActivationResult: Equatable, Sendable {
    case activated
    case unavailableTarget
}

@MainActor
public protocol ApplicationActivating {
    func activate(processIdentifier: Int) -> Bool
}

public enum ApplicationTerminationResult: Equatable, Sendable {
    case requestAccepted
    case unavailableTarget
}

public protocol ApplicationTerminating: AnyObject {
    func terminate(processIdentifier: Int) -> Bool
}

public struct ApplicationTerminationService {
    private let terminator: any ApplicationTerminating

    public init() {
        self.terminator = NSRunningApplicationTerminator()
    }

    public init(terminator: any ApplicationTerminating) {
        self.terminator = terminator
    }

    public func terminate(_ application: ApplicationItem) -> ApplicationTerminationResult {
        terminator.terminate(processIdentifier: application.processIdentifier)
            ? .requestAccepted
            : .unavailableTarget
    }
}

@MainActor
public protocol ApplicationActivationServicing {
    func activate(_ application: ApplicationItem) -> ApplicationActivationResult
}

public protocol ApplicationSelectionRecencyRecording: AnyObject {
    func recordSelection(id: String)
    func flush()
}

public struct ApplicationActivationService: ApplicationActivationServicing {
    private let activator: any ApplicationActivating

    public init() {
        self.activator = NSRunningApplicationActivator()
    }

    public init(activator: any ApplicationActivating) {
        self.activator = activator
    }

    @MainActor
    public func activate(_ application: ApplicationItem) -> ApplicationActivationResult {
        activator.activate(processIdentifier: application.processIdentifier)
            ? .activated
            : .unavailableTarget
    }
}

public struct ApplicationSelectionCoordinator {
    private let activationService: any ApplicationActivationServicing
    private let recencyStore: any ApplicationSelectionRecencyRecording

    public init(
        activationService: any ApplicationActivationServicing,
        recencyStore: any ApplicationSelectionRecencyRecording
    ) {
        self.activationService = activationService
        self.recencyStore = recencyStore
    }

    @discardableResult
    @MainActor
    public func confirm(_ application: ApplicationItem) -> ApplicationActivationResult {
        let result = activationService.activate(application)
        guard result == .activated else {
            return result
        }

        recencyStore.recordSelection(id: application.id)
        recencyStore.flush()
        return result
    }
}

extension SwitcherRecencyStore: ApplicationSelectionRecencyRecording {}

public struct WorkspaceActivationRecencyObserver {
    private let recencyStore: any ApplicationSelectionRecencyRecording
    private let ownBundleIdentifier: String?

    public init(
        recencyStore: any ApplicationSelectionRecencyRecording,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.recencyStore = recencyStore
        self.ownBundleIdentifier = RunningApplicationProvider.normalizedBundleIdentifier(
            ownBundleIdentifier
        )
    }

    public func recordActivation(_ snapshot: RunningApplicationSnapshot) {
        guard snapshot.isRegular, !snapshot.isTerminated else {
            return
        }

        let bundleIdentifier = RunningApplicationProvider.normalizedBundleIdentifier(
            snapshot.bundleIdentifier
        )
        if let ownBundleIdentifier,
           bundleIdentifier == ownBundleIdentifier {
            return
        }

        let id = RunningApplicationProvider.stableApplicationIdentifier(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: snapshot.processIdentifier
        )
        recencyStore.recordSelection(id: id)
        recencyStore.flush()
    }
}

public enum WorkspaceApplicationTerminationPolicy {
    public static func applicationIdentifier(
        for snapshot: RunningApplicationSnapshot
    ) -> String? {
        guard snapshot.isRegular, snapshot.isTerminated else {
            return nil
        }

        return RunningApplicationProvider.stableApplicationIdentifier(
            bundleIdentifier: snapshot.bundleIdentifier,
            processIdentifier: snapshot.processIdentifier
        )
    }
}

protocol ApplicationActivationTarget: AnyObject {
    var isTerminated: Bool { get }
    @MainActor
    func activateAllWindows(from processIdentifier: Int?) -> Bool
}

protocol ApplicationActivationTargetProviding {
    @MainActor
    func target(processIdentifier: Int) -> (any ApplicationActivationTarget)?
    @MainActor
    func frontmostApplicationProcessIdentifier() -> Int?
}

struct NSRunningApplicationActivationTargetProvider: ApplicationActivationTargetProviding {
    func target(processIdentifier: Int) -> (any ApplicationActivationTarget)? {
        guard let application = NSRunningApplication(
            processIdentifier: pid_t(processIdentifier)
        ) else {
            return nil
        }

        return NSRunningApplicationActivationTarget(application: application)
    }

    func frontmostApplicationProcessIdentifier() -> Int? {
        NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) }
    }
}

final class NSRunningApplicationActivationTarget: ApplicationActivationTarget {
    private let application: NSRunningApplication

    init(application: NSRunningApplication) {
        self.application = application
    }

    var isTerminated: Bool {
        application.isTerminated
    }

    func activateAllWindows(from processIdentifier: Int?) -> Bool {
        if let processIdentifier,
           processIdentifier != Int(application.processIdentifier),
           let frontmostApplication = NSRunningApplication(
               processIdentifier: pid_t(processIdentifier)
           ) {
            return application.activate(
                from: frontmostApplication,
                options: .activateAllWindows
            )
        }

        return application.activate(options: .activateAllWindows)
    }
}

struct NSRunningApplicationActivator: ApplicationActivating {
    let targetProvider: any ApplicationActivationTargetProviding

    init(
        targetProvider: any ApplicationActivationTargetProviding =
            NSRunningApplicationActivationTargetProvider()
    ) {
        self.targetProvider = targetProvider
    }

    func activate(processIdentifier: Int) -> Bool {
        guard let target = targetProvider.target(processIdentifier: processIdentifier),
              !target.isTerminated else {
            return false
        }

        return target.activateAllWindows(
            from: targetProvider.frontmostApplicationProcessIdentifier()
        )
    }
}

private final class NSRunningApplicationTerminator: ApplicationTerminating {
    func terminate(processIdentifier: Int) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: pid_t(processIdentifier)
        ), !application.isTerminated else {
            return false
        }

        return application.terminate()
    }
}
