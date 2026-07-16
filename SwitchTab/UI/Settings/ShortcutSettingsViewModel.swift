import Combine
import Foundation

public extension Notification.Name {
    static let shortcutSettingsDidChange = Notification.Name("SwitchTab.shortcutSettingsDidChange")
    static let shortcutRegistrationDidChange = Notification.Name("SwitchTab.shortcutRegistrationDidChange")
    static let shortcutRecordingDidBegin = Notification.Name("SwitchTab.shortcutRecordingDidBegin")
    static let shortcutRecordingDidEnd = Notification.Name("SwitchTab.shortcutRecordingDidEnd")
}

public final class ShortcutSettingsViewModel: ObservableObject {
    private struct RegistrationMessageText: Equatable {
        let currentAppWindowSwitching: String?

        static let empty = RegistrationMessageText(
            currentAppWindowSwitching: nil
        )
    }

    @Published public private(set) var currentAppWindowShortcut: ShortcutSetting
    @Published public private(set) var permissionState: PermissionState
    @Published public private(set) var errorMessage: String?
    @Published private var registrationMessageText: RegistrationMessageText

    private let store: ShortcutSettingsStore
    private let validator: ShortcutValidationService
    private let permissionStateProvider: () -> PermissionState
    private let onValidSettingsChanged: ([ShortcutSetting]) -> Void
    private var registrationMessageCancellable: AnyCancellable?

    public init(
        store: ShortcutSettingsStore = ShortcutSettingsStore(),
        validator: ShortcutValidationService = ShortcutValidationService(),
        permissionStateProvider: @escaping () -> PermissionState = { PermissionService().currentState() },
        onValidSettingsChanged: @escaping ([ShortcutSetting]) -> Void = { _ in }
    ) {
        let savedShortcut = store.load()
        let loadedRegistrationMessages = store.loadRegistrationMessages()
        let registrationMessageText = Self.registrationMessageText(from: loadedRegistrationMessages)

        self.store = store
        self.validator = validator
        self.permissionStateProvider = permissionStateProvider
        self.onValidSettingsChanged = onValidSettingsChanged
        self.currentAppWindowShortcut = savedShortcut
        self.permissionState = permissionStateProvider()
        self.registrationMessageText = registrationMessageText

        registrationMessageCancellable = NotificationCenter.default.publisher(for: .shortcutRegistrationDidChange)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                let registrationMessageText = Self.registrationMessageText(from: store.loadRegistrationMessages())
                guard registrationMessageText != self.registrationMessageText else {
                    return
                }

                self.registrationMessageText = registrationMessageText
            }
    }

    public func registrationMessage() -> String? {
        registrationMessageText.currentAppWindowSwitching
    }

    public func refreshPermissionState() {
        let refreshedPermissionState = permissionStateProvider()
        guard refreshedPermissionState != permissionState else {
            return
        }

        permissionState = refreshedPermissionState
    }

    @discardableResult
    public func save(
        keyEquivalent: String,
        keyCode: UInt16? = nil,
        modifiers: [String],
        isUsable: Bool
    ) -> Bool {
        let current = currentAppWindowShortcut
        let candidate = current.replacingWithValidation(
            keyEquivalent: keyEquivalent,
            keyCode: keyCode,
            modifiers: modifiers,
            isUsable: isUsable
        )
        guard candidate != current else {
            setErrorMessage(nil)
            return true
        }

        let validationResult = validator.validate(
            candidate,
            existing: []
        )

        guard validationResult == .valid else {
            setErrorMessage(errorMessage(for: validationResult))
            return false
        }

        do {
            try store.save(candidate)
            assign(candidate)
            setErrorMessage(nil)
            let updatedSettings = [currentAppWindowShortcut]
            onValidSettingsChanged(updatedSettings)
            NotificationCenter.default.post(
                name: .shortcutSettingsDidChange,
                object: nil,
                userInfo: ["settings": updatedSettings]
            )
            return true
        } catch {
            setErrorMessage("Shortcut could not be saved.")
            return false
        }
    }

    @discardableResult
    public func record(
        capture: ShortcutCapture,
        isUsable: Bool
    ) -> Bool {
        save(
            keyEquivalent: capture.keyEquivalent,
            keyCode: capture.keyCode,
            modifiers: capture.modifiers,
            isUsable: isUsable
        )
    }

    @discardableResult
    public func resetToDefault() -> Bool {
        return save(
            keyEquivalent: ShortcutSetting.defaultCurrentAppWindowSwitching.keyEquivalent,
            keyCode: ShortcutSetting.defaultCurrentAppWindowSwitching.keyCode,
            modifiers: ShortcutSetting.defaultCurrentAppWindowSwitching.modifiers,
            isUsable: true
        )
    }

    private func assign(_ setting: ShortcutSetting) {
        currentAppWindowShortcut = setting
    }

    private func setErrorMessage(_ message: String?) {
        guard errorMessage != message else {
            return
        }

        errorMessage = message
    }

    private static func registrationMessageText(
        from messages: [ShortcutRegistrationMessage]
    ) -> RegistrationMessageText {
        guard !messages.isEmpty else {
            return .empty
        }

        var currentAppWindowSwitchingText = ""

        for message in messages {
            append(message.message, to: &currentAppWindowSwitchingText)
        }

        return RegistrationMessageText(
            currentAppWindowSwitching: currentAppWindowSwitchingText.isEmpty ? nil : currentAppWindowSwitchingText
        )
    }

    private static func append(_ message: String, to text: inout String) {
        guard !text.isEmpty else {
            text = message
            return
        }

        text += " "
        text += message
    }

    private func errorMessage(for result: ShortcutValidationResult) -> String {
        switch result {
        case .valid:
            ""
        case .duplicate:
            "Shortcut is already used by another switcher mode."
        case .missingModifier:
            "Shortcut must include at least one modifier."
        case .unusable:
            "Shortcut cannot be registered by macOS."
        }
    }
}
