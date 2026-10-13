// The Settings Allow action still opens the real recovery destination; do not use it to change TCC.
import AppKit
import SwiftUI
import SwitchTab

@MainActor
final class ViewStateFixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var aboutWindow: NSWindow?
    private var viewModel: ShortcutSettingsViewModel?
    private let recordingCoordinator = ShortcutRecordingCoordinator()
    private var permissionState = PermissionState(accessibility: .missing, screenRecording: .missing)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let fixture = NSMenuItem(title: "Fixture", action: nil, keyEquivalent: "")
        let actions = NSMenu(title: "Fixture")
        for (title, action) in [
            ("Both Permissions Missing", #selector(bothMissing)),
            ("Accessibility Off", #selector(accessibilityOff)),
            ("Previews Off", #selector(previewsOff)),
            ("Both Permissions Granted", #selector(bothGranted)),
            ("About", #selector(showAbout)),
            ("Light Appearance", #selector(light)),
            ("Dark Appearance", #selector(dark))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            actions.addItem(item)
        }
        fixture.submenu = actions
        menu.addItem(fixture)
        NSApp.mainMenu = menu

        let defaults = UserDefaults(suiteName: "com.royjen.switchtab.view-audit.preferences")!
        let model = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: defaults),
            permissionStateProvider: { [weak self] in
                self?.permissionState ?? PermissionState(accessibility: .missing, screenRecording: .missing)
            }
        )
        viewModel = model
        let view = ShortcutSettingsView(
            viewModel: model,
            applicationSettingsViewModel: ApplicationSettingsViewModel(
                store: ApplicationSettingsStore(userDefaults: defaults),
                launchAtLoginService: FixtureLoginService()
            ),
            recordingCoordinator: recordingCoordinator
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        controller.view.frame = NSRect(x: 0, y: 0, width: 620, height: 500)
        controller.view.autoresizingMask = [.width, .height]
        let panel = NSWindow(
            contentRect: NSRect(x: 260, y: 200, width: 620, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "SwitchTab View Audit"
        panel.isReleasedWhenClosed = false
        panel.contentViewController = controller
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        window = panel
        NSApp.activate()
    }

    @objc private func bothMissing() {
        permissionState = PermissionState(accessibility: .missing, screenRecording: .missing)
        viewModel?.refreshPermissionState()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if notification.object as? NSWindow === window {
                recordingCoordinator.cancel()
            }
        }
    }

    @objc private func accessibilityOff() {
        permissionState = PermissionState(accessibility: .missing, screenRecording: .granted)
        viewModel?.refreshPermissionState()
    }

    @objc private func previewsOff() {
        permissionState = PermissionState(accessibility: .granted, screenRecording: .missing)
        viewModel?.refreshPermissionState()
    }

    @objc private func bothGranted() {
        permissionState = PermissionState(accessibility: .granted, screenRecording: .granted)
        viewModel?.refreshPermissionState()
    }

    @objc private func showAbout() {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let content = AboutSwitchTabContent(
            version: "Fixture", build: "QA",
            usageDashboard: UsageDashboardSnapshot(
                totalCount: 2,
                rows: [UsageDashboardRow(title: "Window Shortcut Uses", shortcutLabel: "Command + `", count: 2)]
            )
        )
        let controller = NSHostingController(rootView: AboutSwitchTabView(
            content: content,
            onContactSupport: {},
            onAcknowledgments: {}
        ))
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: AboutWindowSizingPolicy.contentSize)
        controller.view.autoresizingMask = [.width, .height]
        let panel = NSWindow(
            contentRect: controller.view.frame,
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "SwitchTab About View Audit"
        panel.isReleasedWhenClosed = false
        panel.contentViewController = controller
        panel.appearance = window?.appearance
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        aboutWindow = panel
    }

    @objc private func light() { setAppearance(.aqua) }
    @objc private func dark() { setAppearance(.darkAqua) }

    private func setAppearance(_ name: NSAppearance.Name) {
        window?.appearance = NSAppearance(named: name)
        aboutWindow?.appearance = NSAppearance(named: name)
    }
}

@MainActor
final class FixtureLoginService: LaunchAtLoginServicing {
    var startsAtLogin = false
    func setStartsAtLogin(_ enabled: Bool) throws { startsAtLogin = enabled }
}

@main
@MainActor
enum ViewStateFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ViewStateFixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
