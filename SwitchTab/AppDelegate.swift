import AppKit

enum AppDelegateShortcutConflictPolicy {
    static func enabledApplicationShortcuts(
        in configurations: [SwitcherShortcutConfiguration]
    ) -> [ShortcutSetting] {
        guard let applicationConfiguration = configurations.first(where: {
            $0.mode == .applicationSwitching
        }), applicationConfiguration.isEnabled else {
            return []
        }

        let forward = applicationConfiguration.shortcut
        return [forward, forward.reverseVariant(id: "\(forward.id)-reverse")]
    }

    static func windowRegistrationExistingShortcuts(
        windowSetting: ShortcutSetting,
        configurations: [SwitcherShortcutConfiguration]
    ) -> (forward: [ShortcutSetting], reverse: [ShortcutSetting]) {
        let applicationShortcuts = enabledApplicationShortcuts(in: configurations)
        return (applicationShortcuts, [windowSetting] + applicationShortcuts)
    }
}

struct ApplicationShortcutLifecycleTransaction {
    let previousWindowSnapshot: HotkeyRegistrationSnapshot
    let suspendWindow: () -> Void
    let registerApplicationCandidate: () -> Bool
    let registerWindowWithCandidateConflicts: () -> Bool
    let restorePreviousApplication: () -> Bool
    let restorePreviousWindow: (HotkeyRegistrationSnapshot) -> Bool
    let deferredRestoration: (() -> Void)?

    init(
        previousWindowSnapshot: HotkeyRegistrationSnapshot,
        suspendWindow: @escaping () -> Void,
        registerApplicationCandidate: @escaping () -> Bool,
        registerWindowWithCandidateConflicts: @escaping () -> Bool,
        restorePreviousApplication: @escaping () -> Bool,
        restorePreviousWindow: @escaping (HotkeyRegistrationSnapshot) -> Bool,
        deferredRestoration: (() -> Void)? = nil
    ) {
        self.previousWindowSnapshot = previousWindowSnapshot
        self.suspendWindow = suspendWindow
        self.registerApplicationCandidate = registerApplicationCandidate
        self.registerWindowWithCandidateConflicts = registerWindowWithCandidateConflicts
        self.restorePreviousApplication = restorePreviousApplication
        self.restorePreviousWindow = restorePreviousWindow
        self.deferredRestoration = deferredRestoration
    }

    func apply() -> ShortcutChangeResult {
        suspendWindow()
        guard registerApplicationCandidate() else {
            return restorePreviousRegistrations()
        }
        guard registerWindowWithCandidateConflicts() else {
            return restorePreviousRegistrations()
        }

        return .applied
    }

    private func restorePreviousRegistrations() -> ShortcutChangeResult {
        if let deferredRestoration {
            deferredRestoration()
            return .rejectedRestorationDeferred
        }

        let didRestoreApplication = restorePreviousApplication()
        let didRestoreWindow = restorePreviousWindow(previousWindowSnapshot)
        return didRestoreApplication && didRestoreWindow
            ? .rejectedPreviousRestored
            : .rollbackFailed
    }
}

@MainActor
struct ShortcutEnabledLifecycle {
    let windowHotkeyService: HotkeyService
    let registerWindowHotkeys: @MainActor (ShortcutSetting) -> Bool
    let updateApplicationHotkeyRegistration: @MainActor (
        SwitcherShortcutConfiguration
    ) -> Bool
    let dismissWindowOverlayIfActive: @MainActor () -> Void
    let persistRegistrationMessages: @MainActor () -> Void

    func apply(configuration: SwitcherShortcutConfiguration) {
        switch configuration.mode {
        case .currentAppWindowSwitching:
            if configuration.isEnabled {
                _ = registerWindowHotkeys(configuration.shortcut)
            } else {
                windowHotkeyService.unregisterAll()
                dismissWindowOverlayIfActive()
            }
        case .applicationSwitching:
            _ = updateApplicationHotkeyRegistration(configuration)
        }

        persistRegistrationMessages()
    }
}

@MainActor
final class ShortcutRecordingHotkeyLifecycle {
    let windowHotkeyService: HotkeyService
    let applicationHotkeyController: ApplicationSwitchingHotkeyController
    let registerWindowHotkeys: @MainActor (
        ShortcutSetting,
        [SwitcherShortcutConfiguration]
    ) -> Bool
    let updateApplicationHotkeyRegistration: @MainActor (
        SwitcherShortcutConfiguration
    ) -> Bool
    let dismissWindowOverlayIfActive: @MainActor () -> Void
    let persistRegistrationMessages: @MainActor () -> Void
    private(set) var isRecording = false

    init(
        windowHotkeyService: HotkeyService,
        applicationHotkeyController: ApplicationSwitchingHotkeyController,
        registerWindowHotkeys: @escaping @MainActor (
            ShortcutSetting,
            [SwitcherShortcutConfiguration]
        ) -> Bool,
        updateApplicationHotkeyRegistration: @escaping @MainActor (
            SwitcherShortcutConfiguration
        ) -> Bool,
        dismissWindowOverlayIfActive: @escaping @MainActor () -> Void,
        persistRegistrationMessages: @escaping @MainActor () -> Void
    ) {
        self.windowHotkeyService = windowHotkeyService
        self.applicationHotkeyController = applicationHotkeyController
        self.registerWindowHotkeys = registerWindowHotkeys
        self.updateApplicationHotkeyRegistration = updateApplicationHotkeyRegistration
        self.dismissWindowOverlayIfActive = dismissWindowOverlayIfActive
        self.persistRegistrationMessages = persistRegistrationMessages
    }

