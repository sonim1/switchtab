import Combine
import Foundation
import SwitchTab

enum ShortcutSettingsStoreTests {
    static func run() throws {
        try testStoreLoadsDefaultsWhenEmpty()
        try testInvalidSaveKeepsLastPersistedShortcut()
        try testRegistrationFailureKeepsLastPersistedShortcut()
        try testSavingDefaultShortcutDoesNotPersistWhenAlreadyImplicit()
        try testSavingDefaultShortcutClearsPersistedCustomShortcut()
        try testSavingUnchangedShortcutDoesNotRewrite()
        try testViewModelDoesNotNotifyWhenShortcutIsUnchanged()
        try testViewModelDoesNotPublishUnchangedValidationError()
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

        try expectEqual(defaults.writeCount, 1)
    }

    static func testSavingDefaultShortcutDoesNotPersistWhenAlreadyImplicit() throws {
        let defaults = CountingShortcutDefaults()
        let store = ShortcutSettingsStore(userDefaults: defaults)

        try store.save(.defaultCurrentAppWindowSwitching)

        try expectEqual(defaults.writeCount, 0)
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

        try expectEqual(defaults.writeCount, 1)
        try expectEqual(defaults.removeCount, 1)
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
        try expectEqual(defaults.writeCount, 0)
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

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
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
