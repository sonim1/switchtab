@testable import SwitchTab

enum ApplicationSwitchingTests {
    static func run() throws {
        try testDefaultApplicationSwitchingShortcutsAreFixed()
        try testControllerEnablesForwardAndReverseHandlersInOrder()
        try testControllerReenableUnregistersBeforeRegisteringAgain()
        try testControllerDisableDoesNotRegisterAndUnregistersEnabledRegistrations()
        try testControllerReverseFailureRollsBackForwardRegistration()
        try testControllerTeardownLeavesIndependentWindowServiceRegistered()
        try testProviderFiltersNonRegularTerminatedAndOwnBundleApplications()
        try testProviderUsesUnknownApplicationForMissingOrBlankNames()
        try testProviderDeduplicatesBundleIdentifiersUsingActiveRepresentative()
        try testProviderUsesDeterministicProcessScopedFallbackIdentifiers()
        try testProviderPreservesIncomingSnapshotOrder()
        try testProviderMapsApplicationIconsToProcessIdentifiers()
        try testActivationSuccessRecordsAndFlushesRecencyOnce()
        try testActivationFailureDoesNotRecordOrFlushRecency()
        try testWorkspaceActivationObserverRecordsExternalRegularActivation()
        try testWorkspaceActivationObserverRejectsOwnTerminatedAndNonRegularSnapshots()
        try testWorkspaceActivationObserverUsesProcessIdentifierFallback()
    }

    static func testDefaultApplicationSwitchingShortcutsAreFixed() throws {
        let forward = ShortcutSetting.defaultApplicationSwitching
        let reverse = ShortcutSetting.defaultApplicationSwitchingReverse

        try expectEqual(forward.id, "application-switching")
        try expectEqual(forward.mode, .applicationSwitching)
        try expectEqual(forward.keyEquivalent, "Tab")
        try expectEqual(forward.keyCode, 48)
        try expectEqual(forward.modifiers, ["command"])
        try expectTrue(forward.isUsable)
        try expectEqual(forward.displayText, "Cmd + Tab")

        try expectEqual(reverse.id, "application-switching-reverse")
        try expectEqual(reverse.mode, .applicationSwitching)
        try expectEqual(reverse.keyEquivalent, "Tab")
        try expectEqual(reverse.keyCode, 48)
        try expectEqual(reverse.modifiers, ["command", "shift"])
        try expectTrue(reverse.isUsable)
        try expectEqual(reverse.displayText, "Cmd + Shift + Tab")
        try expectTrue(forward.id != reverse.id)
    }