    func begin() {
        isRecording = true
        windowHotkeyService.unregisterAll()
        applicationHotkeyController.unregisterAll()
        persistRegistrationMessages()
    }

    func end(configurations: [SwitcherShortcutConfiguration]) {
        isRecording = false
        restore(configurations: configurations)
    }

    func applicationDidBecomeActive(configurations: [SwitcherShortcutConfiguration]) {
        guard !isRecording else {
            return
        }

        restore(configurations: configurations)
    }

    func restore(configurations: [SwitcherShortcutConfiguration]) {
        let windowConfiguration = configuration(
            for: .currentAppWindowSwitching,
            in: configurations
        )
        let applicationConfiguration = configuration(
            for: .applicationSwitching,
            in: configurations
        )

        windowHotkeyService.unregisterAll()
        if !windowConfiguration.isEnabled {
            dismissWindowOverlayIfActive()
        }

        _ = updateApplicationHotkeyRegistration(applicationConfiguration)
        if windowConfiguration.isEnabled {
            _ = registerWindowHotkeys(windowConfiguration.shortcut, configurations)
        }

        persistRegistrationMessages()
    }

    private func configuration(
        for mode: SwitcherMode,
        in configurations: [SwitcherShortcutConfiguration]
    ) -> SwitcherShortcutConfiguration {
        configurations.first { $0.mode == mode }
            ?? .defaultValue(for: mode)
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: SwitcherOverlayController?
    private let windowProvider = AccessibilityWindowProvider()
    private let applicationProvider = RunningApplicationProvider()
    private let windowFocusService = WindowFocusService()
    private let windowCloseService = WindowCloseService()
    private let applicationActivationService = ApplicationActivationService()
    private let applicationTerminationService = ApplicationTerminationService()
    private let applicationWindowCountLoader = ApplicationWindowCountLoader()
    private let permissionService = PermissionService()
    private let shortcutStore = ShortcutSettingsStore()
    private let applicationSettingsStore = ApplicationSettingsStore()
    private let updateChecker: any UpdateChecking = UpdateControllerFactory.make()
    private let recencyStore = SwitcherRecencyStore()
    private let applicationRecencyStore = SwitcherRecencyStore(mode: .applicationSwitching)
    private let usageMetricsStore = UsageMetricsStore()
    private let hotkeyService = HotkeyService()
    private let applicationHotkeyController = ApplicationSwitchingHotkeyController()
    private lazy var shortcutRecordingHotkeyLifecycle = ShortcutRecordingHotkeyLifecycle(
        windowHotkeyService: hotkeyService,
        applicationHotkeyController: applicationHotkeyController,
        registerWindowHotkeys: { [weak self] setting, configurations in
            self?.registerWindowHotkeys(
                setting: setting,
                configurations: configurations
            ) ?? false
        },
        updateApplicationHotkeyRegistration: { [weak self] configuration in
            self?.updateApplicationHotkeyRegistration(configuration: configuration) ?? false
        },
        dismissWindowOverlayIfActive: { [weak self] in
            guard self?.overlayController?.activeMode == .currentAppWindowSwitching else {
                return
            }
            self?.overlayController?.dismiss()
        },
        persistRegistrationMessages: { [weak self] in
            self?.persistRegistrationMessages()
        }
    )
    private lazy var workspaceActivationRecencyObserver = WorkspaceActivationRecencyObserver(
        recencyStore: applicationRecencyStore
    )
    private let thumbnailStore = WindowThumbnailStore()
    private var thumbnailLoader: WindowThumbnailLoader?
    private var menuBarStatusItemController: MenuBarStatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var shortcutRecordingDidBeginObserver: NSObjectProtocol?
    private var shortcutRecordingDidEndObserver: NSObjectProtocol?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
    private var workspaceApplicationActivationObserver: NSObjectProtocol?
    private var workspaceApplicationTerminationObserver: NSObjectProtocol?
    private var modeSwitchMemory = SwitcherModeSwitchMemory()
    private var settingsRequestObserver: NSObjectProtocol?
    private var aboutRequestObserver: NSObjectProtocol?
    private var updateCheckRequestObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ _: Notification) {
        NSApp.setActivationPolicy(.accessory)
        debugLog("application did finish launching")
        let overlayController = SwitcherOverlayController(thumbnailStore: thumbnailStore)
        overlayController.onDismiss = { [weak self] in
            self?.cancelThumbnailLoadingIfNeeded()
            self?.windowCloseService.cancelAll()
            // Resuming is scoped to one held-modifier session.
            self?.modeSwitchMemory.reset()
        }
        self.overlayController = overlayController
        menuBarStatusItemController = MenuBarStatusItemController(
            store: applicationSettingsStore,
            updateChecker: updateChecker
        )
        observeShortcutRecording()
        observeApplicationActivation()
        observeWorkspaceApplicationActivation()
        observeWorkspaceApplicationTermination()
        observeSettingsRequests()
        observeAboutRequests()
        observeUpdateCheckRequests()
        registerConfiguredHotkeys(shortcutStore.loadConfigurations())
        showSettingsWindowIfNeededOnLaunch()
    }

