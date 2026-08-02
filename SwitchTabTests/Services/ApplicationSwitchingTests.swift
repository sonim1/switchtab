import Foundation
@testable import SwitchTab

@MainActor
enum ApplicationSwitchingTests {
    static func run() throws {
        try testDefaultApplicationSwitchingShortcutsAreFixed()
        try testControllerRegistersCustomApplicationShortcutAndReverseHandlers()
        try testControllerEnablesForwardAndReverseHandlersInOrder()
        try testControllerReenableUnregistersBeforeRegisteringAgain()
        try testControllerDisableDoesNotRegisterAndUnregistersEnabledRegistrations()
        try testControllerReverseFailureRollsBackForwardRegistration()
        try testControllerTeardownLeavesIndependentWindowServiceRegistered()
        try testApplicationEnabledChangesLeaveWindowRegistrationsLive()
        try testWindowEnabledChangesLeaveApplicationRegistrationsLive()
        try testApplicationEnabledFailurePersistsWithoutWindowMutation()
        try testApplicationEnableRejectsLiveWindowFallbackConflict()
        try testApplicationShortcutTransactionDefersRestoreWhileRecording()
        try testRecordingLifecycleSuspendsBothAndRestoresOnlyEnabledModes()
        try testApplicationPresentationAppliesMRUThenPinsActiveApplication()
        try testSelectionPolicyUsesMRUFirstWhenNoApplicationIsActive()
        try testSelectionPolicySkipsPinnedActiveApplicationForward()
        try testProviderFiltersNonRegularTerminatedAndOwnBundleApplications()
        try testProviderUsesUnknownApplicationForMissingOrBlankNames()
        try testProviderDeduplicatesBundleIdentifiersUsingActiveRepresentative()
        try testProviderUsesDeterministicProcessScopedFallbackIdentifiers()
        try testProviderPreservesIncomingSnapshotOrder()
        try testProviderMapsApplicationIconsToProcessIdentifiers()
        try testApplicationWindowCountPreservesMetadataAndStoresNumericSubtitle()
        try testApplicationUnknownWindowCountPreservesMetadataAndClearsSubtitle()
        try testApplicationPresentationMapsKnownZeroAndUnknownWindowCounts()
        try testWindowCountLoaderDefersWorkFromCaller()
        try testTerminationServiceReportsAcceptedAndRejectedRequests()
        try testTerminationIdentityUsesStableBundleOrProcessIdentifier()
        try testTerminationIdentityRejectsNonRegularOrUnterminatedSnapshots()
        try testSystemActivatorUsesFrontmostApplicationAsActivationSource()
        try testSystemActivatorRejectsTerminatedTargetBeforeActivation()
        try testSystemActivatorRejectsMissingTarget()
        try testSystemActivatorFallsBackWhenFrontmostApplicationIsMissing()
        try testSystemActivatorReturnsCoordinatedActivationFailure()
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

    static func testControllerRegistersCustomApplicationShortcutAndReverseHandlers() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )
        let setting = ShortcutSetting(
            id: "custom-application-switching",
            mode: .applicationSwitching,
            keyEquivalent: "Space",
            keyCode: 49,
            modifiers: ["option"],
            isUsable: true
        )
        let reverse = setting.reverseVariant(id: "application-switching-reverse")
        var forwardCount = 0
        var reverseCount = 0

        let didRegister = controller.updateRegistration(
            setting: setting,
            enabled: true,
            forwardHandler: { forwardCount += 1 },
            reverseHandler: { reverseCount += 1 }
        )

        try expectTrue(didRegister)
        try expectEqual(registrar.events, ["register-forward", "register-reverse"])
        try expectEqual(registrar.attemptedSettings, [setting, reverse])

        registrar.invoke(settingID: setting.id)
        try expectEqual(forwardCount, 1)
        try expectEqual(reverseCount, 0)

