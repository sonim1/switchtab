import Foundation

public struct ShortcutSettingsStore {
    private static let windowShortcutStorageKey = "SwitchTab.shortcut.currentAppWindowSwitching"
    private static let registrationMessagesKey = "SwitchTab.shortcut.registrationMessages"
    private static let emptyRegistrationMessages: [ShortcutRegistrationMessage] = []

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> ShortcutSetting {
        load(key: Self.windowShortcutStorageKey, defaultSetting: .defaultCurrentAppWindowSwitching)
    }

    private func load(key: String, defaultSetting: ShortcutSetting) -> ShortcutSetting {
        guard let data = userDefaults.data(forKey: key),
              let setting = try? decoder.decode(ShortcutSetting.self, from: data) else {
            return defaultSetting
        }

        return setting
    }

    public func save(_ setting: ShortcutSetting) throws {
        let key = Self.windowShortcutStorageKey
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