    public func applicationShouldHandleReopen(
        _: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        showSettingsWindowIfNeededOnLaunch()
        return true
    }

    public func applicationWillTerminate(_ _: Notification) {
        cancelThumbnailLoadingIfNeeded()
        menuBarStatusItemController?.invalidate()
        menuBarStatusItemController = nil
        hotkeyService.unregisterAll()
        applicationHotkeyController.unregisterAll()
        recencyStore.flush()
        applicationRecencyStore.flush()
        usageMetricsStore.flush()
        removeNotificationObservers()
    }

    public func showCurrentAppSwitcher(reverse: Bool = false) {
        debugLog("hotkey handler entered reverse=\(reverse)")
        usageMetricsStore.recordWindowShortcutUse()
        guard let overlayController else {
            debugLog("overlay controller missing")
            return
        }

        if advancePresentedOverlayIfNeeded(
            overlayController: overlayController,
            mode: .currentAppWindowSwitching,
            reverse: reverse
        ) {
            return
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            debugLog(
                "frontmost app pid=\(frontmostApplication.processIdentifier) name=\(frontmostApplication.localizedName ?? "unknown")"
            )
        } else {
            debugLog("frontmost app missing")
        }
        presentWindowSwitcher(
            target: .frontmostApplication,
            reverse: reverse,
            retainingSession: false
        )
    }

    public func showApplicationSwitcher(reverse: Bool = false) {
        guard let overlayController else {
            return
        }

        if advancePresentedOverlayIfNeeded(
            overlayController: overlayController,
            mode: .applicationSwitching,
            reverse: reverse
        ) {
            return
        }

        presentApplicationSwitcher(reverse: reverse, retainingSession: false)
    }

    /// Hands the live overlay to the other mode while the trigger modifier is
    /// still held. Nothing is committed and the previous highlight is kept so
    /// coming back resumes instead of restarting.
    private func switchOverlayMode(reverse: Bool) {
        guard let overlayController,
              let activeMode = overlayController.activeMode,
              let selectedItem = overlayController.selectedItem else {
            return
        }

        switch activeMode {
        case .applicationSwitching:
            guard hotkeyService.registeredSetting(for: .currentAppWindowSwitching) != nil,
                  let ownerProcessIdentifier = selectedItem.appIconProcessIdentifier else {
                return
            }

            modeSwitchMemory.rememberApplication(id: selectedItem.id)
            presentWindowSwitcher(
                target: .application(
                    processIdentifier: ownerProcessIdentifier,
                    name: selectedItem.title
                ),
                reverse: reverse,
                retainingSession: true
            )
        case .currentAppWindowSwitching:
            guard applicationHotkeyController.isRegistered else {
                return
            }

            if let ownerProcessIdentifier = selectedItem.appIconProcessIdentifier {
                modeSwitchMemory.rememberWindow(
                    id: selectedItem.id,
                    ownerProcessIdentifier: ownerProcessIdentifier
                )
            }
            presentApplicationSwitcher(reverse: reverse, retainingSession: true)
        }
    }

    private enum WindowSwitcherTarget: Equatable {
        case frontmostApplication
        case application(processIdentifier: Int, name: String)
    }

    @discardableResult
    private func presentWindowSwitcher(
        target: WindowSwitcherTarget,
        reverse: Bool,
        retainingSession: Bool
    ) -> Bool {
        guard let overlayController else {
            return false
        }

        cancelThumbnailLoadingIfNeeded()
        let accessibilityState = permissionService.currentAccessibilityState()
        debugLog("accessibility state=\(accessibilityState)")
        guard !accessibilityState.blocksCapability else {
            debugLog("accessibility missing; showing settings")
            // A refused mode switch leaves the held session where it is.
            guard !retainingSession else {
                return false
            }

            showSettingsWindow()
            return false
        }

        let permissionState = permissionService.currentState(accessibility: accessibilityState)
        let discoveredWindows: [WindowItem]
        switch target {
        case .frontmostApplication:
            discoveredWindows = windowProvider.currentApplicationWindows(
                includeScreenCaptureIdentifiers: !permissionState.blocksWindowPreviews
            )
        case .application(let processIdentifier, let name):
            discoveredWindows = windowProvider.applicationWindows(
                ownerProcessIdentifier: processIdentifier,
                ownerName: name,
                includeScreenCaptureIdentifiers: !permissionState.blocksWindowPreviews
            )
        }
        let recentlyOrderedWindows = recencyStore.order(discoveredWindows) { window in
            window.id
        }
        let windows = SwitcherWindowOrderPolicy.pinningFocusedWindowFirst(recentlyOrderedWindows) { window in
            window.isFocused
        }
        debugLog("window count=\(windows.count)")
        guard !windows.isEmpty else {
            debugLog("no windows; leaving overlay unchanged=\(retainingSession)")
            guard !retainingSession else {
                return false
            }

            overlayController.dismiss()
            return false
        }

        let snapshot = SwitcherPresentationSnapshot(
            elements: windows,
            reverse: reverse
        ) { window in
            window.switcherListItem
        }
        overlayController.present(
            mode: .currentAppWindowSwitching,
            items: snapshot.listItems,
            selectedIndex: windowSelectedIndex(
                windows: windows,
                freshIndex: snapshot.selectedIndex,
                retainingSession: retainingSession
            ),
            triggerShortcut: windowTriggerShortcut(),
            alternateModeKeyCode: alternateModeKeyCode(activeMode: .currentAppWindowSwitching),
            retainingSession: retainingSession,
            onClose: { [weak self, weak overlayController] item, presentationID in
                guard let self,
                      let window = snapshot.element(withID: item.id) else {
                    return
                }

                _ = self.windowCloseService.close(
                    window,
                    permissionState: permissionState,
                    onDestroyed: {
                        overlayController?.confirmWindowDisappeared(
                            id: item.id,
                            presentationID: presentationID
                        )
                    }
                )
            },
            onConfirm: { [weak self] item, _ in
                guard let self,
                      let selectedWindow = snapshot.element(withID: item.id) else {
                    return
                }

                let selectionCoordinator = WindowSelectionCoordinator(
                    focusService: self.windowFocusService,
                    recencyStore: self.recencyStore
                )
                selectionCoordinator.confirm(selectedWindow, permissionState: permissionState)
                self.usageMetricsStore.flush()
            },
            onModeSwitch: { [weak self] reverse in
                self?.switchOverlayMode(reverse: reverse)
            }
        )
        let thumbnailPointSize = SwitcherOverlayLayoutMetrics.metrics(
            for: applicationSettingsStore.overlaySizeScale
        ).thumbnailSize
        let viewportPixelSize = WindowThumbnailCaptureSizing.viewportPixelSize(for: thumbnailPointSize)
        thumbnailLoaderForRefresh().refresh(
            windows: windows,
            permissionState: permissionState,
            viewportPixelSize: viewportPixelSize
        )
        return true
    }

