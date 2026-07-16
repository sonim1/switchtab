import Foundation
import SwitchTab

enum ApplicationSettingsStoreTests {
    @MainActor
    static func run() throws {
        try testMenuBarIconDefaultsToVisible()
        try testMenuBarIconVisibilityPersists()
        try testMenuBarIconVisibilityChangePostsNotification()
        try testMenuBarIconVisibilityNoOpDoesNotPostNotification()
        try testOverlaySizeDefaultsToStandard()
        try testOverlaySizePersists()
        try testOverlaySizeNoOpDoesNotPostNotification()
        try testViewModelTogglesMenuBarIconVisibility()
        try testViewModelUpdatesOverlaySize()
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

    static func testOverlaySizeDefaultsToStandard() throws {
        let store = ApplicationSettingsStore(userDefaults: makeDefaults())

        try expectEqual(store.overlaySize, .standard)
    }

    static func testOverlaySizePersists() throws {
        let defaults = makeDefaults()
        let store = ApplicationSettingsStore(userDefaults: defaults)

        store.saveOverlaySize(.compact)

        try expectEqual(ApplicationSettingsStore(userDefaults: defaults).overlaySize, .compact)
    }

    static func testOverlaySizeNoOpDoesNotPostNotification() throws {
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

        store.saveOverlaySize(.standard)

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
    static func testViewModelUpdatesOverlaySize() throws {
        let defaults = makeDefaults()
        let viewModel = ApplicationSettingsViewModel(
            store: ApplicationSettingsStore(userDefaults: defaults),
            launchAtLoginService: FakeLaunchAtLoginService()
        )

        viewModel.setOverlaySize(.large)

        try expectEqual(viewModel.overlaySize, .large)
        try expectEqual(ApplicationSettingsStore(userDefaults: defaults).overlaySize, .large)
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
