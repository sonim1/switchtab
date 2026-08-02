public final class ApplicationSwitchingHotkeyController {
    public static let registrationFailureMessage =
        "Application switching needs Accessibility permission. Grant access in Permissions, then return to SwitchTab."

    private let hotkeyService: HotkeyService
    private var registrationMessages: [ShortcutRegistrationMessage] = []

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

        guard enabled else {
            return true
        }

        let forwardResult = hotkeyService.register(
            setting: setting,
            existing: existing,
            mode: .applicationSwitching,
            handler: forwardHandler
        )
        guard forwardResult == .registered else {
            return handleRegistrationFailure()
        }

        let reverseSetting = setting.reverseVariant(id: "application-switching-reverse")
        let reverseResult = hotkeyService.register(
            setting: reverseSetting,
            existing: existing + [setting],
            mode: .applicationSwitching,
            handler: reverseHandler
        )
        guard reverseResult == .registered else {
            return handleRegistrationFailure()
        }

        return true
    }

    public func unregisterAll() {
        hotkeyService.unregisterAll()
        registrationMessages.removeAll(keepingCapacity: true)
    }

    public func registrationMessageSnapshot() -> [ShortcutRegistrationMessage] {
        registrationMessages
    }

    private func handleRegistrationFailure() -> Bool {
        let serviceMessages = hotkeyService.registrationMessageSnapshot()
        let failureMode = serviceMessages.first(where: { $0.mode == .applicationSwitching })?.mode
            ?? .applicationSwitching
        hotkeyService.unregisterAll()
        registrationMessages = [
            ShortcutRegistrationMessage(
                mode: failureMode,
                message: Self.registrationFailureMessage
            )
        ]
        return false
    }
}