    static func testControllerEnablesForwardAndReverseHandlersInOrder() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )
        var forwardCount = 0
        var reverseCount = 0

        let didRegister = controller.updateRegistration(
            enabled: true,
            forwardHandler: { forwardCount += 1 },
            reverseHandler: { reverseCount += 1 }
        )

        try expectTrue(didRegister)
        try expectEqual(registrar.events, ["register-forward", "register-reverse"])
        try expectEqual(
            registrar.attemptedSettings,
            [.defaultApplicationSwitching, .defaultApplicationSwitchingReverse]
        )
        registrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitching.id)
        registrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitchingReverse.id)
        try expectEqual(forwardCount, 1)
        try expectEqual(reverseCount, 1)
        try expectEqual(controller.registrationMessageSnapshot(), [])
    }

    static func testControllerReenableUnregistersBeforeRegisteringAgain() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )

        try expectTrue(controller.updateRegistration(enabled: true, forwardHandler: {}, reverseHandler: {}))
        registrar.events.removeAll()

        try expectTrue(controller.updateRegistration(enabled: true, forwardHandler: {}, reverseHandler: {}))

        try expectEqual(registrar.events, ["unregister", "register-forward", "register-reverse"])
    }

    static func testControllerDisableDoesNotRegisterAndUnregistersEnabledRegistrations() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )

        try expectTrue(controller.updateRegistration(enabled: false, forwardHandler: {}, reverseHandler: {}))
        try expectEqual(registrar.events, [])

        try expectTrue(controller.updateRegistration(enabled: true, forwardHandler: {}, reverseHandler: {}))
        registrar.events.removeAll()

        try expectTrue(controller.updateRegistration(enabled: false, forwardHandler: {}, reverseHandler: {}))

        try expectEqual(registrar.events, ["unregister"])
        try expectEqual(controller.registrationMessageSnapshot(), [])
    }

    static func testControllerReverseFailureRollsBackForwardRegistration() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar { setting in
            setting.id == ShortcutSetting.defaultApplicationSwitching.id
        }
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )
        var forwardCount = 0

        let didRegister = controller.updateRegistration(
            enabled: true,
            forwardHandler: { forwardCount += 1 },
            reverseHandler: {}
        )

        try expectFalse(didRegister)
        try expectEqual(registrar.events, ["register-forward", "register-reverse", "unregister"])
        registrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitching.id)
        try expectEqual(forwardCount, 0)
        try expectEqual(
            controller.registrationMessageSnapshot(),
            [
                ShortcutRegistrationMessage(
                    mode: .applicationSwitching,
                    message: ApplicationSwitchingHotkeyController.registrationFailureMessage
                )
            ]
        )
    }

    static func testControllerTeardownLeavesIndependentWindowServiceRegistered() throws {
        let windowRegistrar = ApplicationSwitchingRecordingRegistrar()
        let windowService = HotkeyService(registrar: windowRegistrar)
        var invocationCount = 0
        _ = windowService.register(
            setting: .defaultCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            invocationCount += 1
        }

        var controller: ApplicationSwitchingHotkeyController? = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: ApplicationSwitchingRecordingRegistrar())
        )
        _ = controller?.updateRegistration(enabled: true, forwardHandler: {}, reverseHandler: {})
        controller = nil

        windowRegistrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        try expectEqual(invocationCount, 1)
        try expectEqual(windowRegistrar.unregisterAllCallCount, 0)
    }

    static func testProviderFiltersNonRegularTerminatedAndOwnBundleApplications() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 10,
                    bundleIdentifier: "com.apple.finder",
                    localizedName: "Finder",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 11,
                    bundleIdentifier: "com.example.helper",
                    localizedName: "Helper",
                    isRegular: false,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 12,
                    bundleIdentifier: "com.example.terminated",
                    localizedName: "Terminated",
                    isRegular: true,
                    isTerminated: true,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 13,
                    bundleIdentifier: "com.royjen.switchtab",
                    localizedName: "SwitchTab",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        try expectEqual(provider.runningApplications().map(\.id), ["com.apple.finder"])
    }

    static func testProviderUsesUnknownApplicationForMissingOrBlankNames() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 20,
                    bundleIdentifier: "com.example.missing-name",
                    localizedName: nil,
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 21,
                    bundleIdentifier: "com.example.blank-name",
                    localizedName: " \t ",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        try expectEqual(
            provider.runningApplications().map(\.switcherListItem.title),
            ["Unknown Application", "Unknown Application"]
        )
    }

    static func testProviderDeduplicatesBundleIdentifiersUsingActiveRepresentative() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 30,
                    bundleIdentifier: "com.example.shared",
                    localizedName: "First",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 32,
                    bundleIdentifier: "com.example.other",
                    localizedName: "Other",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 31,
                    bundleIdentifier: "com.example.shared",
                    localizedName: "Active Duplicate",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.id), ["com.example.shared", "com.example.other"])
        try expectEqual(applications.map(\.processIdentifier), [31, 32])
        try expectEqual(applications.map(\.switcherListItem.title), ["Active Duplicate", "Other"])
        try expectEqual(applications.map(\.bundleIdentifier), ["com.example.shared", "com.example.other"])
        try expectEqual(applications.map(\.isActive), [true, false])
    }

    static func testProviderUsesDeterministicProcessScopedFallbackIdentifiers() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 40,
                    bundleIdentifier: nil,
                    localizedName: "First",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 41,
                    bundleIdentifier: "",
                    localizedName: "Second",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 40,
                    bundleIdentifier: nil,
                    localizedName: "Duplicate PID",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.id), ["pid:40", "pid:41"])
        try expectEqual(applications.map(\.processIdentifier), [40, 41])
        try expectEqual(applications.map(\.switcherListItem.title), ["First", "Second"])
        try expectEqual(applications.map(\.isActive), [false, false])
    }

    static func testProviderPreservesIncomingSnapshotOrder() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 50,
                    bundleIdentifier: "com.example.safari",
                    localizedName: "Safari",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 51,
                    bundleIdentifier: "com.example.finder",
                    localizedName: "Finder",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 52,
                    bundleIdentifier: "com.example.notes",
                    localizedName: "Notes",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.switcherListItem.title), ["Safari", "Finder", "Notes"])
        try expectEqual(
            applications.map(\.bundleIdentifier),
            ["com.example.safari", "com.example.finder", "com.example.notes"]
        )
        try expectEqual(applications.map(\.isActive), [false, true, false])
    }

    static func testProviderMapsApplicationIconsToProcessIdentifiers() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 60,
                    bundleIdentifier: "com.example.one",
                    localizedName: "One",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 61,
                    bundleIdentifier: "com.example.two",
                    localizedName: "Two",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(
            applications.map(\.switcherListItem.appIconProcessIdentifier),
            [60, 61]
        )
        try expectEqual(applications.map { $0.switcherListItem.id }, applications.map(\.id))
    }

    static func testActivationSuccessRecordsAndFlushesRecencyOnce() throws {
        let sequence = RecordingApplicationSequence()
        let activator = FakeApplicationActivator(result: true, sequence: sequence)
        let activationService = ApplicationActivationService(activator: activator)
        let recencyStore = RecordingApplicationSelectionRecencyStore(sequence: sequence)
        let coordinator = ApplicationSelectionCoordinator(
            activationService: activationService,
            recencyStore: recencyStore
        )
        let application = makeApplication(id: "com.example.notes", processIdentifier: 101)

        let result = coordinator.confirm(application)

        try expectEqual(result, .activated)
        try expectEqual(activator.processIdentifiers, [101])
        try expectEqual(recencyStore.recordedIDs, [application.id])
        try expectEqual(recencyStore.flushCount, 1)
        try expectEqual(
            sequence.events,
            ["activate:101", "record:\(application.id)", "flush"]
        )
    }

    static func testActivationFailureDoesNotRecordOrFlushRecency() throws {
        let sequence = RecordingApplicationSequence()
        let activator = FakeApplicationActivator(result: false, sequence: sequence)
        let activationService = ApplicationActivationService(activator: activator)
        let recencyStore = RecordingApplicationSelectionRecencyStore(sequence: sequence)
        let coordinator = ApplicationSelectionCoordinator(
            activationService: activationService,
            recencyStore: recencyStore
        )
        let application = makeApplication(id: "com.example.safari", processIdentifier: 202)

        let result = coordinator.confirm(application)

        try expectEqual(result, .unavailableTarget)
        try expectEqual(activator.processIdentifiers, [202])
        try expectEqual(recencyStore.recordedIDs, [])
        try expectEqual(recencyStore.flushCount, 0)
        try expectEqual(sequence.events, ["activate:202"])
    }

    static func testWorkspaceActivationObserverRecordsExternalRegularActivation() throws {
        let sequence = RecordingApplicationSequence()
        let recencyStore = RecordingApplicationSelectionRecencyStore(sequence: sequence)
        let observer = WorkspaceActivationRecencyObserver(
            recencyStore: recencyStore,
            ownBundleIdentifier: "com.example.switchtab"
        )
        let snapshot = RunningApplicationSnapshot(
            processIdentifier: 303,
            bundleIdentifier: " com.example.notes ",
            localizedName: "Notes",
            isRegular: true,
            isTerminated: false,
            isActive: true
        )

        observer.recordActivation(snapshot)

        try expectEqual(recencyStore.recordedIDs, ["com.example.notes"])
        try expectEqual(recencyStore.flushCount, 1)
        try expectEqual(sequence.events, ["record:com.example.notes", "flush"])
    }

    static func testWorkspaceActivationObserverRejectsOwnTerminatedAndNonRegularSnapshots() throws {
        let sequence = RecordingApplicationSequence()
        let recencyStore = RecordingApplicationSelectionRecencyStore(sequence: sequence)
        let observer = WorkspaceActivationRecencyObserver(
            recencyStore: recencyStore,
            ownBundleIdentifier: " com.example.switchtab "
        )
        let snapshots = [
            RunningApplicationSnapshot(
                processIdentifier: 304,
                bundleIdentifier: "com.example.switchtab",
                localizedName: "SwitchTab",
                isRegular: true,
                isTerminated: false,
                isActive: true
            ),
            RunningApplicationSnapshot(
                processIdentifier: 305,
                bundleIdentifier: "com.example.terminated",
                localizedName: "Terminated",
                isRegular: true,
                isTerminated: true,
                isActive: false
            ),
            RunningApplicationSnapshot(
                processIdentifier: 306,
                bundleIdentifier: "com.example.helper",
                localizedName: "Helper",
                isRegular: false,
                isTerminated: false,
                isActive: false
            )
        ]

        for snapshot in snapshots {
            observer.recordActivation(snapshot)
        }

        try expectEqual(recencyStore.recordedIDs, [])
        try expectEqual(recencyStore.flushCount, 0)
        try expectEqual(sequence.events, [])
    }

    static func testWorkspaceActivationObserverUsesProcessIdentifierFallback() throws {
        let sequence = RecordingApplicationSequence()
        let recencyStore = RecordingApplicationSelectionRecencyStore(sequence: sequence)
        let observer = WorkspaceActivationRecencyObserver(
            recencyStore: recencyStore,
            ownBundleIdentifier: "com.example.switchtab"
        )
        let snapshot = RunningApplicationSnapshot(
            processIdentifier: 307,
            bundleIdentifier: "  ",
            localizedName: "Unknown",
            isRegular: true,
            isTerminated: false,
            isActive: true
        )

        observer.recordActivation(snapshot)

        try expectEqual(recencyStore.recordedIDs, ["pid:307"])
        try expectEqual(recencyStore.flushCount, 1)
        try expectEqual(sequence.events, ["record:pid:307", "flush"])
    }

    private static func makeApplication(id: String, processIdentifier: Int) -> ApplicationItem {
        ApplicationItem(
            id: id,
            processIdentifier: processIdentifier,
            bundleIdentifier: id,
            isActive: false,
            switcherListItem: SwitcherListItem(
                id: id,
                title: id,
                subtitle: nil,
                symbolName: "app",
                appIconProcessIdentifier: processIdentifier
            )
        )
    }
}

