import Combine
import Foundation

@MainActor
public final class ApplicationSettingsViewModel: ObservableObject {
    @Published public private(set) var startsAtLogin: Bool
    @Published public private(set) var menuBarIconVisible: Bool
    @Published public private(set) var replacesCommandTab: Bool
    @Published public private(set) var overlaySizeScale: OverlaySizeScale
    @Published public private(set) var updateCheckingAvailable: Bool
    @Published public private(set) var currentVersionDisplay: String
    @Published public private(set) var automaticallyChecksForUpdates: Bool
    @Published public private(set) var errorMessage: String?

    private let store: ApplicationSettingsStore
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let updateChecker: any UpdateChecking

    public init(
        store: ApplicationSettingsStore = ApplicationSettingsStore(),
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        updateChecker: (any UpdateChecking)? = nil
    ) {
        let resolvedLaunchAtLoginService = launchAtLoginService ?? LaunchAtLoginService()
        let resolvedUpdateChecker = updateChecker ?? UnavailableUpdateController()

        self.store = store
        self.launchAtLoginService = resolvedLaunchAtLoginService
        self.updateChecker = resolvedUpdateChecker
        self.startsAtLogin = resolvedLaunchAtLoginService.startsAtLogin
        self.menuBarIconVisible = store.menuBarIconVisible
        self.replacesCommandTab = store.replacesCommandTab
        self.overlaySizeScale = store.overlaySizeScale
        self.updateCheckingAvailable = resolvedUpdateChecker.isUpdateCheckingAvailable
        self.currentVersionDisplay = resolvedUpdateChecker.currentVersionDisplay
        self.automaticallyChecksForUpdates = resolvedUpdateChecker.automaticallyChecksForUpdates
    }

    public func setStartsAtLogin(_ startsAtLogin: Bool) {
        guard self.startsAtLogin != startsAtLogin else {
            setErrorMessage(nil)
            return
        }

        do {
            try launchAtLoginService.setStartsAtLogin(startsAtLogin)
            self.startsAtLogin = launchAtLoginService.startsAtLogin
            setErrorMessage(nil)
        } catch {
            self.startsAtLogin = launchAtLoginService.startsAtLogin
            setErrorMessage("Start at login could not be updated.")
        }
    }

    public func setMenuBarIconVisible(_ visible: Bool) {
        guard menuBarIconVisible != visible else {
            return
        }

        store.saveMenuBarIconVisible(visible)
        menuBarIconVisible = visible
    }

    public func setReplacesCommandTab(_ enabled: Bool) {
        guard replacesCommandTab != enabled else {
            return
        }

        store.saveReplacesCommandTab(enabled)
        replacesCommandTab = enabled
    }

    public func setOverlaySizeScale(_ scale: OverlaySizeScale) {
        guard overlaySizeScale != scale else {
            return
        }

        store.saveOverlaySizeScale(scale)
        overlaySizeScale = scale
    }

    public func checkForUpdates() {
        guard updateCheckingAvailable else {
            return
        }

        updateChecker.checkForUpdates()
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard updateCheckingAvailable else {
            automaticallyChecksForUpdates = false
            return
        }

        updateChecker.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updateChecker.automaticallyChecksForUpdates
    }

    private func setErrorMessage(_ message: String?) {
        guard errorMessage != message else {
            return
        }

        errorMessage = message
    }
}
