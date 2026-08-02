import Foundation

public struct ShortcutSettingsStore {
    public static let legacyWindowShortcutStorageKey = "SwitchTab.shortcut.currentAppWindowSwitching"
    private static let configurationsStorageKey = "SwitchTab.shortcut.configurations"
    private static let currentPayloadVersion = 1
    private static let registrationMessagesKey = "SwitchTab.shortcut.registrationMessages"
    private static let emptyRegistrationMessages: [ShortcutRegistrationMessage] = []

    private struct StoredConfigurations: Codable {
        let version: Int
        let configurations: [SwitcherShortcutConfiguration]
    }

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> ShortcutSetting {
        if let configurations = persistedConfigurations() {
            return configurations.first {
                $0.mode == .currentAppWindowSwitching
            }?.shortcut ?? .defaultCurrentAppWindowSwitching
        }

        return load(
            key: Self.legacyWindowShortcutStorageKey,
            defaultSetting: .defaultCurrentAppWindowSwitching
        )
    }

    private func load(key: String, defaultSetting: ShortcutSetting) -> ShortcutSetting {
        guard let data = userDefaults.data(forKey: key),
              let setting = try? decoder.decode(ShortcutSetting.self, from: data) else {
            return defaultSetting
        }

        return setting
    }

    public func save(_ setting: ShortcutSetting) throws {
        if var configurations = persistedConfigurations(),
           let index = configurations.firstIndex(where: {
               $0.mode == .currentAppWindowSwitching
           }) {
            configurations[index].shortcut = setting
            try saveConfigurations(configurations)
            return
        }

        let key = Self.legacyWindowShortcutStorageKey
        let defaultSetting = ShortcutSetting.defaultCurrentAppWindowSwitching

        if setting == defaultSetting {
            if userDefaults.data(forKey: key) != nil {
                userDefaults.removeObject(forKey: key)
            }
            return
        }

        if let existingData = userDefaults.data(forKey: key),
           let existingSetting = try? decoder.decode(ShortcutSetting.self, from: existingData),
           existingSetting == setting {
            return
        }

        let data = try encoder.encode(setting)
        userDefaults.set(data, forKey: key)
    }

    public func loadConfigurations() -> [SwitcherShortcutConfiguration] {
        if let configurations = persistedConfigurations() {
            return configurations
        }

        let migrated = migratedConfigurations()
        try? saveConfigurations(migrated)
        return migrated
    }

    private func persistedConfigurations() -> [SwitcherShortcutConfiguration]? {
        guard let data = userDefaults.data(forKey: Self.configurationsStorageKey),
              let payload = try? decoder.decode(StoredConfigurations.self, from: data),
              payload.version == Self.currentPayloadVersion,
              isComplete(payload.configurations) else {
            return nil
        }

        return orderedConfigurations(payload.configurations)
    }

    public func saveConfigurations(_ configurations: [SwitcherShortcutConfiguration]) throws {
        let payload = StoredConfigurations(
            version: Self.currentPayloadVersion,
            configurations: orderedConfigurations(configurations)
        )
        let data = try encoder.encode(payload)
        guard userDefaults.data(forKey: Self.configurationsStorageKey) != data else {
            return
        }

        userDefaults.set(data, forKey: Self.configurationsStorageKey)
    }

    private func isComplete(_ configurations: [SwitcherShortcutConfiguration]) -> Bool {
        guard configurations.count == SwitcherMode.allCases.count else {
            return false
        }

        let modeValues = Set(configurations.map { $0.mode.rawValue })
        let expectedModeValues = Set(SwitcherMode.allCases.map { $0.rawValue })
        return modeValues == expectedModeValues
    }

    private func orderedConfigurations(
        _ configurations: [SwitcherShortcutConfiguration]
    ) -> [SwitcherShortcutConfiguration] {
        SwitcherMode.allCases.map { mode in
            configurations.first { $0.mode == mode }
                ?? .defaultValue(for: mode)
        }
    }

    private func migratedConfigurations() -> [SwitcherShortcutConfiguration] {
        let legacyWindow = load(
            key: Self.legacyWindowShortcutStorageKey,
            defaultSetting: .defaultCurrentAppWindowSwitching
        )
        let explicitApplicationState = userDefaults.object(
            forKey: ApplicationSettingsStore.replacesCommandTabKey
        ) as? Bool
        let applicationEnabled = explicitApplicationState ?? !hasLegacyFootprint

        return [
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: true,
                shortcut: legacyWindow
            ),
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: applicationEnabled,
                shortcut: .defaultApplicationSwitching
            )
        ]
    }

    private var hasLegacyFootprint: Bool {
        [
            Self.legacyWindowShortcutStorageKey,
            Self.registrationMessagesKey,
            ApplicationSettingsStore.menuBarIconVisibleKey,
            ApplicationSettingsStore.overlaySizeScaleKey,
            ApplicationSettingsStore.overlaySizeKey,
            "SwitchTab.recency.currentAppWindowSwitching",
            "SwitchTab.recency.applicationSwitching"
        ].contains { userDefaults.object(forKey: $0) != nil }
    }

    public func loadRegistrationMessages() -> [ShortcutRegistrationMessage] {
        guard let data = userDefaults.data(forKey: Self.registrationMessagesKey),
              let messages = try? decoder.decode([ShortcutRegistrationMessage].self, from: data) else {
            return Self.emptyRegistrationMessages
        }

        return messages
    }

    @discardableResult
    public func saveRegistrationMessages(_ messages: [ShortcutRegistrationMessage]) -> Bool {
        let existingData = userDefaults.data(forKey: Self.registrationMessagesKey)

        guard !messages.isEmpty else {
            if existingData != nil {
                userDefaults.removeObject(forKey: Self.registrationMessagesKey)
                return true
            }
            return false
        }

        guard let data = try? encoder.encode(messages) else {
            return false
        }

        if let existingData,
           let existingMessages = try? decoder.decode([ShortcutRegistrationMessage].self, from: existingData),
           existingMessages == messages {
            return false
        }

        userDefaults.set(data, forKey: Self.registrationMessagesKey)
        return true
    }

}