    @discardableResult
    private func presentApplicationSwitcher(
        reverse: Bool,
        retainingSession: Bool
    ) -> Bool {
        guard let overlayController else {
            return false
        }

        cancelThumbnailLoadingIfNeeded()
        let recentlyOrderedApplications = applicationRecencyStore.order(
            applicationProvider.runningApplications()
        ) { application in
            application.id
        }
        let applications = SwitcherWindowOrderPolicy.pinningFocusedWindowFirst(
            recentlyOrderedApplications
        ) { application in
            application.isActive
        }
        guard !applications.isEmpty else {
            guard !retainingSession else {
                return false
            }

            overlayController.dismiss()
            return false
        }

        let snapshot = SwitcherPresentationSnapshot(
            elements: applications,
            reverse: reverse
        ) { application in
            application.switcherListItem
        }
        guard let presentationID = overlayController.present(
            mode: .applicationSwitching,
            items: snapshot.listItems,
            selectedIndex: applicationSelectedIndex(
                applications: applications,
                reverse: reverse,
                retainingSession: retainingSession
            ),
            triggerShortcut: applicationTriggerShortcut(),
            alternateModeKeyCode: alternateModeKeyCode(activeMode: .applicationSwitching),
            retainingSession: retainingSession,
            onQuit: { [weak self] item, _ in
                guard let self,
                      let selectedApplication = snapshot.element(withID: item.id) else {
                    return
                }

                _ = self.applicationTerminationService.terminate(selectedApplication)
            },
            onConfirm: { [weak self] item, _ in
                guard let self,
                      let selectedApplication = snapshot.element(withID: item.id) else {
                    return
                }

                let selectionCoordinator = ApplicationSelectionCoordinator(
                    activationService: self.applicationActivationService,
                    recencyStore: self.applicationRecencyStore
                )
                selectionCoordinator.confirm(selectedApplication)
            },
            onModeSwitch: { [weak self] reverse in
                self?.switchOverlayMode(reverse: reverse)
            }
        ) else {
            return false
        }

        applicationWindowCountLoader.load(applications: applications) { [weak self] countedApplications in
            Task { @MainActor [weak self] in
                self?.overlayController?.updateApplicationItems(
                    countedApplications.map(\.switcherListItem),
                    presentationID: presentationID
                )
            }
        }
        return true
    }

    /// A mode switch arrives on the window this application was last left on,
    /// or on its frontmost window; it never skips ahead, because the highlight
    /// is the choice that a release would commit.
    private func windowSelectedIndex(
        windows: [WindowItem],
        freshIndex: Int,
        retainingSession: Bool
    ) -> Int {
        guard retainingSession,
              let ownerProcessIdentifier = windows.first?.ownerProcessIdentifier else {
            return freshIndex
        }

        let rememberedIndex = modeSwitchMemory
            .windowID(ownerProcessIdentifier: ownerProcessIdentifier)
            .flatMap { rememberedID in
                windows.firstIndex { $0.id == rememberedID }
            }
        return SwitcherModeSwitchMemory.resumedIndex(
            itemCount: windows.count,
            rememberedIndex: rememberedIndex,
            advance: 0,
            fallback: 0
        )
    }

    /// Returning to application mode resumes the application that was left and
    /// then advances one step, so the key that switched modes still moves the
    /// selection the way it does inside a mode.
    private func applicationSelectedIndex(
        applications: [ApplicationItem],
        reverse: Bool,
        retainingSession: Bool
    ) -> Int {
        let freshIndex = ApplicationSwitcherSelectionPolicy.initialSelectedIndex(
            applications: applications,
            reverse: reverse
        )
        guard retainingSession else {
            return freshIndex
        }

        let rememberedIndex = modeSwitchMemory.applicationID.flatMap { rememberedID in
            applications.firstIndex { $0.id == rememberedID }
        }
        return SwitcherModeSwitchMemory.resumedIndex(
            itemCount: applications.count,
            rememberedIndex: rememberedIndex,
            advance: reverse ? -1 : 1,
            fallback: freshIndex
        )
    }

