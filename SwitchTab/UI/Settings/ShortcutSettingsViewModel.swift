import Combine
import Foundation

public extension Notification.Name {
    static let shortcutSettingsDidChange = Notification.Name("SwitchTab.shortcutSettingsDidChange")
    static let shortcutRegistrationDidChange = Notification.Name("SwitchTab.shortcutRegistrationDidChange")
    static let shortcutRecordingDidBegin = Notification.Name("SwitchTab.shortcutRecordingDidBegin")
    static let shortcutRecordingDidEnd = Notification.Name("SwitchTab.shortcutRecordingDidEnd")
}

public enum ShortcutChangeResult: Equatable, Sendable {
    case applied
    case rejectedPreviousRestored
    case rollbackFailed
}

public final class ShortcutSettingsViewModel: ObservableObject {
    private struct ModeMessageText: Equatable {
        var currentAppWindowSwitching: String?
        var applicationSwitching: String?

        static let empty = ModeMessageText(
            currentAppWindowSwitching: nil,
            applicationSwitching: nil
        )

        func message(for mode: SwitcherMode) -> String? {
            switch mode {
            case .currentAppWindowSwitching:
                currentAppWindowSwitching
            case .applicationSwitching:
                applicationSwitching
            }
        }

        mutating func set(_ message: String?, for mode: SwitcherMode) {
            switch mode {
            case .currentAppWindowSwitching:
                currentAppWindowSwitching = message
            case .applicationSwitching:
                applicationSwitching = message
            }
        }
    }

    private struct ShortcutState: Equatable {
        var configurations: [SwitcherShortcutConfiguration]
        var errorMessageText: ModeMessageText
    }

    @Published public private(set) var permissionState: PermissionState
    @Published private var shortcutState: ShortcutState
    @Published private var registrationMessageText: ModeMessageText

    private let validator: ShortcutValidationService
    private let permissionStateProvider: () -> PermissionState
    private let saveConfigurations: ([SwitcherShortcutConfiguration]) throws -> Void
    private let onShortcutChanged: (
        SwitcherShortcutConfiguration,
        SwitcherShortcutConfiguration
    ) -> ShortcutChangeResult
    private let onEnabledChanged: (SwitcherShortcutConfiguration) -> Void
    private var registrationMessageCancellable: AnyCancellable?