        registrar.invoke(settingID: reverse.id)
        try expectEqual(forwardCount, 1)
        try expectEqual(reverseCount, 1)
    }

    static func testControllerEnablesForwardAndReverseHandlersInOrder() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )
        var forwardCount = 0
        var reverseCount = 0

        let didRegister = controller.updateRegistration(
            setting: .defaultApplicationSwitching,
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
        try expectEqual(forwardCount, 1)
        try expectEqual(reverseCount, 0)

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

        try expectTrue(controller.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: true,
            forwardHandler: {},
            reverseHandler: {}
        ))
        registrar.events.removeAll()

        try expectTrue(controller.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: true,
            forwardHandler: {},
            reverseHandler: {}
        ))

        try expectEqual(registrar.events, ["unregister", "register-forward", "register-reverse"])
    }

    static func testControllerDisableDoesNotRegisterAndUnregistersEnabledRegistrations() throws {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )

        try expectTrue(controller.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: false,
            forwardHandler: {},
            reverseHandler: {}
        ))
        try expectEqual(registrar.events, [])

        try expectTrue(controller.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: true,
            forwardHandler: {},
            reverseHandler: {}
        ))
        registrar.events.removeAll()

        try expectTrue(controller.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: false,
            forwardHandler: {},
            reverseHandler: {}
        ))

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
            setting: .defaultApplicationSwitching,
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
        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar()
        var invocationCount = 0
        _ = windowService.register(
            setting: .defaultCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            invocationCount += 1
        }

        var controller: ApplicationSwitchingHotkeyController? = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: applicationRegistrar)
        )
        _ = controller?.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: true,
            forwardHandler: {},
            reverseHandler: {}
        )
        controller?.unregisterAll()
        controller = nil

        try expectEqual(applicationRegistrar.unregisterAllCallCount, 1)
        windowRegistrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        try expectEqual(invocationCount, 1)
        try expectEqual(windowRegistrar.unregisterAllCallCount, 0)
    }

    static func testApplicationEnabledChangesLeaveWindowRegistrationsLive() throws {
        let windowRegistrar = ApplicationSwitchingRecordingRegistrar()
        let windowHotkeyService = HotkeyService(registrar: windowRegistrar)
        var windowInvocationCount = 0
        let windowForward = ShortcutSetting.defaultCurrentAppWindowSwitching
        let windowReverse = windowForward.reverseVariant(
            id: "current-app-window-switching-reverse"
        )
        _ = windowHotkeyService.register(
            setting: windowForward,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            windowInvocationCount += 1
        }
        _ = windowHotkeyService.register(
            setting: windowReverse,
            existing: [windowForward],
            mode: .currentAppWindowSwitching
        ) {
            windowInvocationCount += 1
        }

        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar()
        let applicationController = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: applicationRegistrar)
        )
        var windowRegisterCount = 0
        var persistedMessageSnapshots: [[ShortcutRegistrationMessage]] = []
        let lifecycle = ShortcutEnabledLifecycle(
            windowHotkeyService: windowHotkeyService,
            registerWindowHotkeys: { _ in
                windowRegisterCount += 1
                return true
            },
            updateApplicationHotkeyRegistration: { configuration in
                applicationController.updateRegistration(
                    setting: configuration.shortcut,
                    enabled: configuration.isEnabled,
                    forwardHandler: {},
                    reverseHandler: {}
                )
            },
            dismissWindowOverlayIfActive: {},
            persistRegistrationMessages: {
                persistedMessageSnapshots.append(
                    windowHotkeyService.registrationMessageSnapshot()
                        + applicationController.registrationMessageSnapshot()
                )
            }
        )
        let enabledApplication = SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: true,
            shortcut: .defaultApplicationSwitching
        )

        lifecycle.apply(configuration: enabledApplication)
        windowRegistrar.invoke(settingID: windowForward.id)
        lifecycle.apply(configuration: SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: false,
            shortcut: .defaultApplicationSwitching
        ))
        windowRegistrar.invoke(settingID: windowReverse.id)

        try expectEqual(windowRegisterCount, 0)
        try expectEqual(windowRegistrar.unregisterAllCallCount, 0)
        try expectEqual(windowInvocationCount, 2)
        try expectEqual(
            windowHotkeyService.registeredSettings(for: .currentAppWindowSwitching),
            [windowForward, windowReverse]
        )
        try expectEqual(
            applicationRegistrar.events,
            ["register-forward", "register-reverse", "unregister"]
        )
        try expectEqual(persistedMessageSnapshots.count, 2)
    }

    static func testWindowEnabledChangesLeaveApplicationRegistrationsLive() throws {
        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar()
        let applicationHotkeyService = HotkeyService(registrar: applicationRegistrar)
        let applicationController = ApplicationSwitchingHotkeyController(
            hotkeyService: applicationHotkeyService
        )
        var applicationInvocationCount = 0
        _ = applicationController.updateRegistration(
            setting: .defaultApplicationSwitching,
            enabled: true,
            forwardHandler: { applicationInvocationCount += 1 },
            reverseHandler: { applicationInvocationCount += 1 }
        )
        applicationRegistrar.events.removeAll()

        let windowRegistrar = ApplicationSwitchingRecordingRegistrar()
        let windowHotkeyService = HotkeyService(registrar: windowRegistrar)
        var applicationUpdateCount = 0
        var dismissWindowOverlayCount = 0
        var persistCount = 0
        let lifecycle = ShortcutEnabledLifecycle(
            windowHotkeyService: windowHotkeyService,
            registerWindowHotkeys: { setting in
                windowHotkeyService.unregisterAll()
                let reverse = setting.reverseVariant(
                    id: "current-app-window-switching-reverse"
                )
                let forwardResult = windowHotkeyService.register(
                    setting: setting,
                    existing: [] as [ShortcutSetting],
                    mode: .currentAppWindowSwitching,
                    handler: {}
                )
                let reverseResult = windowHotkeyService.register(
                    setting: reverse,
                    existing: [setting],
                    mode: .currentAppWindowSwitching,
                    handler: {}
                )
                return forwardResult == .registered && reverseResult == .registered
            },
            updateApplicationHotkeyRegistration: { _ in
                applicationUpdateCount += 1
                return true
            },
            dismissWindowOverlayIfActive: {
                dismissWindowOverlayCount += 1
            },
            persistRegistrationMessages: {
                persistCount += 1
            }
        )
        let enabledWindow = SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: true,
            shortcut: .defaultCurrentAppWindowSwitching
        )

        lifecycle.apply(configuration: enabledWindow)
        applicationRegistrar.invoke(
            settingID: ShortcutSetting.defaultApplicationSwitching.id
        )
        lifecycle.apply(configuration: SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: false,
            shortcut: .defaultCurrentAppWindowSwitching
        ))
        applicationRegistrar.invoke(
            settingID: ShortcutSetting.defaultApplicationSwitchingReverse.id
        )

        try expectEqual(applicationRegistrar.events, [])
        try expectEqual(applicationRegistrar.unregisterAllCallCount, 0)
        try expectEqual(applicationUpdateCount, 0)
        try expectEqual(applicationInvocationCount, 2)
        try expectEqual(
            applicationHotkeyService.registeredSettings(for: .applicationSwitching),
            [
                .defaultApplicationSwitching,
                .defaultApplicationSwitchingReverse
            ]
        )
        try expectEqual(
            windowRegistrar.events,
            ["register-forward", "register-reverse", "unregister"]
        )
        try expectEqual(dismissWindowOverlayCount, 1)
        try expectEqual(persistCount, 2)
    }

    static func testApplicationEnabledFailurePersistsWithoutWindowMutation() throws {
        let windowRegistrar = ApplicationSwitchingRecordingRegistrar()
        let windowHotkeyService = HotkeyService(registrar: windowRegistrar)
        let windowForward = ShortcutSetting.defaultCurrentAppWindowSwitching
        let windowReverse = windowForward.reverseVariant(
            id: "current-app-window-switching-reverse"
        )
        _ = windowHotkeyService.register(
            setting: windowForward,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching,
            handler: {}
        )
        _ = windowHotkeyService.register(
            setting: windowReverse,
            existing: [windowForward],
            mode: .currentAppWindowSwitching,
            handler: {}
        )

        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar { setting in
            setting.id == ShortcutSetting.defaultApplicationSwitching.id
        }
        let applicationController = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: applicationRegistrar)
        )
        var windowRegisterCount = 0
        var persistedMessageSnapshots: [[ShortcutRegistrationMessage]] = []
        let lifecycle = ShortcutEnabledLifecycle(
            windowHotkeyService: windowHotkeyService,
            registerWindowHotkeys: { _ in
                windowRegisterCount += 1
                return true
            },
            updateApplicationHotkeyRegistration: { configuration in
                applicationController.updateRegistration(
                    setting: configuration.shortcut,
                    enabled: configuration.isEnabled,
                    forwardHandler: {},
                    reverseHandler: {}
                )
            },
            dismissWindowOverlayIfActive: {},
            persistRegistrationMessages: {
                persistedMessageSnapshots.append(
                    windowHotkeyService.registrationMessageSnapshot()
                        + applicationController.registrationMessageSnapshot()
                )
            }
        )

        lifecycle.apply(configuration: SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: true,
            shortcut: .defaultApplicationSwitching
        ))

        try expectEqual(windowRegisterCount, 0)
        try expectEqual(windowRegistrar.unregisterAllCallCount, 0)
        try expectEqual(
            windowHotkeyService.registeredSettings(for: .currentAppWindowSwitching),
            [windowForward, windowReverse]
        )
        try expectEqual(
            applicationRegistrar.events,
            ["register-forward", "register-reverse", "unregister"]
        )
        try expectEqual(
            persistedMessageSnapshots,
            [[
                ShortcutRegistrationMessage(
                    mode: .applicationSwitching,
                    message: ApplicationSwitchingHotkeyController.registrationFailureMessage
                )
            ]]
        )
    }

    static func testApplicationEnableRejectsLiveWindowFallbackConflict() throws {
        let windowRegistrar = ApplicationSwitchingRecordingRegistrar { setting in
            !setting.modifiers.contains("command")
        }
        let windowHotkeyService = HotkeyService(registrar: windowRegistrar)
        var windowInvocationCount = 0
        let configuredWindowForward = ShortcutSetting.defaultCurrentAppWindowSwitching
        let configuredWindowReverse = configuredWindowForward.reverseVariant(
            id: "current-app-window-switching-reverse"
        )
        _ = windowHotkeyService.registerFirstUsable(
            primaryCandidate: configuredWindowForward,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            windowInvocationCount += 1
        }
        _ = windowHotkeyService.registerFirstUsable(
            primaryCandidate: configuredWindowReverse,
            fallbackCandidate: .fallbackCurrentAppWindowSwitchingReverse,
            existing: [configuredWindowForward],
            mode: .currentAppWindowSwitching
        ) {
            windowInvocationCount += 1
        }
        let liveWindowSettings = windowHotkeyService.registeredSettings(
            for: .currentAppWindowSwitching
        )
        try expectEqual(
            liveWindowSettings,
            [
                .fallbackCurrentAppWindowSwitching,
                .fallbackCurrentAppWindowSwitchingReverse
            ]
        )

        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar()
        let applicationController = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: applicationRegistrar)
        )
        let conflictingApplicationShortcut = ShortcutSetting(
            id: "application-switching",
            mode: .applicationSwitching,
            keyEquivalent: "`",
            keyCode: 50,
            modifiers: ["option", "control"],
            isUsable: true
        )
        var persistedMessageSnapshots: [[ShortcutRegistrationMessage]] = []
        let lifecycle = ShortcutEnabledLifecycle(
            windowHotkeyService: windowHotkeyService,
            registerWindowHotkeys: { _ in false },
            updateApplicationHotkeyRegistration: { configuration in
                applicationController.updateRegistration(
                    setting: configuration.shortcut,
                    enabled: configuration.isEnabled,
                    existing: windowHotkeyService.registeredSettings(
                        for: .currentAppWindowSwitching
                    ),
                    forwardHandler: {},
                    reverseHandler: {}
                )
            },
            dismissWindowOverlayIfActive: {},
            persistRegistrationMessages: {
                persistedMessageSnapshots.append(
                    windowHotkeyService.registrationMessageSnapshot()
                        + applicationController.registrationMessageSnapshot()
                )
            }
        )

        lifecycle.apply(configuration: SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: true,
            shortcut: conflictingApplicationShortcut
        ))
        windowRegistrar.invoke(
            settingID: ShortcutSetting.fallbackCurrentAppWindowSwitching.id
        )
        windowRegistrar.invoke(
            settingID: ShortcutSetting.fallbackCurrentAppWindowSwitchingReverse.id
        )

        try expectEqual(windowRegistrar.unregisterAllCallCount, 0)
        try expectEqual(windowInvocationCount, 2)
        try expectEqual(
            windowHotkeyService.registeredSettings(for: .currentAppWindowSwitching),
            liveWindowSettings
        )
        try expectEqual(applicationRegistrar.events, [])
        try expectEqual(
            persistedMessageSnapshots.last?.last,
            ShortcutRegistrationMessage(
                mode: .applicationSwitching,
                message: ApplicationSwitchingHotkeyController.registrationFailureMessage
            )
        )
    }

    static func testApplicationShortcutTransactionDefersRestoreWhileRecording() throws {
        var events: [String] = []
        let transaction = ApplicationShortcutLifecycleTransaction(
            previousWindowSnapshot: HotkeyRegistrationSnapshot(
                mode: .currentAppWindowSwitching,
                expectedEnabled: true,
                settings: [],
                registrationMessages: []
            ),
            suspendWindow: { events.append("suspend-window") },
            registerApplicationCandidate: {
                events.append("register-application")
                return false
            },
            registerWindowWithCandidateConflicts: {
                events.append("register-window")
                return true
            },
            restorePreviousApplication: {
                events.append("restore-application")
                return true
            },
            restorePreviousWindow: { _ in
                events.append("restore-window")
                return true
            },
            deferredRestoration: {
                events.append("defer-restoration")
            }
        )

        try expectEqual(transaction.apply(), .rejectedRestorationDeferred)
        try expectEqual(
            events,
            [
                "suspend-window",
                "register-application",
                "defer-restoration"
            ]
        )
    }

    static func testRecordingLifecycleSuspendsBothAndRestoresOnlyEnabledModes() throws {
        let windowRegistrar = ApplicationSwitchingRecordingRegistrar()
        let windowHotkeyService = HotkeyService(registrar: windowRegistrar)
        let applicationRegistrar = ApplicationSwitchingRecordingRegistrar()
        let applicationController = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: applicationRegistrar)
        )
        var windowInvocationCount = 0
        var applicationInvocationCount = 0
        var persistCount = 0
        let lifecycle = ShortcutRecordingHotkeyLifecycle(
            windowHotkeyService: windowHotkeyService,
            applicationHotkeyController: applicationController,
            registerWindowHotkeys: { setting, _ in
                let reverse = setting.reverseVariant(
                    id: "current-app-window-switching-reverse"
                )
                let forwardResult = windowHotkeyService.register(
                    setting: setting,
                    existing: [] as [ShortcutSetting],
                    mode: .currentAppWindowSwitching
                ) {
                    windowInvocationCount += 1
                }
                let reverseResult = windowHotkeyService.register(
                    setting: reverse,
                    existing: [setting],
                    mode: .currentAppWindowSwitching
                ) {
                    windowInvocationCount += 1
                }
                return forwardResult == .registered && reverseResult == .registered
            },
            updateApplicationHotkeyRegistration: { configuration in
                applicationController.updateRegistration(
                    setting: configuration.shortcut,
                    enabled: configuration.isEnabled,
                    forwardHandler: { applicationInvocationCount += 1 },
                    reverseHandler: { applicationInvocationCount += 1 }
                )
            },
            dismissWindowOverlayIfActive: {},
            persistRegistrationMessages: { persistCount += 1 }
        )
        let windowEnabledOnly = [
            SwitcherShortcutConfiguration.defaultCurrentAppWindows,
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: false,
                shortcut: .defaultApplicationSwitching
            )
        ]
        let applicationEnabledOnly = [
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: false,
                shortcut: .defaultCurrentAppWindowSwitching
            ),
            SwitcherShortcutConfiguration.defaultApplicationSwitching
        ]
        let bothEnabled = [
            SwitcherShortcutConfiguration.defaultCurrentAppWindows,
            SwitcherShortcutConfiguration.defaultApplicationSwitching
        ]

        lifecycle.end(configurations: bothEnabled)
        windowRegistrar.events.removeAll()
        applicationRegistrar.events.removeAll()

        lifecycle.begin()
        lifecycle.applicationDidBecomeActive(configurations: bothEnabled)
        windowRegistrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        applicationRegistrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitching.id)
        try expectEqual(windowInvocationCount, 0)
        try expectEqual(applicationInvocationCount, 0)
        try expectEqual(windowRegistrar.events, ["unregister"])
        try expectEqual(applicationRegistrar.events, ["unregister"])

        windowRegistrar.events.removeAll()
        applicationRegistrar.events.removeAll()
        lifecycle.end(configurations: windowEnabledOnly)
        windowRegistrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        applicationRegistrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitching.id)
        try expectEqual(windowInvocationCount, 1)
        try expectEqual(applicationInvocationCount, 0)
        try expectEqual(windowRegistrar.events, ["register-forward", "register-reverse"])
        try expectEqual(applicationRegistrar.events, [])

        lifecycle.begin()
        windowRegistrar.events.removeAll()
        applicationRegistrar.events.removeAll()
        lifecycle.end(configurations: applicationEnabledOnly)
        windowRegistrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        applicationRegistrar.invoke(settingID: ShortcutSetting.defaultApplicationSwitching.id)
        try expectEqual(windowInvocationCount, 1)
        try expectEqual(applicationInvocationCount, 1)
        try expectEqual(windowRegistrar.events, [])
        try expectEqual(applicationRegistrar.events, ["register-forward", "register-reverse"])
        try expectEqual(persistCount, 5)
    }

    static func testApplicationPresentationAppliesMRUThenPinsActiveApplication() throws {
        let suiteName = "ApplicationSwitchingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure.failed("Could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recencyStore = SwitcherRecencyStore(
            userDefaults: defaults,
            mode: .applicationSwitching
        )
        recencyStore.recordSelection(id: "safari")
        recencyStore.recordSelection(id: "notes")
        let applications = [
            makeApplication(id: "finder", processIdentifier: 1, isActive: true),
            makeApplication(id: "safari", processIdentifier: 2),
            makeApplication(id: "notes", processIdentifier: 3)
        ]

        let recentlyOrdered = recencyStore.order(applications) { $0.id }
        let ordered = SwitcherWindowOrderPolicy.pinningFocusedWindowFirst(recentlyOrdered) {
            $0.isActive
        }
        let forward = SwitcherPresentationSnapshot(
            elements: ordered,
            reverse: false
        ) { $0.switcherListItem }
        let reverse = SwitcherPresentationSnapshot(
            elements: ordered,
            reverse: true
        ) { $0.switcherListItem }

        try expectEqual(ordered.map(\.id), ["finder", "notes", "safari"])
        try expectEqual(forward.element(at: forward.selectedIndex)?.id, "notes")
        try expectEqual(reverse.element(at: reverse.selectedIndex)?.id, "safari")
    }

    static func testSelectionPolicyUsesMRUFirstWhenNoApplicationIsActive() throws {
        let applications = [
            makeApplication(id: "notes", processIdentifier: 1),
            makeApplication(id: "safari", processIdentifier: 2)
        ]

        try expectEqual(
            ApplicationSwitcherSelectionPolicy.initialSelectedIndex(
                applications: applications,
                reverse: false
            ),
            0
        )
        try expectEqual(
            ApplicationSwitcherSelectionPolicy.initialSelectedIndex(
                applications: applications,
                reverse: true
            ),
            1
        )
    }

    static func testSelectionPolicySkipsPinnedActiveApplicationForward() throws {
        let applications = [
            makeApplication(id: "finder", processIdentifier: 1, isActive: true),
            makeApplication(id: "notes", processIdentifier: 2),
            makeApplication(id: "safari", processIdentifier: 3)
        ]

        try expectEqual(
            ApplicationSwitcherSelectionPolicy.initialSelectedIndex(
                applications: applications,
                reverse: false
            ),
            1
        )
        try expectEqual(
            ApplicationSwitcherSelectionPolicy.initialSelectedIndex(
                applications: applications,
                reverse: true
            ),
            2
        )
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

    static func testApplicationWindowCountPreservesMetadataAndStoresNumericSubtitle() throws {
        let application = ApplicationItem(
            id: "com.example.editor",
            processIdentifier: 81,
            bundleIdentifier: "com.example.editor",
            isActive: true,
            switcherListItem: SwitcherListItem(
                id: "com.example.editor",
                title: "Editor",
                subtitle: nil,
                symbolName: "square.stack.3d.up",
                thumbnailKey: "editor-thumbnail",
                appIconProcessIdentifier: 81
            )
        )

        let counted = application.withWindowCount(3)

        try expectEqual(counted.id, application.id)
        try expectEqual(counted.processIdentifier, application.processIdentifier)
        try expectEqual(counted.bundleIdentifier, application.bundleIdentifier)
        try expectEqual(counted.isActive, application.isActive)
        try expectEqual(counted.switcherListItem.id, application.switcherListItem.id)
        try expectEqual(counted.switcherListItem.title, application.switcherListItem.title)
        try expectEqual(counted.switcherListItem.subtitle, "3")
        try expectEqual(counted.switcherListItem.symbolName, application.switcherListItem.symbolName)
        try expectEqual(counted.switcherListItem.thumbnailKey, application.switcherListItem.thumbnailKey)
        try expectEqual(
            counted.switcherListItem.appIconProcessIdentifier,
            application.switcherListItem.appIconProcessIdentifier
        )
    }

    static func testApplicationUnknownWindowCountPreservesMetadataAndClearsSubtitle() throws {
        let application = ApplicationItem(
            id: "com.example.editor",
            processIdentifier: 81,
            bundleIdentifier: nil,
            isActive: false,
            switcherListItem: SwitcherListItem(
                id: "com.example.editor",
                title: "Editor",
                subtitle: "stale",
                symbolName: "app",
                thumbnailKey: "editor-thumbnail",
                appIconProcessIdentifier: 81
            )
        )

        let unknown = application.withWindowCount(nil)

        try expectEqual(
            unknown,
            ApplicationItem(
                id: application.id,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                isActive: application.isActive,
                switcherListItem: SwitcherListItem(
                    id: application.switcherListItem.id,
                    title: application.switcherListItem.title,
                    subtitle: nil,
                    symbolName: application.switcherListItem.symbolName,
                    thumbnailKey: application.switcherListItem.thumbnailKey,
                    appIconProcessIdentifier: application.switcherListItem.appIconProcessIdentifier
                )
            )
        )
    }

    static func testApplicationPresentationMapsKnownZeroAndUnknownWindowCounts() throws {
        let applications = [
            makeApplication(id: "com.example.one", processIdentifier: 81),
            makeApplication(id: "com.example.zero", processIdentifier: 82),
            makeApplication(id: "com.example.unknown", processIdentifier: 83)
        ]
        let counts = [81: 4, 82: 0]

        let counted = ApplicationSwitcherWindowCountPolicy.addingCounts(
            to: applications,
            windowCount: { counts[$0.processIdentifier] }
        )

        try expectEqual(counted.map(\.switcherListItem.subtitle), ["4", "0", nil])
        try expectEqual(counted.map(\.id), applications.map(\.id))
    }

    static func testWindowCountLoaderDefersWorkFromCaller() throws {
        let workerQueue = DispatchQueue(label: "ApplicationSwitchingTests.window-count-loader")
        workerQueue.suspend()
        let completion = DispatchSemaphore(value: 0)
        let loader = ApplicationWindowCountLoader(
            queue: workerQueue,
            loadCounts: { applications in
                applications.map { $0.withWindowCount(1) }
            }
        )

        loader.load(applications: [
            makeApplication(id: "com.example.editor", processIdentifier: 84)
        ]) { _ in
            completion.signal()
        }

        let immediateResult = completion.wait(timeout: .now())
        workerQueue.resume()

        try expectEqual(immediateResult, .timedOut)
        try expectEqual(completion.wait(timeout: .now() + 1), .success)
    }

    static func testTerminationServiceReportsAcceptedAndRejectedRequests() throws {
        let acceptedDriver = FakeApplicationTerminator(result: true)
        let acceptedService = ApplicationTerminationService(terminator: acceptedDriver)
        let rejectedDriver = FakeApplicationTerminator(result: false)
        let rejectedService = ApplicationTerminationService(terminator: rejectedDriver)
        let application = makeApplication(id: "com.example.editor", processIdentifier: 91)

        try expectEqual(acceptedService.terminate(application), .requestAccepted)
        try expectEqual(rejectedService.terminate(application), .unavailableTarget)
        try expectEqual(acceptedDriver.processIdentifiers, [91])
        try expectEqual(rejectedDriver.processIdentifiers, [91])
    }

    static func testTerminationIdentityUsesStableBundleOrProcessIdentifier() throws {
        let bundled = RunningApplicationSnapshot(
            processIdentifier: 101,
            bundleIdentifier: " com.example.editor ",
            localizedName: "Editor",
            isRegular: true,
            isTerminated: true,
            isActive: false
        )
        let unbundled = RunningApplicationSnapshot(
            processIdentifier: 102,
            bundleIdentifier: " ",
            localizedName: "Tool",
            isRegular: true,
            isTerminated: true,
            isActive: false
        )

        try expectEqual(
            WorkspaceApplicationTerminationPolicy.applicationIdentifier(for: bundled),
            "com.example.editor"
        )
        try expectEqual(
            WorkspaceApplicationTerminationPolicy.applicationIdentifier(for: unbundled),
            "pid:102"
        )
    }

    static func testTerminationIdentityRejectsNonRegularOrUnterminatedSnapshots() throws {
        let nonRegular = RunningApplicationSnapshot(
            processIdentifier: 103,
            bundleIdentifier: "com.example.helper",
            localizedName: "Helper",
            isRegular: false,
            isTerminated: true,
            isActive: false
        )
        let stillRunning = RunningApplicationSnapshot(
            processIdentifier: 104,
            bundleIdentifier: "com.example.running",
            localizedName: "Running",
            isRegular: true,
            isTerminated: false,
            isActive: false
        )

        try expectEqual(
            WorkspaceApplicationTerminationPolicy.applicationIdentifier(for: nonRegular),
            nil
        )
        try expectEqual(
            WorkspaceApplicationTerminationPolicy.applicationIdentifier(for: stillRunning),
            nil
        )
    }

    static func testSystemActivatorUsesFrontmostApplicationAsActivationSource() throws {
        let target = FakeApplicationActivationTarget(activationResult: true)
        let provider = FakeApplicationActivationTargetProvider(
            target: target,
            frontmostProcessIdentifier: 73
        )
        let activator = NSRunningApplicationActivator(targetProvider: provider)

        let result = activator.activate(processIdentifier: 404)

        try expectTrue(result)
        try expectEqual(provider.processIdentifiers, [404])
        try expectEqual(target.events, ["activateAllWindowsFrom:73"])
    }

    static func testSystemActivatorRejectsTerminatedTargetBeforeActivation() throws {
        let target = FakeApplicationActivationTarget(
            isTerminated: true,
            activationResult: true
        )
        let activator = NSRunningApplicationActivator(
            targetProvider: FakeApplicationActivationTargetProvider(target: target)
        )

        try expectTrue(!activator.activate(processIdentifier: 405))
        try expectEqual(target.events, [])
    }

    static func testSystemActivatorRejectsMissingTarget() throws {
        let provider = FakeApplicationActivationTargetProvider(target: nil)
        let activator = NSRunningApplicationActivator(targetProvider: provider)

        try expectTrue(!activator.activate(processIdentifier: 406))
        try expectEqual(provider.processIdentifiers, [406])
    }

    static func testSystemActivatorFallsBackWhenFrontmostApplicationIsMissing() throws {
        let target = FakeApplicationActivationTarget(activationResult: true)
        let activator = NSRunningApplicationActivator(
            targetProvider: FakeApplicationActivationTargetProvider(
                target: target,
                frontmostProcessIdentifier: nil
            )
        )

        try expectTrue(activator.activate(processIdentifier: 408))
        try expectEqual(target.events, ["activateAllWindows"])
    }

    static func testSystemActivatorReturnsCoordinatedActivationFailure() throws {
        let target = FakeApplicationActivationTarget(activationResult: false)
        let activator = NSRunningApplicationActivator(
            targetProvider: FakeApplicationActivationTargetProvider(target: target)
        )

        try expectTrue(!activator.activate(processIdentifier: 407))
        try expectEqual(target.events, ["activateAllWindowsFrom:73"])
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

    private static func makeApplication(
        id: String,
        processIdentifier: Int,
        isActive: Bool = false
    ) -> ApplicationItem {
        ApplicationItem(
            id: id,
            processIdentifier: processIdentifier,
            bundleIdentifier: id,
            isActive: isActive,
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

private final class FakeApplicationActivationTarget: ApplicationActivationTarget {
    let isTerminated: Bool
    let activationResult: Bool
    private(set) var events: [String] = []

    init(
        isTerminated: Bool = false,
        activationResult: Bool
    ) {
        self.isTerminated = isTerminated
        self.activationResult = activationResult
    }

    func activateAllWindows(from processIdentifier: Int?) -> Bool {
        if let processIdentifier {
            events.append("activateAllWindowsFrom:\(processIdentifier)")
        } else {
            events.append("activateAllWindows")
        }
        return activationResult
    }
}

private final class FakeApplicationActivationTargetProvider: ApplicationActivationTargetProviding {
    let targetValue: (any ApplicationActivationTarget)?
    let frontmostProcessIdentifier: Int?
    private(set) var processIdentifiers: [Int] = []

    init(
        target: (any ApplicationActivationTarget)?,
        frontmostProcessIdentifier: Int? = 73
    ) {
        self.targetValue = target
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
    }

    func target(processIdentifier: Int) -> (any ApplicationActivationTarget)? {
        processIdentifiers.append(processIdentifier)
        return targetValue
    }

    func frontmostApplicationProcessIdentifier() -> Int? {
        frontmostProcessIdentifier
    }
}

private final class FakeApplicationTerminator: ApplicationTerminating {
    let result: Bool
    private(set) var processIdentifiers: [Int] = []

    init(result: Bool) {
        self.result = result
    }

    func terminate(processIdentifier: Int) -> Bool {
        processIdentifiers.append(processIdentifier)
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
            setting.id.hasSuffix("-reverse")
                ? "register-reverse"
                : "register-forward"
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