    /// The key that hands the overlay to the other mode, or `nil` while that
    /// mode is disabled or unregistered — the overlay must not swallow a key
    /// macOS still owns.
    private func alternateModeKeyCode(activeMode: SwitcherMode) -> UInt16? {
        switch activeMode {
        case .currentAppWindowSwitching:
            guard applicationHotkeyController.isRegistered else {
                return nil
            }

            return resolvedKeyCode(for: configuredShortcut(for: .applicationSwitching))
        case .applicationSwitching:
            guard let windowSetting = hotkeyService.registeredSetting(
                for: .currentAppWindowSwitching
            ) else {
                return nil
            }

            return resolvedKeyCode(for: windowSetting)
        }
    }

    private func resolvedKeyCode(for setting: ShortcutSetting) -> UInt16? {
        setting.keyCode ?? ShortcutKeyCodeResolver.keyCode(for: setting.keyEquivalent)
    }

    private func thumbnailLoaderForRefresh() -> WindowThumbnailLoader {
        if let thumbnailLoader {
            return thumbnailLoader
        }

        let thumbnailLoader = WindowThumbnailLoader(
            store: thumbnailStore,
            capturer: ScreenCaptureKitWindowThumbnailCapturer()
        )
        self.thumbnailLoader = thumbnailLoader
        return thumbnailLoader
    }

    private func cancelThumbnailLoadingIfNeeded() {
        thumbnailLoader?.cancel()
    }

    private func advancePresentedOverlayIfNeeded(
        overlayController: SwitcherOverlayController,
        mode: SwitcherMode,
        reverse: Bool
    ) -> Bool {
        guard overlayController.isPresented,
              overlayController.activeMode == mode else {
            return false
        }

        _ = overlayController.handle(reverse ? .moveUp : .moveDown)
        return true
    }

    private func observeShortcutRecording() {
        observe(.shortcutRecordingDidBegin, storing: &shortcutRecordingDidBeginObserver) { [weak self] in
            guard let self else {
                return
            }

            self.shortcutRecordingHotkeyLifecycle.begin()
        }

        observe(.shortcutRecordingDidEnd, storing: &shortcutRecordingDidEndObserver) { [weak self] in
            guard let self else {
                return
            }

            self.shortcutRecordingHotkeyLifecycle.end(
                configurations: self.shortcutStore.loadConfigurations()
            )
        }
    }

    private func observeWorkspaceApplicationActivation() {
        guard workspaceApplicationActivationObserver == nil else {
            return
        }

        workspaceApplicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }

