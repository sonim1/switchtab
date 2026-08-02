import Combine
import Foundation
import SwitchTab

enum ApplicationSettingsStoreTests {
    @MainActor
    static func run() throws {
        try testMenuBarIconDefaultsToVisible()
        try testMenuBarIconVisibilityPersists()
        try testMenuBarIconVisibilityChangePostsNotification()
        try testMenuBarIconVisibilityNoOpDoesNotPostNotification()
        try testReplacesCommandTabBridgeLoadsDefaultAndMigratedValue()
        try testReplacesCommandTabBridgePersistsUnifiedConfiguration()
        try testReplacesCommandTabViewModelForwardsSuccessfulChange()
        try testReplacesCommandTabBridgeNoOpDoesNotWriteNotifyOrPublish()
        try testReplacesCommandTabBridgeRejectsFuturePayload()
        try testOverlaySizeScaleDefaultsToOne()
        try testOverlaySizeScalePersists()
        try testOverlaySizeScaleNoOpDoesNotPostNotification()
        try testOverlaySizeScaleMigratesLegacyPreference()
        try testStoredScaleWinsOverLegacyPreference()
        try testViewModelTogglesMenuBarIconVisibility()
        try testViewModelUpdatesOverlaySizeScale()
        try testViewModelHidesUpdateControlsWhenUnavailable()
        try testViewModelForwardsManualUpdateChecks()
        try testViewModelUpdatesAutomaticCheckPreference()
        try testViewModelTogglesStartAtLogin()
        try testViewModelKeepsStartAtLoginStateWhenServiceFails()
        try testLaunchPolicyShowsSettingsWhenMenuBarIconIsHidden()
        try testLaunchPolicyShowsSettingsWhenAnyPermissionIsMissing()
    }