    public init(
        store: ShortcutSettingsStore = ShortcutSettingsStore(),
        validator: ShortcutValidationService = ShortcutValidationService(),
        permissionStateProvider: @escaping () -> PermissionState = { PermissionService().currentState() },
        saveConfigurations: (([SwitcherShortcutConfiguration]) throws -> Void)? = nil,
        onShortcutChanged: @escaping (
            SwitcherShortcutConfiguration,
            SwitcherShortcutConfiguration
        ) -> ShortcutChangeResult = { _, _ in .applied },
        onEnabledChanged: @escaping (SwitcherShortcutConfiguration) -> Void = { _ in }
    ) {
        let configurations = store.loadConfigurations()
        let loadedRegistrationMessages = store.loadRegistrationMessages()
        let registrationMessageText = Self.registrationMessageText(from: loadedRegistrationMessages)

        self.validator = validator
        self.permissionStateProvider = permissionStateProvider
        self.saveConfigurations = saveConfigurations ?? { try store.saveConfigurations($0) }
        self.onShortcutChanged = onShortcutChanged
        self.onEnabledChanged = onEnabledChanged
        self.permissionState = permissionStateProvider()
        self.shortcutState = ShortcutState(
            configurations: configurations,
            errorMessageText: .empty
        )
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

    // TODO(Task 5): Remove this deprecated compatibility shim when the settings UI uses configuration(for:).
    public var currentAppWindowShortcut: ShortcutSetting {
        configuration(for: .currentAppWindowSwitching).shortcut
    }

    // TODO(Task 5): Remove this deprecated compatibility shim when errors render per mode.
    public var errorMessage: String? {
        errorMessage(for: .currentAppWindowSwitching)
            ?? errorMessage(for: .applicationSwitching)
    }

    // TODO(Task 4): Remove this deprecated initializer after callback wiring accepts configurations.
    public convenience init(
        store: ShortcutSettingsStore = ShortcutSettingsStore(),
        validator: ShortcutValidationService = ShortcutValidationService(),
        permissionStateProvider: @escaping () -> PermissionState = { PermissionService().currentState() },
        onValidSettingsChanged: @escaping (
            ShortcutSetting,
            ShortcutSetting
        ) -> ShortcutChangeResult
    ) {
        self.init(
            store: store,
            validator: validator,
            permissionStateProvider: permissionStateProvider,
            onShortcutChanged: { candidate, previous in
                onValidSettingsChanged(candidate.shortcut, previous.shortcut)
            }
        )
    }

    public func configuration(for mode: SwitcherMode) -> SwitcherShortcutConfiguration {
        shortcutState.configurations.first { $0.mode == mode }
            ?? .defaultValue(for: mode)
    }

    public func errorMessage(for mode: SwitcherMode) -> String? {
        shortcutState.errorMessageText.message(for: mode)
    }

    public func registrationMessage(for mode: SwitcherMode) -> String? {
        registrationMessageText.message(for: mode)
    }

    public func registrationMessage() -> String? {
        registrationMessage(for: .currentAppWindowSwitching)
    }

    public func applicationSwitchingRegistrationMessage() -> String? {
        registrationMessage(for: .applicationSwitching)
    }

    public func refreshPermissionState() {
        let refreshedPermissionState = permissionStateProvider()
        guard refreshedPermissionState != permissionState else {
            return
        }

        permissionState = refreshedPermissionState
    }

    public func setEnabled(_ enabled: Bool, for mode: SwitcherMode) {
        guard let index = index(for: mode) else {
            return
        }

        let previous = shortcutState.configurations[index]
        guard previous.isEnabled != enabled else {
            return
        }

        var candidate = previous
        candidate.isEnabled = enabled
        var configurations = shortcutState.configurations
        configurations[index] = candidate

        do {
            try saveConfigurations(configurations)
        } catch {
            setErrorMessage("Shortcut could not be saved.", for: mode)
            return
        }

        assign(configurations: configurations, clearingErrorFor: mode)
        postSettingsDidChange(configurations)
        onEnabledChanged(candidate)
    }

    @discardableResult
    public func record(capture: ShortcutCapture, for mode: SwitcherMode) -> Bool {
        updateShortcut(
            keyEquivalent: capture.keyEquivalent,
            keyCode: capture.keyCode,
            modifiers: capture.modifiers,
            isUsable: true,
            for: mode
        )
    }

    @discardableResult
    public func resetToDefault(for mode: SwitcherMode) -> Bool {
        let defaultShortcut = SwitcherShortcutConfiguration.defaultValue(for: mode).shortcut
        return updateShortcut(
            keyEquivalent: defaultShortcut.keyEquivalent,
            keyCode: defaultShortcut.keyCode,
            modifiers: defaultShortcut.modifiers,
            isUsable: defaultShortcut.isUsable,
            for: mode
        )
    }

    // TODO(Task 5): Remove this deprecated window-only compatibility API with the old settings row.
    @discardableResult
    public func save(
        keyEquivalent: String,
        keyCode: UInt16? = nil,
        modifiers: [String],
        isUsable: Bool
    ) -> Bool {
        updateShortcut(
            keyEquivalent: keyEquivalent,
            keyCode: keyCode,
            modifiers: modifiers,
            isUsable: isUsable,
            for: .currentAppWindowSwitching
        )
    }

    // TODO(Task 5): Remove this deprecated window-only compatibility API with the old settings row.
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

    // TODO(Task 5): Remove this deprecated window-only compatibility API with the old settings row.
    @discardableResult
    public func resetToDefault() -> Bool {
        resetToDefault(for: .currentAppWindowSwitching)
    }

    private func updateShortcut(
        keyEquivalent: String,
        keyCode: UInt16?,
        modifiers: [String],
        isUsable: Bool,
        for mode: SwitcherMode
    ) -> Bool {
        guard let index = index(for: mode) else {
            return false
        }

        let previous = shortcutState.configurations[index]
        let candidateShortcut = previous.shortcut.replacingWithValidation(
            keyEquivalent: keyEquivalent,
            keyCode: keyCode,
            modifiers: modifiers,
            isUsable: isUsable
        )
        var candidate = previous
        candidate.shortcut = candidateShortcut
        guard candidate != previous else {
            setErrorMessage(nil, for: mode)
            return true
        }

        guard let other = shortcutState.configurations.first(where: { $0.mode != mode }) else {
            return false
        }
        let validationResult = validationResult(
            for: candidate.shortcut,
            other: other.shortcut
        )
        guard validationResult == .valid else {
            setErrorMessage(validationErrorMessage(for: validationResult), for: mode)
            return false
        }

        switch onShortcutChanged(candidate, previous) {
        case .applied:
            break
        case .rejectedPreviousRestored:
            setErrorMessage(
                "Shortcut could not be registered. The previous shortcut is still active.",
                for: mode
            )
            return false
        case .rollbackFailed:
            setErrorMessage(
                "Shortcut could not be registered, and the previous shortcut could not be restored.",
                for: mode
            )
            return false
        }

        var configurations = shortcutState.configurations
        configurations[index] = candidate
        do {
            try saveConfigurations(configurations)
        } catch {
            let didRestorePreviousShortcut = onShortcutChanged(previous, candidate) == .applied
            setErrorMessage(
                didRestorePreviousShortcut
                    ? "Shortcut could not be saved."
                    : "Shortcut could not be saved, and the previous shortcut could not be restored.",
                for: mode
            )
            return false
        }

        assign(configurations: configurations, clearingErrorFor: mode)
        postSettingsDidChange(configurations)
        return true
    }

    private func validationResult(
        for candidate: ShortcutSetting,
        other: ShortcutSetting
    ) -> ShortcutValidationResult {
        let otherReverse = other.reverseVariant(id: "\(other.id)-reverse")
        let existing = [other, otherReverse]
        let forwardResult = validator.validate(candidate, existing: existing)
        guard forwardResult == .valid else {
            return forwardResult
        }

        return validator.validate(
            candidate.reverseVariant(id: "\(candidate.id)-reverse"),
            existing: existing
        )
    }

    private func index(for mode: SwitcherMode) -> Int? {
        shortcutState.configurations.firstIndex { $0.mode == mode }
    }

    private func assign(
        configurations: [SwitcherShortcutConfiguration],
        clearingErrorFor mode: SwitcherMode
    ) {
        var updatedState = shortcutState
        updatedState.configurations = configurations
        updatedState.errorMessageText.set(nil, for: mode)
        guard updatedState != shortcutState else {
            return
        }

        shortcutState = updatedState
    }

    private func setErrorMessage(_ message: String?, for mode: SwitcherMode) {
        guard shortcutState.errorMessageText.message(for: mode) != message else {
            return
        }

        var updatedState = shortcutState
        updatedState.errorMessageText.set(message, for: mode)
        shortcutState = updatedState
    }

    private func postSettingsDidChange(_ configurations: [SwitcherShortcutConfiguration]) {
        NotificationCenter.default.post(
            name: .shortcutSettingsDidChange,
            object: nil,
            userInfo: ["settings": configurations.map(\.shortcut)]
        )
    }

    private static func registrationMessageText(
        from messages: [ShortcutRegistrationMessage]
    ) -> ModeMessageText {
        guard !messages.isEmpty else {
            return .empty
        }

        var currentAppWindowSwitchingText = ""
        var applicationSwitchingText = ""

        for message in messages {
            switch message.mode {
            case .currentAppWindowSwitching:
                append(message.message, to: &currentAppWindowSwitchingText)
            case .applicationSwitching:
                append(message.message, to: &applicationSwitchingText)
            }
        }

        return ModeMessageText(
            currentAppWindowSwitching: currentAppWindowSwitchingText.isEmpty ? nil : currentAppWindowSwitchingText,
            applicationSwitching: applicationSwitchingText.isEmpty ? nil : applicationSwitchingText
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

    private func validationErrorMessage(for result: ShortcutValidationResult) -> String {
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
