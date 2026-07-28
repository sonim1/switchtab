import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: SwitcherOverlayController?
    private let windowProvider = AccessibilityWindowProvider()
    private let windowFocusService = WindowFocusService()
    private let windowCloseService = WindowCloseService()
    private let permissionService = PermissionService()
    private let shortcutStore = ShortcutSettingsStore()
    private let applicationSettingsStore = ApplicationSettingsStore()
    private let updateChecker: any UpdateChecking = UpdateControllerFactory.make()
    private let recencyStore = SwitcherRecencyStore()
    private let usageMetricsStore = UsageMetricsStore()
    private let hotkeyService = HotkeyService()
    private let thumbnailStore = WindowThumbnailStore()
    private var thumbnailLoader: WindowThumbnailLoader?
    private var menuBarStatusItemController: MenuBarStatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var shortcutSettingsObserver: NSObjectProtocol?
    private var shortcutRecordingDidBeginObserver: NSObjectProtocol?
    private var shortcutRecordingDidEndObserver: NSObjectProtocol?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
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
        }
        self.overlayController = overlayController
        menuBarStatusItemController = MenuBarStatusItemController(
            store: applicationSettingsStore,
            updateChecker: updateChecker
        )
        observeShortcutChanges()
        observeShortcutRecording()
        observeApplicationActivation()
        observeSettingsRequests()
        observeAboutRequests()
        observeUpdateCheckRequests()
        registerWindowHotkeys(setting: shortcutStore.load())
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
        recencyStore.flush()
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

        cancelThumbnailLoadingIfNeeded()
        let accessibilityState = permissionService.currentAccessibilityState()
        debugLog("accessibility state=\(accessibilityState)")
        guard !accessibilityState.blocksCapability else {
            debugLog("accessibility missing; showing settings")
            showSettingsWindow()
            return
        }

        let permissionState = permissionService.currentState(accessibility: accessibilityState)
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            debugLog(
                "frontmost app pid=\(frontmostApplication.processIdentifier) name=\(frontmostApplication.localizedName ?? "unknown")"
            )
        } else {
            debugLog("frontmost app missing")
        }
        let recentlyOrderedWindows = recencyStore.order(
            windowProvider.currentApplicationWindows(
                includeScreenCaptureIdentifiers: !permissionState.blocksWindowPreviews
            )
        ) { window in
            window.id
        }
        let windows = SwitcherWindowOrderPolicy.pinningFocusedWindowFirst(recentlyOrderedWindows) { window in
            window.isFocused
        }
        debugLog("window count=\(windows.count)")
        guard !windows.isEmpty else {
            debugLog("no windows; dismissing overlay")
            overlayController.dismiss()
            return
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
            selectedIndex: snapshot.selectedIndex,
            triggerShortcut: windowTriggerShortcut(),
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

    private func observeShortcutChanges() {
        observe(
            .shortcutSettingsDidChange,
            storing: &shortcutSettingsObserver,
            extracting: { $0.userInfo?["settings"] as? [ShortcutSetting] }
        ) { [weak self] settings in
            self?.registerWindowHotkeys(settings: settings)
        }
    }

    private func observeShortcutRecording() {
        observe(.shortcutRecordingDidBegin, storing: &shortcutRecordingDidBeginObserver) { [weak self] in
            self?.hotkeyService.unregisterAll()
        }

        observe(.shortcutRecordingDidEnd, storing: &shortcutRecordingDidEndObserver) { [weak self] in
            guard let self else {
                return
            }

            self.registerWindowHotkeys(setting: self.shortcutStore.load())
        }
    }

    private func observeApplicationActivation() {
        observe(NSApplication.didBecomeActiveNotification, storing: &applicationDidBecomeActiveObserver) { [weak self] in
            guard let self else {
                return
            }

            self.registerWindowHotkeys(setting: self.shortcutStore.load())
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
        removeObserver(&shortcutSettingsObserver)
        removeObserver(&shortcutRecordingDidBeginObserver)
        removeObserver(&shortcutRecordingDidEndObserver)
        removeObserver(&applicationDidBecomeActiveObserver)
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

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                activationCoordinator: SettingsActivationPolicyCoordinator(
                    policyApplier: NSApplicationActivationPolicyApplier()
                ),
                updateChecker: updateChecker,
                onShortcutChange: { [weak self] candidate, previous in
                    self?.replaceWindowHotkeys(candidate: candidate, previous: previous) ?? false
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
        let windowShortcut = registeredWindowShortcut ?? shortcutStore.load()
        return windowShortcut.displayText
    }

    private func windowTriggerShortcut() -> ShortcutSetting {
        hotkeyService.registeredSetting(for: .currentAppWindowSwitching)
            ?? shortcutStore.load()
    }

    private func registerWindowHotkeys(settings: [ShortcutSetting]) {
        let windowSetting = settings.first { $0.mode == .currentAppWindowSwitching }
            ?? ShortcutSetting.defaultCurrentAppWindowSwitching
        registerWindowHotkeys(setting: windowSetting)
    }

    private func registerWindowHotkeys(setting windowSetting: ShortcutSetting) {
        hotkeyService.unregisterAll()

        let windowReverseSetting = windowSetting.reverseVariant(id: "\(windowSetting.id)-reverse")

        let forwardResult = hotkeyService.registerFirstUsable(
            primaryCandidate: windowSetting,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher()
        }
        debugLog("registered forward shortcut=\(windowSetting.displayText) keyCode=\(String(describing: windowSetting.keyCode)) result=\(forwardResult)")

        let reverseResult = hotkeyService.registerFirstUsable(
            primaryCandidate: windowReverseSetting,
            fallbackCandidate: .fallbackCurrentAppWindowSwitchingReverse,
            existing: [windowSetting],
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher(reverse: true)
        }
        debugLog("registered reverse shortcut=\(windowReverseSetting.displayText) keyCode=\(String(describing: windowReverseSetting.keyCode)) result=\(reverseResult)")

        let registrationMessages = hotkeyService.registrationMessageSnapshot()
        if shortcutStore.saveRegistrationMessages(registrationMessages) {
            NotificationCenter.default.post(name: .shortcutRegistrationDidChange, object: nil)
        }
    }

    private func replaceWindowHotkeys(
        candidate: ShortcutSetting,
        previous: ShortcutSetting
    ) -> Bool {
        guard registerExactWindowHotkeys(setting: candidate) else {
            registerWindowHotkeys(setting: previous)
            return false
        }

        return true
    }

    private func registerExactWindowHotkeys(setting windowSetting: ShortcutSetting) -> Bool {
        hotkeyService.unregisterAll()

        let forwardResult = hotkeyService.register(
            setting: windowSetting,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher()
        }
        guard forwardResult == .registered else {
            return false
        }

        let reverseSetting = windowSetting.reverseVariant(id: "\(windowSetting.id)-reverse")
        let reverseResult = hotkeyService.register(
            setting: reverseSetting,
            existing: [windowSetting],
            mode: .currentAppWindowSwitching
        ) { [weak self] in
            self?.showCurrentAppSwitcher(reverse: true)
        }

        return reverseResult == .registered
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