            let snapshot = RunningApplicationSnapshot(
                processIdentifier: Int(application.processIdentifier),
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                isRegular: application.activationPolicy == .regular,
                isTerminated: application.isTerminated,
                isActive: application.isActive
            )
            MainActor.assumeIsolated {
                self?.workspaceActivationRecencyObserver.recordActivation(snapshot)
            }
        }
    }

    private func observeWorkspaceApplicationTermination() {
        guard workspaceApplicationTerminationObserver == nil else {
            return
        }

        workspaceApplicationTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }

            let snapshot = RunningApplicationSnapshot(
                processIdentifier: Int(application.processIdentifier),
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                isRegular: application.activationPolicy == .regular,
                isTerminated: application.isTerminated,
                isActive: application.isActive
            )
            guard let id = WorkspaceApplicationTerminationPolicy.applicationIdentifier(
                for: snapshot
            ) else {
                return
            }

            MainActor.assumeIsolated {
                // A recycled process identifier must not resume a dead app's window.
                self?.modeSwitchMemory.forgetWindows(
                    ownerProcessIdentifier: snapshot.processIdentifier
                )
                self?.overlayController?.confirmApplicationTerminated(
                    id: id,
                    processIdentifier: snapshot.processIdentifier
                )
            }
        }
    }

    private func observeApplicationActivation() {
        observe(NSApplication.didBecomeActiveNotification, storing: &applicationDidBecomeActiveObserver) { [weak self] in
            guard let self else {
                return
            }

            self.shortcutRecordingHotkeyLifecycle.applicationDidBecomeActive(
                configurations: self.shortcutStore.loadConfigurations()
            )
        }
    }

    private func observeSettingsRequests() {
        observe(.showSettingsWindow, storing: &settingsRequestObserver) { [weak self] in
            self?.showSettingsWindow()
        }
    }

    private func observeAboutRequests() {
        observe(.showAboutWindow, storing: &aboutRequestObserver) { [weak self] in
            self?.showAboutWindow()
        }
    }

    private func observeUpdateCheckRequests() {
        observe(.checkForUpdates, storing: &updateCheckRequestObserver) { [weak self] in
            self?.updateChecker.checkForUpdates()
        }
    }

    private func observe(
        _ name: Notification.Name,
        storing observer: inout NSObjectProtocol?,
        using handler: @escaping @MainActor @Sendable () -> Void
    ) {
        observe(name, storing: &observer, extracting: { _ in () }) { _ in
            handler()
        }
    }

    private func observe<Payload: Sendable>(
        _ name: Notification.Name,
        storing observer: inout NSObjectProtocol?,
        extracting payload: @escaping @Sendable (Notification) -> Payload?,
        using handler: @escaping @MainActor @Sendable (Payload) -> Void
    ) {
        guard observer == nil else {
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { notification in
            guard let payload = payload(notification) else {
                return
            }

            MainActor.assumeIsolated {
                handler(payload)
            }
        }
    }

    private func removeNotificationObservers() {
        removeObserver(&shortcutRecordingDidBeginObserver)
        removeObserver(&shortcutRecordingDidEndObserver)
        removeObserver(&applicationDidBecomeActiveObserver)
        removeWorkspaceApplicationActivationObserver()
        removeWorkspaceApplicationTerminationObserver()
        removeObserver(&settingsRequestObserver)
        removeObserver(&aboutRequestObserver)
        removeObserver(&updateCheckRequestObserver)
    }

    private func removeObserver(_ observer: inout NSObjectProtocol?) {
        guard let registeredObserver = observer else {
            return
        }

        NotificationCenter.default.removeObserver(registeredObserver)
        observer = nil
    }

    private func removeWorkspaceApplicationActivationObserver() {
        guard let workspaceApplicationActivationObserver else {
            return
        }

        NSWorkspace.shared.notificationCenter.removeObserver(workspaceApplicationActivationObserver)
        self.workspaceApplicationActivationObserver = nil
    }

    private func removeWorkspaceApplicationTerminationObserver() {
        guard let workspaceApplicationTerminationObserver else {
            return
        }

        NSWorkspace.shared.notificationCenter.removeObserver(workspaceApplicationTerminationObserver)
        self.workspaceApplicationTerminationObserver = nil
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                activationCoordinator: SettingsActivationPolicyCoordinator(
                    policyApplier: NSApplicationActivationPolicyApplier()
                ),
                updateChecker: updateChecker,
                onShortcutChanged: { [weak self] candidate, previous in
                    self?.applyShortcutChange(
                        candidateConfiguration: candidate,
                        previousConfiguration: previous
                    ) ?? .rollbackFailed
                },
                onEnabledChanged: { [weak self] configuration in
                    self?.applyEnabledChange(configuration: configuration)
                }
            )
        }

        settingsWindowController?.show()
    }

    private func showSettingsWindowIfNeededOnLaunch() {
        guard ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: applicationSettingsStore.menuBarIconVisible,
            permissionState: permissionService.currentState()
        ) else {
            return
        }

        showSettingsWindow()
    }

    private func showAboutWindow() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController { [weak self] in
                guard let self else {
                    return AboutSwitchTabContent.current(
                        usageDashboard: .empty
                    )
                }

                return AboutSwitchTabContent.current(
                    usageDashboard: self.usageMetricsStore.todayDashboard(
                        windowShortcutLabel: self.displayedWindowShortcutLabel()
                    )
                )
            }
        }

        aboutWindowController?.show()
    }

    private func displayedWindowShortcutLabel() -> String {
        let registeredWindowShortcut = hotkeyService.registeredSetting(for: .currentAppWindowSwitching)
        let windowShortcut = registeredWindowShortcut
            ?? configuredShortcut(for: .currentAppWindowSwitching)
        return windowShortcut.displayText
    }

    private func windowTriggerShortcut() -> ShortcutSetting {
        hotkeyService.registeredSetting(for: .currentAppWindowSwitching)
            ?? configuredShortcut(for: .currentAppWindowSwitching)
    }

    private func applicationTriggerShortcut() -> ShortcutSetting {
        configuredShortcut(for: .applicationSwitching)
    }

    private func configuredShortcut(for mode: SwitcherMode) -> ShortcutSetting {
        shortcutStore.loadConfigurations().first { $0.mode == mode }?.shortcut
            ?? SwitcherShortcutConfiguration.defaultValue(for: mode).shortcut
    }

    @discardableResult
    private func registerWindowHotkeys(
        setting windowSetting: ShortcutSetting,
        configurations: [SwitcherShortcutConfiguration]
    ) -> Bool {
        hotkeyService.unregisterAll()

        let windowReverseSetting = windowSetting.reverseVariant(id: "\(windowSetting.id)-reverse")
        let existingShortcuts = AppDelegateShortcutConflictPolicy
            .windowRegistrationExistingShortcuts(
                windowSetting: windowSetting,
                configurations: configurations
            )

        let forwardResult = hotkeyService.registerFirstUsable(
            primaryCandidate: windowSetting,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: existingShortcuts.forward,
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher()
        }
        debugLog("registered forward shortcut=\(windowSetting.displayText) keyCode=\(String(describing: windowSetting.keyCode)) result=\(forwardResult)")

        let reverseResult = hotkeyService.registerFirstUsable(
            primaryCandidate: windowReverseSetting,
            fallbackCandidate: .fallbackCurrentAppWindowSwitchingReverse,
            existing: existingShortcuts.reverse,
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher(reverse: true)
        }
        debugLog("registered reverse shortcut=\(windowReverseSetting.displayText) keyCode=\(String(describing: windowReverseSetting.keyCode)) result=\(reverseResult)")

        return forwardResult == .registered && reverseResult == .registered
    }

    private func registerConfiguredHotkeys(
        _ configurations: [SwitcherShortcutConfiguration]
    ) {
        shortcutRecordingHotkeyLifecycle.restore(configurations: configurations)
    }

    @discardableResult
    private func updateApplicationHotkeyRegistration(
        configuration: SwitcherShortcutConfiguration,
        existingShortcuts: [ShortcutSetting] = []
    ) -> Bool {
        guard configuration.isEnabled else {
            applicationHotkeyController.unregisterAll()
            if overlayController?.activeMode == .applicationSwitching {
                overlayController?.dismiss()
            }
            return true
        }

        return applicationHotkeyController.updateRegistration(
            setting: configuration.shortcut,
            enabled: true,
            existing: existingShortcuts,
            forwardHandler: { [weak self] in
                self?.showApplicationSwitcher()
            },
            reverseHandler: { [weak self] in
                self?.showApplicationSwitcher(reverse: true)
            }
        )
    }

    private func persistRegistrationMessages() {
        let registrationMessages = hotkeyService.registrationMessageSnapshot()
            + applicationHotkeyController.registrationMessageSnapshot()
        if shortcutStore.saveRegistrationMessages(registrationMessages) {
            NotificationCenter.default.post(name: .shortcutRegistrationDidChange, object: nil)
        }
    }

    private func applyShortcutChange(
        candidateConfiguration: SwitcherShortcutConfiguration,
        previousConfiguration: SwitcherShortcutConfiguration
    ) -> ShortcutChangeResult {
        let configurations = shortcutStore.loadConfigurations()

        switch candidateConfiguration.mode {
        case .currentAppWindowSwitching:
            let previousWindowSnapshot = hotkeyService.registrationSnapshot(
                for: .currentAppWindowSwitching,
                expectedEnabled: previousConfiguration.isEnabled
            )
            guard candidateConfiguration.isEnabled else {
                hotkeyService.unregisterAll()
                persistRegistrationMessages()
                return .applied
            }

            guard registerExactWindowHotkeys(
                setting: candidateConfiguration.shortcut,
                configurations: replacing(
                    candidateConfiguration,
                    in: configurations
                )
            ) else {
                guard !shortcutRecordingHotkeyLifecycle.isRecording else {
                    shortcutRecordingHotkeyLifecycle.begin()
                    return .rejectedRestorationDeferred
                }

                let didRestorePreviousWindow = restoreExactWindowHotkeys(
                    snapshot: previousWindowSnapshot,
                    configuredSetting: previousConfiguration.shortcut,
                    configurations: replacing(
                        previousConfiguration,
                        in: configurations
                    )
                )
                persistRegistrationMessages()
                return didRestorePreviousWindow
                    ? .rejectedPreviousRestored
                    : .rollbackFailed
            }

        case .applicationSwitching:
            let candidateConfigurations = replacing(
                candidateConfiguration,
                in: configurations
            )
            let windowConfiguration = configuration(
                for: .currentAppWindowSwitching,
                in: candidateConfigurations
            )
            let previousConfigurations = replacing(
                previousConfiguration,
                in: configurations
            )
            let previousWindowConfiguration = configuration(
                for: .currentAppWindowSwitching,
                in: previousConfigurations
            )
            let previousWindowSnapshot = hotkeyService.registrationSnapshot(
                for: .currentAppWindowSwitching,
                expectedEnabled: previousWindowConfiguration.isEnabled
            )
            let deferredRestoration: (() -> Void)? = shortcutRecordingHotkeyLifecycle.isRecording
                ? { self.shortcutRecordingHotkeyLifecycle.begin() }
                : nil
            let transaction = ApplicationShortcutLifecycleTransaction(
                previousWindowSnapshot: previousWindowSnapshot,
                suspendWindow: {
                    self.hotkeyService.unregisterAll()
                },
                registerApplicationCandidate: {
                    self.updateApplicationHotkeyRegistration(
                        configuration: candidateConfiguration
                    )
                },
                registerWindowWithCandidateConflicts: {
                    guard windowConfiguration.isEnabled else {
                        return true
                    }

                    return self.registerWindowHotkeys(
                        setting: windowConfiguration.shortcut,
                        configurations: candidateConfigurations
                    )
                },
                restorePreviousApplication: {
                    self.hotkeyService.unregisterAll()
                    return self.updateApplicationHotkeyRegistration(
                        configuration: previousConfiguration
                    )
                },
                restorePreviousWindow: { snapshot in
                    self.restoreExactWindowHotkeys(
                        snapshot: snapshot,
                        configuredSetting: previousWindowConfiguration.shortcut,
                        configurations: previousConfigurations
                    )
                },
                deferredRestoration: deferredRestoration
            )
            let result = transaction.apply()
            guard result == .applied else {
                persistRegistrationMessages()
                return result
            }
        }

        persistRegistrationMessages()
        return .applied
    }

    private func applyEnabledChange(configuration: SwitcherShortcutConfiguration) {
        let configurations = replacing(
            configuration,
            in: shortcutStore.loadConfigurations()
        )
        let lifecycle = ShortcutEnabledLifecycle(
            windowHotkeyService: hotkeyService,
            registerWindowHotkeys: { setting in
                self.registerWindowHotkeys(
                    setting: setting,
                    configurations: configurations
                )
            },
            updateApplicationHotkeyRegistration: { configuration in
                self.updateApplicationHotkeyRegistration(
                    configuration: configuration,
                    existingShortcuts: self.hotkeyService.registeredSettings(
                        for: .currentAppWindowSwitching
                    )
                )
            },
            dismissWindowOverlayIfActive: {
                guard self.overlayController?.activeMode == .currentAppWindowSwitching else {
                    return
                }
                self.overlayController?.dismiss()
            },
            persistRegistrationMessages: {
                self.persistRegistrationMessages()
            }
        )
        lifecycle.apply(configuration: configuration)
    }

    private func registerExactWindowHotkeys(
        setting windowSetting: ShortcutSetting,
        configurations: [SwitcherShortcutConfiguration]
    ) -> Bool {
        restoreExactWindowHotkeys(
            snapshot: HotkeyRegistrationSnapshot(
                mode: .currentAppWindowSwitching,
                expectedEnabled: true,
                settings: [
                    windowSetting,
                    windowSetting.reverseVariant(id: "\(windowSetting.id)-reverse")
                ],
                registrationMessages: []
            ),
            configuredSetting: windowSetting,
            configurations: configurations
        )
    }

    private func restoreExactWindowHotkeys(
        snapshot: HotkeyRegistrationSnapshot,
        configuredSetting: ShortcutSetting,
        configurations: [SwitcherShortcutConfiguration]
    ) -> Bool {
        hotkeyService.unregisterAll()
        let directions = snapshot.settings.compactMap {
            windowHotkeyDirection(for: $0, configuredSetting: configuredSetting)
        }
        guard snapshot.mode == .currentAppWindowSwitching,
              directions.count == snapshot.settings.count,
              snapshot.expectedEnabled
                ? directions == [.forward, .reverse]
                : directions.isEmpty else {
            return false
        }

        let applicationShortcuts = AppDelegateShortcutConflictPolicy
            .enabledApplicationShortcuts(in: configurations)
        var restoredSettings: [ShortcutSetting] = []

        for (setting, direction) in zip(snapshot.settings, directions) {
            let existingSettings = applicationShortcuts + restoredSettings
            let result: HotkeyRegistrationResult
            switch direction {
            case .forward:
                result = hotkeyService.register(
                    setting: setting,
                    existing: existingSettings,
                    mode: .currentAppWindowSwitching
                ) { [weak self] in
                    self?.showCurrentAppSwitcher()
                }
            case .reverse:
                result = hotkeyService.register(
                    setting: setting,
                    existing: existingSettings,
                    mode: .currentAppWindowSwitching
                ) { [weak self] in
                    self?.showCurrentAppSwitcher(reverse: true)
                }
            }

            guard result == .registered else {
                return false
            }
            restoredSettings.append(setting)
        }

        return hotkeyService.restoreRegistrationMetadata(from: snapshot)
    }

    private enum WindowHotkeyDirection: Equatable {
        case forward
        case reverse
    }

    private func windowHotkeyDirection(
        for setting: ShortcutSetting,
        configuredSetting: ShortcutSetting
    ) -> WindowHotkeyDirection? {
        if setting == configuredSetting
            || setting == .fallbackCurrentAppWindowSwitching {
            return .forward
        }

        let configuredReverse = configuredSetting.reverseVariant(
            id: "\(configuredSetting.id)-reverse"
        )
        if setting == configuredReverse
            || setting == .fallbackCurrentAppWindowSwitchingReverse {
            return .reverse
        }

        return nil
    }

    private func configuration(
        for mode: SwitcherMode,
        in configurations: [SwitcherShortcutConfiguration]
    ) -> SwitcherShortcutConfiguration {
        configurations.first { $0.mode == mode }
            ?? .defaultValue(for: mode)
    }

    private func replacing(
        _ configuration: SwitcherShortcutConfiguration,
        in configurations: [SwitcherShortcutConfiguration]
    ) -> [SwitcherShortcutConfiguration] {
        configurations.map { existing in
            existing.mode == configuration.mode ? configuration : existing
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        NSLog("[SwitchTabDebug] \(message)")
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let logURL = libraryURL.appendingPathComponent("SwitchTabDebug.log")
        let line = "\(Date()) [SwitchTabDebug] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path) {
            let maxLogSizeInBytes: UInt64 = 1_048_576
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attributes[.size] as? UInt64,
               size > maxLogSizeInBytes {
                try? data.write(to: logURL, options: .atomic)
                return
            }

            guard let handle = try? FileHandle(forWritingTo: logURL) else {
                return
            }
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
        #endif
    }

}

