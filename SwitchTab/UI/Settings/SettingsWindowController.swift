import AppKit
import SwiftUI

public extension Notification.Name {
    static let showSettingsWindow = Notification.Name("SwitchTab.showSettingsWindow")
    static let showSwitchingGuide = Notification.Name("SwitchTab.showSwitchingGuide")
}

public enum ApplicationActivationPolicy: Equatable, Sendable {
    case accessory
    case regular
}

public enum SettingsWindowSizingPolicy {
    public static let contentSize = NSSize(width: 620, height: 500)
}

@MainActor
enum FloatingPanelFactory {
    static let windowLevel: NSWindow.Level = .normal

    static func hostingController<Content: View>(
        rootView: Content,
        contentSize: NSSize
    ) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: contentSize)
        controller.view.autoresizingMask = [.width, .height]
        return controller
    }

    static func panel(
        title: String,
        contentSize: NSSize,
        contentViewController: NSViewController
    ) -> NSPanel {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = windowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    static func show(_ window: NSWindow) {
        WindowPlacementPolicy.centerWindowIfNeeded(window, screenFrame: NSScreen.main?.visibleFrame)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
    }
}

@MainActor
public protocol ApplicationActivationPolicyApplying {
    func apply(_ policy: ApplicationActivationPolicy)
}

@MainActor
public final class AuxiliaryWindowActivationPolicyCoordinator {
    private enum Owner: Hashable {
        case settings
        case about
    }

    private let policyApplier: any ApplicationActivationPolicyApplying
    private var visibleOwners: Set<Owner> = []

    public init(policyApplier: any ApplicationActivationPolicyApplying) {
        self.policyApplier = policyApplier
    }

    public func settingsWindowWillShow() {
        willShow(.settings)
    }

    public func settingsWindowDidClose() {
        didClose(.settings)
    }

    public func aboutWindowWillShow() {
        willShow(.about)
    }

    public func aboutWindowDidClose() {
        didClose(.about)
    }

    private func willShow(_ owner: Owner) {
        let wasEmpty = visibleOwners.isEmpty
        guard visibleOwners.insert(owner).inserted else { return }
        if wasEmpty {
            policyApplier.apply(.regular)
        }
    }

    private func didClose(_ owner: Owner) {
        guard visibleOwners.remove(owner) != nil else { return }
        if visibleOwners.isEmpty {
            policyApplier.apply(.accessory)
        }
    }
}

public typealias SettingsActivationPolicyCoordinator = AuxiliaryWindowActivationPolicyCoordinator

@MainActor
public final class NSApplicationActivationPolicyApplier: ApplicationActivationPolicyApplying {
    public init() {}

    public func apply(_ policy: ApplicationActivationPolicy) {
        NSApp.setActivationPolicy(policy.nsApplicationPolicy)
    }
}

@MainActor
public final class SettingsWindowController {
    private let window: NSPanel
    private let activationCoordinator: AuxiliaryWindowActivationPolicyCoordinator
    private let recordingCoordinator: ShortcutRecordingCoordinator
    private let windowDelegate: WindowCloseDelegate

    public init(
        activationCoordinator: AuxiliaryWindowActivationPolicyCoordinator,
        recordingCoordinator: ShortcutRecordingCoordinator? = nil,
        updateChecker: (any UpdateChecking)? = nil,
        onShortcutChanged: @escaping (
            SwitcherShortcutConfiguration,
            SwitcherShortcutConfiguration
        ) -> ShortcutChangeResult = { _, _ in .applied },
        onEnabledChanged: @escaping (SwitcherShortcutConfiguration) -> Void = { _ in },
        practiceModel: SwitchingPracticeModel? = nil,
        onBeginPractice: @escaping () -> Void = {},
        showsGuide: Bool = false
    ) {
        let recordingCoordinator = recordingCoordinator ?? ShortcutRecordingCoordinator()
        let hostingController = FloatingPanelFactory.hostingController(
            rootView: ShortcutSettingsView(
                viewModel: ShortcutSettingsViewModel(
                    onShortcutChanged: onShortcutChanged,
                    onEnabledChanged: onEnabledChanged
                ),
                applicationSettingsViewModel: ApplicationSettingsViewModel(updateChecker: updateChecker),
                practiceModel: practiceModel,
                recordingCoordinator: recordingCoordinator,
                onBeginPractice: onBeginPractice,
                showsGuide: showsGuide
            ),
            contentSize: SettingsWindowSizingPolicy.contentSize
        )
        let window = FloatingPanelFactory.panel(
            title: "SwitchTab Settings",
            contentSize: SettingsWindowSizingPolicy.contentSize,
            contentViewController: hostingController
        )
        let windowDelegate = WindowCloseDelegate {
            recordingCoordinator.cancel()
            activationCoordinator.settingsWindowDidClose()
        }
        window.delegate = windowDelegate

        self.window = window
        self.activationCoordinator = activationCoordinator
        self.recordingCoordinator = recordingCoordinator
        self.windowDelegate = windowDelegate
    }

    public func show() {
        activationCoordinator.settingsWindowWillShow()
        FloatingPanelFactory.show(window)
    }

    public func hideForPractice() {
        recordingCoordinator.cancel()
        window.orderOut(nil)
        activationCoordinator.settingsWindowDidClose()
    }
}

private extension ApplicationActivationPolicy {
    var nsApplicationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .accessory:
            .accessory
        case .regular:
            .regular
        }
    }
}

final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ _: Notification) {
        MainActor.assumeIsolated {
            onClose()
        }
    }
}
