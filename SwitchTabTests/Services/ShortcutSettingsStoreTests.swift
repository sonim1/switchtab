import Combine
import Foundation
import SwitchTab

enum ShortcutSettingsStoreTests {
    static func run() throws {
        try testStoreLoadsDefaultsWhenEmpty()
        try testFreshInstallLoadsBothModesEnabled()
        try testLegacyInstallPreservesWindowShortcutAndExplicitAppState()
        try testLegacyFootprintWithoutExplicitAppStateKeepsAppSwitchingDisabled()
        try testUnifiedPayloadWinsOverLegacyValues()
        try testSavingUnchangedConfigurationsDoesNotRewrite()
        try testCompatibilityWrappersMigrateIntoUnifiedPayload()
        try testSavingIncompleteConfigurationsThrows()
        try testSavingDuplicateConfigurationsThrows()
        try testFuturePayloadIsNotOverwrittenDuringLoad()
        try testFuturePayloadRejectsSaveWithoutChangingBytes()
        try testSavingModeMismatchThrows()
        try testLoadingModeMismatchMigratesInsteadOfAccepting()
        try testCompatibilitySaveRejectsApplicationShortcutInWindowSlot()
        try testUsageOnlyLegacyFootprintDisablesApplicationSwitching()
        try testViewModelLoadsBothConfigurations()
        try testViewModelTogglesOneModeWithoutChangingTheOther()
        try testDisabledModeShortcutRemainsEditable()
        try testResetRestoresOnlyModeDefaultAndPreservesEnabledState()
        try testUnchangedEnabledStateDoesNotWritePublishOrCallback()
        try testUnchangedShortcutDoesNotWritePublishOrCallback()
        try testUnchangedShortcutClearsOnlyItsModeError()
        try testEnabledPersistenceFailureKeepsConfigurationAndSetsModeError()
        try testRegistrationFailureKeepsConfigurationsAndSetsModeError()
        try testPersistenceFailureRollsBackLiveRegistration()
        try testPersistenceFailureReportsFailedLiveRegistrationRollback()
        try testForwardConflictAcrossModesIsRejected()
        try testAutoShiftReverseConflictAcrossModesIsRejected()
        try testInvalidSaveKeepsLastPersistedShortcut()
        try testRegistrationFailureKeepsLastPersistedShortcut()
        try testSavingDefaultShortcutDoesNotPersistWhenAlreadyImplicit()
        try testSavingDefaultShortcutClearsPersistedCustomShortcut()
        try testSavingUnchangedShortcutDoesNotRewrite()
        try testViewModelDoesNotNotifyWhenShortcutIsUnchanged()
        try testViewModelDoesNotPublishUnchangedValidationError()
        try testViewModelRejectsReservedApplicationShortcut()
        try testViewModelLoadsRegistrationMessageText()
        try testViewModelCombinesRegistrationMessages()
        try testViewModelSeparatesRegistrationMessagesByMode()
        try testPersistedApplicationSwitchingRegistrationMessageUsesRecoveryCopy()
        try testViewModelUpdatesCachedRegistrationMessagesOnRegistrationChange()
        try testViewModelDoesNotPublishUnchangedRegistrationMessages()
        try testSavingEmptyRegistrationMessagesDoesNotWriteWhenAlreadyEmpty()
        try testSavingUnchangedRegistrationMessagesDoesNotRewrite()
        try testSavingEmptyRegistrationMessagesClearsPersistedMessages()
        try testViewModelResetsShortcutToDefault()
    }

