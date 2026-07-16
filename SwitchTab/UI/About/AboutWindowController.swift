import AppKit
import SwiftUI

public extension Notification.Name {
    static let showAboutWindow = Notification.Name("SwitchTab.showAboutWindow")
}

public enum AboutWindowSizingPolicy {
    public static let contentSize = NSSize(width: 760, height: 520)
}

@MainActor
public final class AboutWindowController {
    private let window: NSPanel
    private let hostingController: NSHostingController<AboutSwitchTabView>
    private let contentProvider: () -> AboutSwitchTabContent
    private let windowDelegate: WindowCloseDelegate

    public init(contentProvider: @escaping () -> AboutSwitchTabContent) {
        self.contentProvider = contentProvider

        let initialView = AboutSwitchTabView(
            content: Self.placeholderContent,
            onContactSupport: Self.openSupportEmail,
            onAcknowledgments: Self.showAcknowledgments
        )
        let hostingController = FloatingPanelFactory.hostingController(
            rootView: initialView,
            contentSize: AboutWindowSizingPolicy.contentSize
        )
        let window = FloatingPanelFactory.panel(
            title: "About SwitchTab",
            contentSize: AboutWindowSizingPolicy.contentSize,
            contentViewController: hostingController
        )

        let windowDelegate = WindowCloseDelegate {
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = windowDelegate

        self.window = window
        self.hostingController = hostingController
        self.windowDelegate = windowDelegate
    }

    public func show() {
        hostingController.rootView = AboutSwitchTabView(
            content: contentProvider(),
            onContactSupport: Self.openSupportEmail,
            onAcknowledgments: Self.showAcknowledgments
        )
        NSApp.setActivationPolicy(.regular)
        FloatingPanelFactory.show(window)
    }

    private static func openSupportEmail() {
        NSWorkspace.shared.open(Self.supportEmailURL)
    }

    private static func showAcknowledgments() {
        let alert = NSAlert()
        alert.messageText = "Acknowledgments"
        alert.informativeText = "SwitchTab is built with SwiftUI, AppKit, ApplicationServices, and ScreenCaptureKit."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static let placeholderContent = AboutSwitchTabContent(
        version: "",
        build: "",
        usageDashboard: .empty
    )
    private static let supportEmailURL = URL(string: "mailto:support@switchtab.app?subject=SwitchTab%20Support")!
}
