import Foundation
import SwitchTab

enum ApplicationSettingsStoreTests {
    @MainActor
    static func run() throws {
        try testMenuBarIconDefaultsToVisible()
        try testMenuBarIconVisibilityPersists()
        try testMenuBarIconVisibilityChangePostsNotification()
        try testMenuBarIconVisibilityNoOpDoesNotPostNotification()
        try testReplacesCommandTabDefaultsToDisabled()
        try testReplacesCommandTabPersists()
        try testReplacesCommandTabChangePostsExactlyOneNotification()
        try testReplacesCommandTabChangePostsDedicatedNotification()
        try testUnrelatedSettingsDoNotPostCmdTabReplacementNotification()
        try testReplacesCommandTabNoOpDoesNotPostNotification()
        try testOverlaySizeScaleDefaultsToOne()
        try testOverlaySizeScalePersists()
        try testOverlaySizeScaleNoOpDoesNotPostNotification()
        try testOverlaySizeScaleMigratesLegacyPreference()
        try testStoredScaleWinsOverLegacyPreference()
        try testViewModelTogglesMenuBarIconVisibility()
        try testViewModelInitializesFromStoredCmdTabReplacement()
        try testViewModelUpdatesCmdTabReplacement()
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

    static func testReplacesCommandTabDefaultsToDisabled() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())

        try expectFalse(store.replacesCommandTab)
    }

    static func testReplacesCommandTabPersists() throws {
        let defaults = makeDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)

        store.saveReplacesCommandTab(true)

        try expectTrue(ApplicationSettingsStore(userDefaults: defaults).replacesCommandTab)
    }

    static func testReplacesCommandTabChangePostsExactlyOneNotification() throws {
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

        store.saveReplacesCommandTab(true)

        try expectEqual(recorder.postCount, 1)
    }

    static func testReplacesCommandTabChangePostsDedicatedNotification() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .commandTabReplacementDidChange,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveReplacesCommandTab(true)
        store.saveReplacesCommandTab(true)

        try expectEqual(recorder.postCount, 1)
    }

    static func testUnrelatedSettingsDoNotPostCmdTabReplacementNotification() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())
        let recorder = NotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .commandTabReplacementDidChange,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveOverlaySizeScale(OverlaySizeScale(1.2))

        try expectEqual(recorder.postCount, 0)
    }

    static func testReplacesCommandTabNoOpDoesNotPostNotification() throws {
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

        store.saveReplacesCommandTab(false)

        try expectEqual(recorder.postCount, 0)
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
    static func testViewModelInitializesFromStoredCmdTabReplacement() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ApplicationSettingsStore.replacesCommandTabKey)
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )

        try expectTrue(viewModel.replacesCommandTab)
    }

    @MainActor
    static func testViewModelUpdatesCmdTabReplacement() throws {
        let defaults = makeDefaults()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )

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

        viewModel.setReplacesCommandTab(true)
        viewModel.setReplacesCommandTab(true)

        try expectTrue(viewModel.replacesCommandTab)
        try expectTrue(ApplicationSettingsStore(userDefaults: defaults).replacesCommandTab)
        try expectEqual(recorder.postCount, 1)
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
