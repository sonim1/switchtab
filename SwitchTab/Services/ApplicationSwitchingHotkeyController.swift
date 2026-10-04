public final class ApplicationSwitchingHotkeyController {
    public static let registrationFailureMessage =
        "Application switching needs Accessibility permission. Grant access in Permissions, then return to SwitchTab."

    private let hotkeyService: HotkeyService
    private var registrationMessages: [ShortcutRegistrationMessage] = []
    /// Whether application switching currently owns its shortcut. Mode
    /// switching reads this so the overlay never consumes the application key
    /// while macOS still owns it.
    public private(set) var isRegistered = false

    public var registeredShortcut: ShortcutSetting? {
        isRegistered ? hotkeyService.registeredSetting(for: .applicationSwitching) : nil
    }

    public init() {
        hotkeyService = HotkeyService(
            registrar: EventTapHotkeyRegistrar(invokesHandlersForAutorepeat: true)
        )
    }

    public init(hotkeyService: HotkeyService) {
        self.hotkeyService = hotkeyService
    }

    @discardableResult
    public func updateRegistration(
        setting: ShortcutSetting,
        enabled: Bool,
        existing: [ShortcutSetting] = [],
        forwardHandler: @escaping () -> Void,
        reverseHandler: @escaping () -> Void
    ) -> Bool {
        hotkeyService.unregisterAll()
        registrationMessages.removeAll(keepingCapacity: true)
        isRegistered = false

        guard enabled else {
            return true
        }

        let forwardResult = hotkeyService.registerAttempt(
            setting: setting,
            existing: existing,
            mode: .applicationSwitching,
            handler: forwardHandler
        )
        guard forwardResult == .registered else {
            return handleRegistrationFailure(forwardResult)
        }

        let reverseSetting = setting.reverseVariant(id: "application-switching-reverse")
        let reverseResult = hotkeyService.registerAttempt(
            setting: reverseSetting,
            existing: existing + [setting],
            mode: .applicationSwitching,
            handler: reverseHandler
        )
        guard reverseResult == .registered else {
            return handleRegistrationFailure(reverseResult)
        }

        isRegistered = true
        return true
    }

    public func unregisterAll() {
        hotkeyService.unregisterAll()
        registrationMessages.removeAll(keepingCapacity: true)
        isRegistered = false
    }

    public func registrationMessageSnapshot() -> [ShortcutRegistrationMessage] {
        registrationMessages
    }

    private func handleRegistrationFailure(_ result: HotkeyRegistrationAttemptResult) -> Bool {
        isRegistered = false
        let serviceMessages = hotkeyService.registrationMessageSnapshot().filter {
            $0.mode == .applicationSwitching
        }
        hotkeyService.unregisterAll()
        registrationMessages = result == .rejectedByRegistrar ? [
            ShortcutRegistrationMessage(
                mode: .applicationSwitching,
                message: Self.registrationFailureMessage
            )
        ] : serviceMessages
        return false
    }
}