    static func testMenuBarIconDefaultsToVisible() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())

        try expectTrue(store.menuBarIconVisible)
    }

    static func testMenuBarIconVisibilityPersists() throws {
        let defaults = makeDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)

        store.saveMenuBarIconVisible(false)

        try expectFalse(ApplicationSettingsStore(userDefaults: defaults).menuBarIconVisible)
    }

    static func testMenuBarIconVisibilityChangePostsNotification() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveMenuBarIconVisible(false)

        try expectTrue(recorder.didPostNotification)
    }

    static func testMenuBarIconVisibilityNoOpDoesNotPostNotification() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveMenuBarIconVisible(true)

        try expectEqual(recorder.postCount, 0)
    }

    static func testReplacesCommandTabBridgeLoadsDefaultAndMigratedValue() throws {
        let freshDefaults = makeDefaults()
        try expectTrue(ApplicationSettingsStore(userDefaults: freshDefaults).replacesCommandTab)

        let legacyDefaults = makeDefaults()
        legacyDefaults.set(false, forKey: ApplicationSettingsStore.replacesCommandTabKey)
        let legacyStore = ApplicationSettingsStore(userDefaults: legacyDefaults)

        try expectFalse(legacyStore.replacesCommandTab)
        try expectFalse(
            ShortcutSettingsStore(userDefaults: legacyDefaults)
                .loadConfigurations()
                .first { $0.mode == .applicationSwitching }?
                .isEnabled ?? true
        )
    }

    static func testReplacesCommandTabBridgePersistsUnifiedConfiguration() throws {
        let defaults = makeDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)
        let settingsRecorder = NotificationRecorder()
        let commandTabRecorder = NotificationRecorder()
        let settingsObserver = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            settingsRecorder.record()
        }
        let commandTabObserver = NotificationCenter.default.addObserver(
            forName: .commandTabReplacementDidChange,
            object: nil,
            queue: nil
        ) { _ in
            commandTabRecorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(settingsObserver)
            NotificationCenter.default.removeObserver(commandTabObserver)
        }

        let didSave = store.saveReplacesCommandTab(false)

        try expectTrue(didSave)
        try expectFalse(store.replacesCommandTab)
        try expectFalse(
            ShortcutSettingsStore(userDefaults: defaults)
                .loadConfigurations()
                .first { $0.mode == .applicationSwitching }?
                .isEnabled ?? true
        )
        try expectTrue(defaults.object(forKey: ApplicationSettingsStore.replacesCommandTabKey) == nil)
        try expectEqual(settingsRecorder.postCount, 1)
        try expectEqual(commandTabRecorder.postCount, 1)
    }

    @MainActor
    static func testReplacesCommandTabViewModelForwardsSuccessfulChange() throws {
        let defaults = makeDefaults()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        let didSave = viewModel.setReplacesCommandTab(false)

        try expectTrue(didSave)
        try expectFalse(viewModel.replacesCommandTab)
        try expectFalse(
            ShortcutSettingsStore(userDefaults: defaults)
                .loadConfigurations()
                .first { $0.mode == .applicationSwitching }?
                .isEnabled ?? true
        )
        try expectEqual(viewModel.errorMessage, nil)
        try expectEqual(publishCount, 1)
    }

    @MainActor
    static func testReplacesCommandTabBridgeNoOpDoesNotWriteNotifyOrPublish() throws {
        let defaults = CountingShortcutDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)
        let viewModel = ApplicationSettingsViewModel(
            store: store,
            launchAtLoginService: FakeLaunchAtLoginService()
        )
        let enabled = viewModel.replacesCommandTab
        let initialWriteCount = defaults.writeCount
        let settingsRecorder = NotificationRecorder()
        let commandTabRecorder = NotificationRecorder()
        let settingsObserver = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            settingsRecorder.record()
        }
        let commandTabObserver = NotificationCenter.default.addObserver(
            forName: .commandTabReplacementDidChange,
            object: nil,
            queue: nil
        ) { _ in
            commandTabRecorder.record()
        }
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
            NotificationCenter.default.removeObserver(settingsObserver)
            NotificationCenter.default.removeObserver(commandTabObserver)
        }

        let didStoreSave = store.saveReplacesCommandTab(enabled)
        let didViewModelSave = viewModel.setReplacesCommandTab(enabled)

        try expectTrue(didStoreSave)
        try expectTrue(didViewModelSave)
        try expectEqual(defaults.writeCount, initialWriteCount)
        try expectEqual(settingsRecorder.postCount, 0)
        try expectEqual(commandTabRecorder.postCount, 0)
        try expectEqual(publishCount, 0)
    }

    @MainActor
    static func testReplacesCommandTabBridgeRejectsFuturePayload() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: ApplicationSettingsStore.replacesCommandTabKey)
        let futurePayload = try JSONEncoder().encode(
            ApplicationSettingsBridgePayload(
                version: 2,
                configurations: [
                    .defaultCurrentAppWindows,
                    .defaultApplicationSwitching
                ]
            )
        )
        defaults.set(futurePayload, forKey: "SwitchTab.shortcut.configurations")
        let store = ApplicationSettingsStore(userDefaults: defaults)
        let settingsRecorder = NotificationRecorder()
        let commandTabRecorder = NotificationRecorder()
        let settingsObserver = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            settingsRecorder.record()
        }
        let commandTabObserver = NotificationCenter.default.addObserver(
            forName: .commandTabReplacementDidChange,
            object: nil,
            queue: nil
        ) { _ in
            commandTabRecorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(settingsObserver)
            NotificationCenter.default.removeObserver(commandTabObserver)
        }

        try expectFalse(store.saveReplacesCommandTab(true))
        try expectEqual(defaults.data(forKey: "SwitchTab.shortcut.configurations"), futurePayload)
        try expectEqual(settingsRecorder.postCount, 0)
        try expectEqual(commandTabRecorder.postCount, 0)

        let viewModel = ApplicationSettingsViewModel(
            store: store,
            launchAtLoginService: FakeLaunchAtLoginService()
        )
        try expectFalse(viewModel.replacesCommandTab)

        let didSave = viewModel.setReplacesCommandTab(true)

        try expectFalse(didSave)
        try expectFalse(viewModel.replacesCommandTab)
        try expectEqual(
            viewModel.errorMessage,
            "Application switching could not be updated."
        )
        try expectEqual(defaults.data(forKey: "SwitchTab.shortcut.configurations"), futurePayload)
        try expectEqual(settingsRecorder.postCount, 0)
        try expectEqual(commandTabRecorder.postCount, 0)
    }

    static func testOverlaySizeScaleDefaultsToOne() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())

        try expectEqual(store.overlaySizeScale, .default)
    }

    static func testOverlaySizeScalePersists() throws {
        let defaults = makeDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)

        store.saveOverlaySizeScale(OverlaySizeScale(1.35))

        try expectEqual(
            ApplicationSettingsStore(userDefaults: defaults).overlaySizeScale,
            OverlaySizeScale(1.35)
        )
    }

    static func testOverlaySizeScaleMigratesLegacyPreference() throws {
        let defaults = makeDefaults()
        defaults.set(OverlaySizePreference.large.rawValue, forKey: ApplicationSettingsStore.overlaySizeKey)

        try expectEqual(
            ApplicationSettingsStore(userDefaults: defaults).overlaySizeScale,
            OverlaySizePreference.large.scale
        )
    }

    static func testStoredScaleWinsOverLegacyPreference() throws {
        let defaults = makeDefaults()
        defaults.set(OverlaySizePreference.compact.rawValue, forKey: ApplicationSettingsStore.overlaySizeKey)
        defaults.set(1.4, forKey: ApplicationSettingsStore.overlaySizeScaleKey)

        try expectEqual(
            ApplicationSettingsStore(userDefaults: defaults).overlaySizeScale,
            OverlaySizeScale(1.4)
        )
    }

    static func testOverlaySizeScaleNoOpDoesNotPostNotification() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .applicationSettingsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveOverlaySizeScale(.default)

        try expectEqual(recorder.postCount, 0)
    }

    @MainActor
    static func testViewModelTogglesMenuBarIconVisibility() throws {
        let defaults = makeDefaults()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )

        viewModel.setMenuBarIconVisible(false)

        try expectFalse(viewModel.menuBarIconVisible)
        try expectFalse(ApplicationSettingsStore(userDefaults: defaults).menuBarIconVisible)
    }

    @MainActor
    static func testViewModelUpdatesOverlaySizeScale() throws {
        let defaults = makeDefaults()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )

        viewModel.setOverlaySizeScale(OverlaySizeScale(1.25))

        try expectEqual(viewModel.overlaySizeScale, OverlaySizeScale(1.25))
        try expectEqual(
            ApplicationSettingsStore(userDefaults: defaults).overlaySizeScale,
            OverlaySizeScale(1.25)
        )
    }

    @MainActor
    static func testViewModelHidesUpdateControlsWhenUnavailable() throws {
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: makeDefaults()),
            launchAtLoginService: FakeLaunchAtLoginService(),
            updateChecker: UnavailableUpdateController()
        )

        try expectFalse(viewModel.updateCheckingAvailable)
        try expectEqual(viewModel.currentVersionDisplay.isEmpty, false)
    }

    @MainActor
    static func testViewModelForwardsManualUpdateChecks() throws {
        let updateChecker = FakeUpdateChecker(isAvailable: true)
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: makeDefaults()),
            launchAtLoginService: FakeLaunchAtLoginService(),
            updateChecker: updateChecker
        )

        viewModel.checkForUpdates()

        try expectEqual(updateChecker.checkCount, 1)
    }

    @MainActor
    static func testViewModelUpdatesAutomaticCheckPreference() throws {
        let updateChecker = FakeUpdateChecker(isAvailable: true)
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: makeDefaults()),
            launchAtLoginService: FakeLaunchAtLoginService(),
            updateChecker: updateChecker
        )

        viewModel.setAutomaticallyChecksForUpdates(true)

        try expectTrue(viewModel.automaticallyChecksForUpdates)
        try expectTrue(updateChecker.automaticallyChecksForUpdates)
    }

    @MainActor
    static func testViewModelTogglesStartAtLogin() throws {
        let launchAtLoginService = FakeLaunchAtLoginService()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: makeDefaults()),
            launchAtLoginService: launchAtLoginService
        )

        viewModel.setStartsAtLogin(true)

        try expectTrue(viewModel.startsAtLogin)
        try expectEqual(launchAtLoginService.requestedValues, [true])
    }

    @MainActor
    static func testViewModelKeepsStartAtLoginStateWhenServiceFails() throws {
        let launchAtLoginService = FakeLaunchAtLoginService(shouldThrow: true)
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: makeDefaults()),
            launchAtLoginService: launchAtLoginService
        )

        viewModel.setStartsAtLogin(true)

        try expectFalse(viewModel.startsAtLogin)
        try expectEqual(viewModel.errorMessage, "Start at login could not be updated.")
    }

    static func testLaunchPolicyShowsSettingsWhenMenuBarIconIsHidden() throws {
        let permissionState = PermissionState(accessibility: .granted, screenRecording: .granted)

        try expectTrue(ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: false,
            permissionState: permissionState
        ))
        try expectFalse(ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: true,
            permissionState: permissionState
        ))
    }

    static func testLaunchPolicyShowsSettingsWhenAnyPermissionIsMissing() throws {
        try expectTrue(ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: true,
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted)
        ))
        try expectTrue(ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: true,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .missing)
        ))
        try expectFalse(ApplicationLaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            menuBarIconVisible: true,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        ))
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct ApplicationSettingsBridgePayload: Codable {
    let version: Int
    let configurations: [SwitcherShortcutConfiguration]
}

private final class NotificationRecorder: @unchecked Sendable {
    private(set) var postCount = 0

    var didPostNotification: Bool {
        postCount > 0
    }

    func record() {
        postCount += 1
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    private let shouldThrow: Bool
    private(set) var requestedValues: [Bool] = []
    var startsAtLogin = false

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func setStartsAtLogin(_ startsAtLogin: Bool) throws {
        requestedValues.append(startsAtLogin)
        if shouldThrow {
            throw TestFailure.failed("Launch at login failed")
        }

        self.startsAtLogin = startsAtLogin
    }
}

@MainActor
private final class FakeUpdateChecker: UpdateChecking {
    private let isAvailable: Bool
    private(set) var checkCount = 0
    var automaticallyChecksForUpdates = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isUpdateCheckingAvailable: Bool {
        isAvailable
    }

    var currentVersionDisplay: String {
        "1.0 (1)"
    }

    func checkForUpdates() {
        checkCount += 1
    }
}