enum ApplicationSwitcherWindowCountPolicy {
    static func addingCounts(
        to applications: [ApplicationItem],
        windowCount: (ApplicationItem) -> Int?
    ) -> [ApplicationItem] {
        applications.map { application in
            application.withWindowCount(windowCount(application))
        }
    }
}

final class ApplicationWindowCountLoader: @unchecked Sendable {
    typealias LoadCounts = @Sendable ([ApplicationItem]) -> [ApplicationItem]

    private let queue: DispatchQueue
    private let loadCounts: LoadCounts

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.royjen.switchtab.application-window-counts",
            qos: .userInitiated
        ),
        loadCounts: @escaping LoadCounts = { applications in
            let windowProvider = AccessibilityWindowProvider()
            return ApplicationSwitcherWindowCountPolicy.addingCounts(
                to: applications
            ) { application in
                windowProvider.applicationWindowCount(
                    ownerProcessIdentifier: application.processIdentifier
                )
            }
        }
    ) {
        self.queue = queue
        self.loadCounts = loadCounts
    }

    func load(
        applications: [ApplicationItem],
        completion: @escaping @Sendable ([ApplicationItem]) -> Void
    ) {
        let loadCounts = self.loadCounts
        queue.async {
            completion(loadCounts(applications))
        }
    }
}
