import AppKit

public enum MenuBarMenuItemKind: Equatable {
    case settings
    case checkForUpdates
    case separator
    case about
    case quit
}

public enum MenuBarMenuModel {
    public static func items(updateCheckingAvailable: Bool) -> [MenuBarMenuItemKind] {
        if updateCheckingAvailable {
            return [.settings, .checkForUpdates, .separator, .about, .quit]
        }

        return [.settings, .separator, .about, .quit]
    }
}

public enum MenuBarUpdateAction {
    public static func postCheckForUpdatesRequest(
        notificationCenter: NotificationCenter = .default
    ) {
        UpdateRequestPoster.postCheckForUpdatesRequest(notificationCenter: notificationCenter)
    }
}

@MainActor
public final class MenuBarStatusItemController: NSObject {
    private let store: ApplicationSettingsStore
    private let updateChecker: any UpdateChecking
    private var statusItem: NSStatusItem?
    private var settingsObserver: NSObjectProtocol?

    public init(
        store: ApplicationSettingsStore = ApplicationSettingsStore(),
        updateChecker: (any UpdateChecking)? = nil
    ) {
        self.store = store
        self.updateChecker = updateChecker ?? UnavailableUpdateController()
        super.init()
        refreshVisibility()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshVisibility()
            }
        }
    }

    public func invalidate() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        setVisible(false)
    }

    public func refreshVisibility() {
        setVisible(store.menuBarIconVisible)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            installStatusItemIfNeeded()
            return
        }

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "SwitchTab"
        }
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for item in MenuBarMenuModel.items(updateCheckingAvailable: updateChecker.isUpdateCheckingAvailable) {
            switch item {
            case .settings:
                menu.addItem(menuItem(title: "Settings", action: #selector(showSettings)))
            case .checkForUpdates:
                menu.addItem(menuItem(title: "Check for Updates...", action: #selector(checkForUpdates)))
            case .separator:
                menu.addItem(.separator())
            case .about:
                menu.addItem(menuItem(title: "About SwitchTab", action: #selector(showAbout)))
            case .quit:
                menu.addItem(menuItem(title: "Quit", action: #selector(quit)))
            }
        }
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showSettings() {
        NotificationCenter.default.post(name: .showSettingsWindow, object: nil)
    }

    @objc private func showAbout() {
        NotificationCenter.default.post(name: .showAboutWindow, object: nil)
    }

    @objc private func checkForUpdates() {
        MenuBarUpdateAction.postCheckForUpdatesRequest()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
