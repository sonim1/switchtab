import AppKit

public enum ApplicationActivationResult: Equatable, Sendable {
    case activated
    case unavailableTarget
}

public protocol ApplicationActivating {
    func activate(processIdentifier: Int) -> Bool
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