private struct FakeRunningApplicationSnapshotProvider: RunningApplicationSnapshotProviding {
    let snapshotValues: [RunningApplicationSnapshot]

    init(snapshots: [RunningApplicationSnapshot]) {
        self.snapshotValues = snapshots
    }

    func snapshots() -> [RunningApplicationSnapshot] {
        snapshotValues
    }
}

private final class RecordingApplicationSequence {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private final class FakeApplicationActivator: ApplicationActivating {
    let result: Bool
    let sequence: RecordingApplicationSequence
    private(set) var processIdentifiers: [Int] = []

    init(result: Bool, sequence: RecordingApplicationSequence) {
        self.result = result
        self.sequence = sequence
    }

    func activate(processIdentifier: Int) -> Bool {
        processIdentifiers.append(processIdentifier)
        sequence.append("activate:\(processIdentifier)")
        return result
    }
}

private final class RecordingApplicationSelectionRecencyStore: ApplicationSelectionRecencyRecording {
    let sequence: RecordingApplicationSequence
    private(set) var recordedIDs: [String] = []
    private(set) var flushCount = 0

    init(sequence: RecordingApplicationSequence) {
        self.sequence = sequence
    }

    func recordSelection(id: String) {
        recordedIDs.append(id)
        sequence.append("record:\(id)")
    }

    func flush() {
        flushCount += 1
        sequence.append("flush")
    }
}

private final class ApplicationSwitchingRecordingRegistrar: HotkeyRegistering {
    private let shouldRegister: (ShortcutSetting) -> Bool
    private(set) var attemptedSettings: [ShortcutSetting] = []
    var events: [String] = []
    private(set) var unregisterAllCallCount = 0
    private var handlers: [String: () -> Void] = [:]

    init(shouldRegister: @escaping (ShortcutSetting) -> Bool = { _ in true }) {
        self.shouldRegister = shouldRegister
    }

    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        attemptedSettings.append(setting)
        events.append(
            setting.id == ShortcutSetting.defaultApplicationSwitching.id
                ? "register-forward"
                : "register-reverse"
        )
        guard shouldRegister(setting) else {
            return false
        }

        handlers[setting.id] = handler
        return true
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
        events.append("unregister")
        handlers.removeAll(keepingCapacity: true)
    }

    func invoke(settingID: String) {
        handlers[settingID]?()
    }
}
