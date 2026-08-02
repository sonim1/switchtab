import Foundation

public enum ShortcutSettingsStoreError: Error, Equatable, Sendable {
    case missingMode(SwitcherMode)
    case duplicateMode(SwitcherMode)
    case unsupportedVersion(Int)
    case modeMismatch(expected: SwitcherMode, actual: SwitcherMode)
}

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

    private struct StoredVersion: Decodable {
        let version: Int
    }

    private enum PersistedConfigurationsResult {
        case valid([SwitcherShortcutConfiguration])
        case unsupportedVersion(Int)
        case unavailable
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

    private func load(key: String, defaultSetting: ShortcutSetting) -> ShortcutSetting {
        guard let data = userDefaults.data(forKey: key),
              let setting = try? decoder.decode(ShortcutSetting.self, from: data) else {
            return defaultSetting
        }

        return setting
    }

    public func loadConfigurations() -> [SwitcherShortcutConfiguration] {
        switch persistedConfigurations() {
        case .valid(let configurations):
            return configurations
        case .unsupportedVersion:
            return migratedConfigurations()
        case .unavailable:
            break
        }

        let migrated = migratedConfigurations()
        try? saveConfigurations(migrated)
        return migrated
    }

    private func persistedConfigurations() -> PersistedConfigurationsResult {
        guard let data = userDefaults.data(forKey: Self.configurationsStorageKey),
              let version = try? decoder.decode(StoredVersion.self, from: data) else {
            return .unavailable
        }
        guard version.version <= Self.currentPayloadVersion else {
            return .unsupportedVersion(version.version)
        }
        guard version.version == Self.currentPayloadVersion,
              let payload = try? decoder.decode(StoredConfigurations.self, from: data),
              isComplete(payload.configurations) else {
            return .unavailable
        }

        return .valid(orderedConfigurations(payload.configurations))
    }

    public func saveConfigurations(_ configurations: [SwitcherShortcutConfiguration]) throws {
        if let version = unsupportedPersistedVersion() {
            throw ShortcutSettingsStoreError.unsupportedVersion(version)
        }
        try validate(configurations)
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

    private func unsupportedPersistedVersion() -> Int? {
        guard let data = userDefaults.data(forKey: Self.configurationsStorageKey),
              let version = try? decoder.decode(StoredVersion.self, from: data),
              version.version > Self.currentPayloadVersion else {
            return nil
        }

        return version.version
    }

    private func validate(_ configurations: [SwitcherShortcutConfiguration]) throws {
        for configuration in configurations where configuration.mode != configuration.shortcut.mode {
            throw ShortcutSettingsStoreError.modeMismatch(
                expected: configuration.mode,
                actual: configuration.shortcut.mode
            )
        }

        for mode in SwitcherMode.allCases {
            let matchingCount = configurations.reduce(into: 0) { count, configuration in
                if configuration.mode == mode {
                    count += 1
                }
            }

            if matchingCount == 0 {
                throw ShortcutSettingsStoreError.missingMode(mode)
            }
            if matchingCount > 1 {
                throw ShortcutSettingsStoreError.duplicateMode(mode)
            }
        }
    }

    private func isComplete(_ configurations: [SwitcherShortcutConfiguration]) -> Bool {
        guard configurations.count == SwitcherMode.allCases.count else {
            return false
        }

        guard configurations.allSatisfy({ $0.mode == $0.shortcut.mode }) else {
            return false
        }

        let modeValues = Set(configurations.map { $0.mode.rawValue })
        let expectedModeValues = Set(SwitcherMode.allCases.map { $0.rawValue })
        return modeValues == expectedModeValues
    }

    private func orderedConfigurations(
        _ configurations: [SwitcherShortcutConfiguration]
    ) -> [SwitcherShortcutConfiguration] {
        SwitcherMode.allCases.compactMap { mode in
            configurations.first { $0.mode == mode }
        }
    }

    private func migratedConfigurations() -> [SwitcherShortcutConfiguration] {
        let persistedLegacyWindow = load(
            key: Self.legacyWindowShortcutStorageKey,
            defaultSetting: .defaultCurrentAppWindowSwitching
        )
        let legacyWindow = persistedLegacyWindow.mode == .currentAppWindowSwitching
            ? persistedLegacyWindow
            : .defaultCurrentAppWindowSwitching
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
        let knownKeys = [
            Self.legacyWindowShortcutStorageKey,
            Self.registrationMessagesKey,
            ApplicationSettingsStore.menuBarIconVisibleKey,
            ApplicationSettingsStore.overlaySizeScaleKey,
            ApplicationSettingsStore.overlaySizeKey,
            "SwitchTab.recency.currentAppWindowSwitching",
            "SwitchTab.recency.applicationSwitching"
        ]
        return knownKeys.contains { userDefaults.object(forKey: $0) != nil }
            || userDefaults.dictionaryRepresentation().keys.contains {
                $0.hasPrefix("SwitchTab.usage.")
            }
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
