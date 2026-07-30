import AppKit
import Foundation

public enum ApplicationActivationResult: Equatable, Sendable {
    case activated
    case unavailableTarget
}

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

private struct NSRunningApplicationActivator: ApplicationActivating {
    func activate(processIdentifier: Int) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: pid_t(processIdentifier)
        ), !application.isTerminated else {
            return false
        }

        return application.activate(options: .activateAllWindows)
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