    static func testStoreLoadsDefaultsWhenEmpty() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)

        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
    }

    static func testFreshInstallLoadsBothModesEnabled() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())

        let configurations = store.loadConfigurations()

        try expectEqual(
            configurations,
            [.defaultCurrentAppWindows, .defaultApplicationSwitching]
        )
        try expectTrue(configurations.allSatisfy(\.isEnabled))
    }

    static func testLegacyInstallPreservesWindowShortcutAndExplicitAppState() throws {
        let defaults = makeDefaults()
        let legacyWindow = ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )
        defaults.set(
            try JSONEncoder().encode(legacyWindow),
            forKey: ShortcutSettingsStore.legacyWindowShortcutStorageKey
        )
        defaults.set(false, forKey: ApplicationSettingsStore.replacesCommandTabKey)

        let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

        try expectEqual(
            configurations[0],
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: true,
                shortcut: legacyWindow
            )
        )
        try expectEqual(
            configurations[1],
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: false,
                shortcut: .defaultApplicationSwitching
            )
        )
    }

    static func testLegacyFootprintWithoutExplicitAppStateKeepsAppSwitchingDisabled() throws {
        let defaults = makeDefaults()
        defaults.set(["finder"], forKey: "SwitchTab.recency.currentAppWindowSwitching")

        let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

        try expectFalse(configurations[1].isEnabled)
    }

    static func testUnifiedPayloadWinsOverLegacyValues() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let saved = [
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: false,
                shortcut: .defaultCurrentAppWindowSwitching
            ),
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: true,
                shortcut: .defaultApplicationSwitching
            )
        ]
        try store.saveConfigurations(saved)
        defaults.set(true, forKey: ApplicationSettingsStore.replacesCommandTabKey)

        try expectEqual(store.loadConfigurations(), saved)
    }

    static func testSavingUnchangedConfigurationsDoesNotRewrite() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let configurations = [
            SwitcherShortcutConfiguration.defaultCurrentAppWindows,
            SwitcherShortcutConfiguration.defaultApplicationSwitching
        ]

        try store.saveConfigurations(configurations)
        try store.saveConfigurations(configurations)
        try expectEqual(defaults.writeCount, 1)
    }

    static func testCompatibilityWrappersMigrateIntoUnifiedPayload() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let customSetting = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )

        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
        try expectTrue(defaults.data(forKey: "SwitchTab.shortcut.configurations") != nil)

        try store.save(customSetting)

        try expectEqual(store.load(), customSetting)
        try expectEqual(
            store.loadConfigurations().first { $0.mode == .currentAppWindowSwitching }?.shortcut,
            customSetting
        )
    }

    static func testSavingIncompleteConfigurationsThrows() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())

        do {
            try store.saveConfigurations([.defaultCurrentAppWindows])
            throw TestFailure.failed("Expected incomplete configurations to be rejected")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(error, .missingMode(.applicationSwitching))
        }
    }

    static func testSavingDuplicateConfigurationsThrows() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let configurations = [
            SwitcherShortcutConfiguration.defaultCurrentAppWindows,
            SwitcherShortcutConfiguration.defaultApplicationSwitching,
            SwitcherShortcutConfiguration.defaultApplicationSwitching
        ]

        do {
            try store.saveConfigurations(configurations)
            throw TestFailure.failed("Expected duplicate configurations to be rejected")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(error, .duplicateMode(.applicationSwitching))
        }
    }

    static func testFuturePayloadIsNotOverwrittenDuringLoad() throws {
        let defaults = makeDefaults()
        let futureData = try makeStoredConfigurationsData(
            version: 2,
            configurations: [
                .defaultCurrentAppWindows,
                .defaultApplicationSwitching
            ]
        )
        defaults.set(futureData, forKey: "SwitchTab.shortcut.configurations")

        let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

        try expectEqual(configurations, [.defaultCurrentAppWindows, .defaultApplicationSwitching])
        try expectEqual(defaults.data(forKey: "SwitchTab.shortcut.configurations"), futureData)
    }

    static func testFuturePayloadRejectsSaveWithoutChangingBytes() throws {
        let defaults = makeDefaults()
        let futureData = try makeStoredConfigurationsData(
            version: 2,
            configurations: [
                .defaultCurrentAppWindows,
                .defaultApplicationSwitching
            ]
        )
        defaults.set(futureData, forKey: "SwitchTab.shortcut.configurations")
        let store = ShortcutSettingsStore(userDefaults: defaults)

        do {
            try store.saveConfigurations([
                .defaultCurrentAppWindows,
                .defaultApplicationSwitching
            ])
            throw TestFailure.failed("Expected future payload to reject a v1 save")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(error, .unsupportedVersion(2))
        }

        do {
            try store.save(.defaultCurrentAppWindowSwitching)
            throw TestFailure.failed("Expected compatibility save to reject a future payload")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(error, .unsupportedVersion(2))
        }

        try expectEqual(defaults.data(forKey: "SwitchTab.shortcut.configurations"), futureData)
    }

    static func testSavingModeMismatchThrows() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let mismatched = SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: true,
            shortcut: .defaultApplicationSwitching
        )

        do {
            try store.saveConfigurations([mismatched, .defaultApplicationSwitching])
            throw TestFailure.failed("Expected mode mismatch to be rejected")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(
                error,
                .modeMismatch(expected: .currentAppWindowSwitching, actual: .applicationSwitching)
            )
        }
    }

    static func testLoadingModeMismatchMigratesInsteadOfAccepting() throws {
        let defaults = makeDefaults()
        let mismatched = SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: true,
            shortcut: .defaultApplicationSwitching
        )
        let mismatchedData = try makeStoredConfigurationsData(
            version: 1,
            configurations: [mismatched, .defaultApplicationSwitching]
        )
        defaults.set(mismatchedData, forKey: "SwitchTab.shortcut.configurations")

        let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

        try expectEqual(configurations, [.defaultCurrentAppWindows, .defaultApplicationSwitching])
        try expectFalse(configurations.contains { $0.shortcut.mode != $0.mode })
    }

    static func testCompatibilitySaveRejectsApplicationShortcutInWindowSlot() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())

        do {
            try store.save(.defaultApplicationSwitching)
            throw TestFailure.failed("Expected compatibility save to reject application shortcut")
        } catch let error as ShortcutSettingsStoreError {
            try expectEqual(
                error,
                .modeMismatch(expected: .currentAppWindowSwitching, actual: .applicationSwitching)
            )
        }
    }

    static func testUsageOnlyLegacyFootprintDisablesApplicationSwitching() throws {
        let defaults = makeDefaults()
        defaults.set(1, forKey: "SwitchTab.usage.2026-08-02.currentAppWindowSwitching")

        let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

        try expectFalse(configurations[1].isEnabled)
    }

    static func testViewModelLoadsBothConfigurations() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let window = SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: false,
            shortcut: ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
                keyEquivalent: "K",
                modifiers: ["option"],
                isUsable: true
            )
        )
        let application = SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: true,
            shortcut: ShortcutSetting.defaultApplicationSwitching.replacingWithValidation(
                keyEquivalent: "Space",
                keyCode: 49,
                modifiers: ["control"],
                isUsable: true
            )
        )
        try store.saveConfigurations([window, application])

        let viewModel = ShortcutSettingsViewModel(store: store)

        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), window)
        try expectEqual(viewModel.configuration(for: .applicationSwitching), application)
    }

    static func testViewModelTogglesOneModeWithoutChangingTheOther() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        var callbacks: [SwitcherShortcutConfiguration] = []
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            onEnabledChanged: { callbacks.append($0) }
        )
        let previousApplication = viewModel.configuration(for: .applicationSwitching)

        viewModel.setEnabled(false, for: .currentAppWindowSwitching)

        let updatedWindow = viewModel.configuration(for: .currentAppWindowSwitching)
        try expectFalse(updatedWindow.isEnabled)
        try expectEqual(viewModel.configuration(for: .applicationSwitching), previousApplication)
        try expectEqual(callbacks, [updatedWindow])
        try expectEqual(
            store.loadConfigurations(),
            [updatedWindow, previousApplication]
        )
    }

    static func testDisabledModeShortcutRemainsEditable() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let viewModel = ShortcutSettingsViewModel(store: store)
        viewModel.setEnabled(false, for: .applicationSwitching)
        let previousWindow = viewModel.configuration(for: .currentAppWindowSwitching)

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: "Space",
                modifiers: ["option"],
                keyCode: 49
            ),
            for: .applicationSwitching
        )

        let application = viewModel.configuration(for: .applicationSwitching)
        try expectTrue(didRecord)
        try expectFalse(application.isEnabled)
        try expectEqual(application.shortcut.displayText, "Option + Space")
        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), previousWindow)
        try expectEqual(
            store.loadConfigurations().first { $0.mode == .applicationSwitching },
            application
        )
    }

    static func testResetRestoresOnlyModeDefaultAndPreservesEnabledState() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let viewModel = ShortcutSettingsViewModel(store: store)
        viewModel.setEnabled(false, for: .applicationSwitching)
        _ = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: "Space",
                modifiers: ["option"],
                keyCode: 49
            ),
            for: .applicationSwitching
        )
        let previousWindow = viewModel.configuration(for: .currentAppWindowSwitching)

        let didReset = viewModel.resetToDefault(for: .applicationSwitching)

        let application = viewModel.configuration(for: .applicationSwitching)
        try expectTrue(didReset)
        try expectFalse(application.isEnabled)
        try expectEqual(application.shortcut, .defaultApplicationSwitching)
        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), previousWindow)
        try expectEqual(
            store.loadConfigurations().first { $0.mode == .applicationSwitching },
            application
        )
    }

    static func testUnchangedEnabledStateDoesNotWritePublishOrCallback() throws {
        let defaults = CountingShortcutDefaults()
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: defaults),
            onEnabledChanged: { _ in callbackCount += 1 }
        )
        let initialWriteCount = defaults.writeCount
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        viewModel.setEnabled(true, for: .currentAppWindowSwitching)

        try expectEqual(defaults.writeCount, initialWriteCount)
        try expectEqual(callbackCount, 0)
        try expectEqual(publishCount, 0)
    }

    static func testUnchangedShortcutDoesNotWritePublishOrCallback() throws {
        let defaults = CountingShortcutDefaults()
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: defaults),
            onShortcutChanged: { _, _ in
                callbackCount += 1
                return true
            }
        )
        let initialWriteCount = defaults.writeCount
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: ShortcutSetting.defaultCurrentAppWindowSwitching.keyEquivalent,
                modifiers: ShortcutSetting.defaultCurrentAppWindowSwitching.modifiers,
                keyCode: ShortcutSetting.defaultCurrentAppWindowSwitching.keyCode
            ),
            for: .currentAppWindowSwitching
        )

        try expectTrue(didRecord)
        try expectEqual(defaults.writeCount, initialWriteCount)
        try expectEqual(callbackCount, 0)
        try expectEqual(publishCount, 0)
    }

    static func testUnchangedShortcutClearsOnlyItsModeError() throws {
        let defaults = CountingShortcutDefaults()
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: defaults),
            onShortcutChanged: { _, _ in
                callbackCount += 1
                return true
            }
        )
        let initialWriteCount = defaults.writeCount
        let invalidCapture = ShortcutCapture(
            keyEquivalent: "Space",
            modifiers: [],
            keyCode: 49
        )

        try expectFalse(viewModel.record(
            capture: invalidCapture,
            for: .currentAppWindowSwitching
        ))
        try expectFalse(viewModel.record(
            capture: invalidCapture,
            for: .applicationSwitching
        ))
        try expectEqual(
            viewModel.errorMessage(for: .currentAppWindowSwitching),
            "Shortcut must include at least one modifier."
        )
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut must include at least one modifier."
        )

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: ShortcutSetting.defaultCurrentAppWindowSwitching.keyEquivalent,
                modifiers: ShortcutSetting.defaultCurrentAppWindowSwitching.modifiers,
                keyCode: ShortcutSetting.defaultCurrentAppWindowSwitching.keyCode
            ),
            for: .currentAppWindowSwitching
        )

        try expectTrue(didRecord)
        try expectEqual(viewModel.errorMessage(for: .currentAppWindowSwitching), nil)
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut must include at least one modifier."
        )
        try expectEqual(defaults.writeCount, initialWriteCount)
        try expectEqual(callbackCount, 0)
    }

    static func testEnabledPersistenceFailureKeepsConfigurationAndSetsModeError() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            saveConfigurations: { _ in throw TestFailure.failed("save failed") },
            onEnabledChanged: { _ in callbackCount += 1 }
        )
        let previous = store.loadConfigurations()

        viewModel.setEnabled(false, for: .applicationSwitching)

        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), previous[0])
        try expectEqual(viewModel.configuration(for: .applicationSwitching), previous[1])
        try expectEqual(store.loadConfigurations(), previous)
        try expectEqual(callbackCount, 0)
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut could not be saved."
        )
        try expectEqual(viewModel.errorMessage(for: .currentAppWindowSwitching), nil)
    }

    static func testRegistrationFailureKeepsConfigurationsAndSetsModeError() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            onShortcutChanged: { _, _ in
                callbackCount += 1
                return false
            }
        )
        let previous = store.loadConfigurations()

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: "Space",
                modifiers: ["option"],
                keyCode: 49
            ),
            for: .applicationSwitching
        )

        try expectFalse(didRecord)
        try expectEqual(callbackCount, 1)
        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), previous[0])
        try expectEqual(viewModel.configuration(for: .applicationSwitching), previous[1])
        try expectEqual(store.loadConfigurations(), previous)
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut could not be registered. The previous shortcut is still active."
        )
        try expectEqual(viewModel.errorMessage(for: .currentAppWindowSwitching), nil)
    }

    static func testPersistenceFailureRollsBackLiveRegistration() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let previousConfigurations = store.loadConfigurations()
        let previousApplication = previousConfigurations[1]
        let expectedCandidate = SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: previousApplication.isEnabled,
            shortcut: previousApplication.shortcut.replacingWithValidation(
                keyEquivalent: "Space",
                keyCode: 49,
                modifiers: ["option"],
                isUsable: true
            )
        )
        var callbackCandidates: [SwitcherShortcutConfiguration] = []
        var callbackPreviousValues: [SwitcherShortcutConfiguration] = []
        var saveAttemptCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            saveConfigurations: { _ in
                saveAttemptCount += 1
                throw TestFailure.failed("save failed")
            },
            onShortcutChanged: { candidate, previous in
                callbackCandidates.append(candidate)
                callbackPreviousValues.append(previous)
                return true
            }
        )

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: "Space",
                modifiers: ["option"],
                keyCode: 49
            ),
            for: .applicationSwitching
        )

        try expectFalse(didRecord)
        try expectEqual(saveAttemptCount, 1)
        try expectEqual(callbackCandidates, [expectedCandidate, previousApplication])
        try expectEqual(callbackPreviousValues, [previousApplication, expectedCandidate])
        try expectEqual(store.loadConfigurations(), previousConfigurations)
        try expectEqual(
            viewModel.configuration(for: .applicationSwitching),
            previousApplication
        )
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut could not be saved."
        )
    }

    static func testPersistenceFailureReportsFailedLiveRegistrationRollback() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let previousConfigurations = store.loadConfigurations()
        let previousApplication = previousConfigurations[1]
        let expectedCandidate = SwitcherShortcutConfiguration(
            mode: .applicationSwitching,
            isEnabled: previousApplication.isEnabled,
            shortcut: previousApplication.shortcut.replacingWithValidation(
                keyEquivalent: "Space",
                keyCode: 49,
                modifiers: ["option"],
                isUsable: true
            )
        )
        var callbackCandidates: [SwitcherShortcutConfiguration] = []
        var callbackPreviousValues: [SwitcherShortcutConfiguration] = []
        var callbackResults = [true, false]
        var saveAttemptCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            saveConfigurations: { _ in
                saveAttemptCount += 1
                throw TestFailure.failed("save failed")
            },
            onShortcutChanged: { candidate, previous in
                callbackCandidates.append(candidate)
                callbackPreviousValues.append(previous)
                return callbackResults.removeFirst()
            }
        )

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: "Space",
                modifiers: ["option"],
                keyCode: 49
            ),
            for: .applicationSwitching
        )

        try expectFalse(didRecord)
        try expectEqual(saveAttemptCount, 1)
        try expectEqual(callbackCandidates, [expectedCandidate, previousApplication])
        try expectEqual(callbackPreviousValues, [previousApplication, expectedCandidate])
        try expectEqual(store.loadConfigurations(), previousConfigurations)
        try expectEqual(
            viewModel.configuration(for: .applicationSwitching),
            previousApplication
        )
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut could not be saved, and the previous shortcut could not be restored."
        )
        try expectEqual(viewModel.errorMessage(for: .currentAppWindowSwitching), nil)
    }

    static func testForwardConflictAcrossModesIsRejected() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        var callbackCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            onShortcutChanged: { _, _ in
                callbackCount += 1
                return true
            }
        )
        let previous = store.loadConfigurations()

        let didRecord = viewModel.record(
            capture: ShortcutCapture(
                keyEquivalent: ShortcutSetting.defaultCurrentAppWindowSwitching.keyEquivalent,
                modifiers: ShortcutSetting.defaultCurrentAppWindowSwitching.modifiers,
                keyCode: ShortcutSetting.defaultCurrentAppWindowSwitching.keyCode
            ),
            for: .applicationSwitching
        )

        try expectFalse(didRecord)
        try expectEqual(callbackCount, 0)
        try expectEqual(store.loadConfigurations(), previous)
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut is already used by another switcher mode."
        )
    }

    static func testAutoShiftReverseConflictAcrossModesIsRejected() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let window = SwitcherShortcutConfiguration(
            mode: .currentAppWindowSwitching,
            isEnabled: true,
            shortcut: ShortcutSetting(
                id: "current-app-window-switching",
                mode: .currentAppWindowSwitching,
                keyEquivalent: "K",
                modifiers: ["command", "shift"],
                isUsable: true
            )
        )
        try store.saveConfigurations([window, .defaultApplicationSwitching])
        let viewModel = ShortcutSettingsViewModel(store: store)

        let didRecord = viewModel.record(
            capture: ShortcutCapture(keyEquivalent: "K", modifiers: ["command"]),
            for: .applicationSwitching
        )

        try expectFalse(didRecord)
        try expectEqual(viewModel.configuration(for: .currentAppWindowSwitching), window)
        try expectEqual(
            viewModel.configuration(for: .applicationSwitching),
            .defaultApplicationSwitching
        )
        try expectEqual(
            viewModel.errorMessage(for: .applicationSwitching),
            "Shortcut is already used by another switcher mode."
        )
    }

    static func testInvalidSaveKeepsLastPersistedShortcut() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let viewModel = ShortcutSettingsViewModel(store: store)

        let saved = viewModel.save(
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )
        let rejected = viewModel.save(
            keyEquivalent: "J",
            modifiers: [],
            isUsable: true
        )

        try expectTrue(saved)
        try expectFalse(rejected)
        try expectEqual(store.load().keyEquivalent, "K")
    }

    static func testRegistrationFailureKeepsLastPersistedShortcut() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let previous = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )
        try store.save(previous)
        let viewModel = ShortcutSettingsViewModel(
            store: store,
            onValidSettingsChanged: { _, _ in false }
        )

        let didSave = viewModel.save(
            keyEquivalent: "J",
            modifiers: ["command"],
            isUsable: true
        )

        try expectFalse(didSave)
        try expectEqual(viewModel.currentAppWindowShortcut, previous)
        try expectEqual(store.load(), previous)
    }

    static func testSavingUnchangedShortcutDoesNotRewrite() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let setting = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )

        try store.save(setting)
        try store.save(setting)

        try expectEqual(defaults.writeCount, 2)
    }

    static func testSavingDefaultShortcutDoesNotPersistWhenAlreadyImplicit() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)

        try store.save(.defaultCurrentAppWindowSwitching)

        try expectEqual(defaults.writeCount, 1)
        try expectEqual(defaults.removeCount, 0)
        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
    }

    static func testSavingDefaultShortcutClearsPersistedCustomShortcut() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let customSetting = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )

        try store.save(customSetting)
        try store.save(.defaultCurrentAppWindowSwitching)

        try expectEqual(defaults.writeCount, 3)
        try expectEqual(defaults.removeCount, 0)
        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
    }

    static func testViewModelDoesNotNotifyWhenShortcutIsUnchanged() throws {
        let defaults = CountingShortcutDefaults()
        var notificationCount = 0
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: defaults),
            onValidSettingsChanged: { _, _ in
                notificationCount += 1
                return true
            }
        )

        let didSave = viewModel.save(
            keyEquivalent: ShortcutSetting.defaultCurrentAppWindowSwitching.keyEquivalent,
            modifiers: ShortcutSetting.defaultCurrentAppWindowSwitching.modifiers,
            isUsable: true
        )

        try expectTrue(didSave)
        try expectEqual(defaults.writeCount, 1)
        try expectEqual(notificationCount, 0)
    }

    static func testViewModelDoesNotPublishUnchangedValidationError() throws {
        let viewModel = ShortcutSettingsViewModel(
            store: ShortcutSettingsStore(userDefaults: makeDefaults())
        )

        let firstSave = viewModel.save(
            keyEquivalent: "K",
            modifiers: [],
            isUsable: true
        )
        try expectFalse(firstSave)
        try expectEqual(viewModel.errorMessage, "Shortcut must include at least one modifier.")

        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
        }

        let secondSave = viewModel.save(
            keyEquivalent: "K",
            modifiers: [],
            isUsable: true
        )

        try expectFalse(secondSave)
        try expectEqual(viewModel.errorMessage, "Shortcut must include at least one modifier.")
        try expectEqual(publishCount, 0)
    }

    static func testViewModelRejectsReservedApplicationShortcut() throws {
        let store = ShortcutSettingsStore(userDefaults: makeDefaults())
        let viewModel = ShortcutSettingsViewModel(store: store)

        let didSave = viewModel.save(
            keyEquivalent: "Tab",
            keyCode: 48,
            modifiers: ["command"],
            isUsable: true
        )

        try expectFalse(didSave)
        try expectEqual(viewModel.currentAppWindowShortcut, .defaultCurrentAppWindowSwitching)
        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
        try expectEqual(
            viewModel.errorMessage,
            "Shortcut is already used by another switcher mode."
        )
    }

    static func testViewModelLoadsRegistrationMessageText() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        store.saveRegistrationMessages([
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Shortcut unavailable")
        ])

        let viewModel = ShortcutSettingsViewModel(store: store)

        try expectEqual(viewModel.registrationMessage(), "Shortcut unavailable")
    }

    static func testViewModelCombinesRegistrationMessages() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        store.saveRegistrationMessages([
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Cmd + ` unavailable"),
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Option + ` unavailable"),
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Fallback failed")
        ])

        let viewModel = ShortcutSettingsViewModel(store: store)

        try expectEqual(
            viewModel.registrationMessage(),
            "Cmd + ` unavailable Option + ` unavailable Fallback failed"
        )
    }

    static func testViewModelSeparatesRegistrationMessagesByMode() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        store.saveRegistrationMessages([
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Window first"),
            ShortcutRegistrationMessage(mode: .applicationSwitching, message: "Applications first"),
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Window second"),
            ShortcutRegistrationMessage(mode: .applicationSwitching, message: "Applications second")
        ])

        let viewModel = ShortcutSettingsViewModel(store: store)

        try expectEqual(viewModel.registrationMessage(), "Window first Window second")
        try expectEqual(
            viewModel.applicationSwitchingRegistrationMessage(),
            "Applications first Applications second"
        )
    }

    static func testPersistedApplicationSwitchingRegistrationMessageUsesRecoveryCopy() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let registrar = ShortcutSettingsApplicationSwitchingFailingRegistrar()
        let controller = ApplicationSwitchingHotkeyController(
            hotkeyService: HotkeyService(registrar: registrar)
        )

        try expectFalse(
            controller.updateRegistration(enabled: true, forwardHandler: {}, reverseHandler: {})
        )
        try expectTrue(store.saveRegistrationMessages(controller.registrationMessageSnapshot()))

        let viewModel = ShortcutSettingsViewModel(store: store)

        try expectEqual(viewModel.registrationMessage(), nil)
        try expectEqual(
            viewModel.applicationSwitchingRegistrationMessage(),
            ApplicationSwitchingHotkeyController.registrationFailureMessage
        )
    }

    static func testViewModelUpdatesCachedRegistrationMessagesOnRegistrationChange() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let viewModel = ShortcutSettingsViewModel(store: store)

        store.saveRegistrationMessages([
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Window fallback failed")
        ])
        NotificationCenter.default.post(name: .shortcutRegistrationDidChange, object: nil)

        try expectEqual(viewModel.registrationMessage(), "Window fallback failed")
    }

    static func testViewModelDoesNotPublishUnchangedRegistrationMessages() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let messages = [
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Shortcut unavailable")
        ]
        store.saveRegistrationMessages(messages)
        let viewModel = ShortcutSettingsViewModel(store: store)
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
        }

        NotificationCenter.default.post(name: .shortcutRegistrationDidChange, object: nil)

        try expectEqual(viewModel.registrationMessage(), "Shortcut unavailable")
        try expectEqual(publishCount, 0)
    }

    static func testSavingEmptyRegistrationMessagesDoesNotWriteWhenAlreadyEmpty() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)

        let didChange = store.saveRegistrationMessages([])

        try expectFalse(didChange)
        try expectEqual(defaults.writeCount, 0)
        try expectEqual(defaults.removeCount, 0)
    }

    static func testSavingUnchangedRegistrationMessagesDoesNotRewrite() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let messages = [
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Shortcut unavailable")
        ]

        let didSave = store.saveRegistrationMessages(messages)
        let didSaveAgain = store.saveRegistrationMessages(messages)

        try expectTrue(didSave)
        try expectFalse(didSaveAgain)
        try expectEqual(defaults.writeCount, 1)
    }

    static func testSavingEmptyRegistrationMessagesClearsPersistedMessages() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        store.saveRegistrationMessages([
            ShortcutRegistrationMessage(mode: .currentAppWindowSwitching, message: "Shortcut unavailable")
        ])

        let didClear = store.saveRegistrationMessages([])

        try expectTrue(didClear)
        try expectEqual(store.loadRegistrationMessages(), [])
    }

    static func testViewModelResetsShortcutToDefault() throws {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let viewModel = ShortcutSettingsViewModel(store: store)

        _ = viewModel.save(
            keyEquivalent: "K",
            modifiers: ["option", "control"],
            isUsable: true
        )

        let reset = viewModel.resetToDefault()

        try expectTrue(reset)
        try expectEqual(viewModel.currentAppWindowShortcut, .defaultCurrentAppWindowSwitching)
        try expectEqual(store.load(), .defaultCurrentAppWindowSwitching)
    }

    private static func makeStoredConfigurationsData(
        version: Int,
        configurations: [SwitcherShortcutConfiguration]
    ) throws -> Data {
        try JSONEncoder().encode(
            TestStoredConfigurations(version: version, configurations: configurations)
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct TestStoredConfigurations: Codable {
    let version: Int
    let configurations: [SwitcherShortcutConfiguration]
}

final class CountingShortcutDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    private(set) var writeCount = 0
    private(set) var removeCount = 0

    init() {
        super.init(suiteName: "SwitchTabTests.\(UUID().uuidString)")!
    }

    override func data(forKey defaultName: String) -> Data? {
        return values[defaultName] as? Data
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        guard let value else {
            values.removeValue(forKey: defaultName)
            return
        }

        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        removeCount += 1
        values.removeValue(forKey: defaultName)
    }
}

private final class ShortcutSettingsApplicationSwitchingFailingRegistrar: HotkeyRegistering {
    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        setting.id == ShortcutSetting.defaultApplicationSwitching.id
    }

    func unregisterAll() {}
}
