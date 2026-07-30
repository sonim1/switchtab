public struct ShortcutValidationService: Sendable {
    private static let applicationSwitchingReservedShortcuts: [ShortcutSetting] = [
        .defaultApplicationSwitching,
        .defaultApplicationSwitchingReverse
    ]

    public init() {}

    public func validate<Settings: Sequence>(
        _ setting: ShortcutSetting,
        existing settings: Settings
    ) -> ShortcutValidationResult where Settings.Element == ShortcutSetting {
        guard setting.isUsable else {
            return .unusable
        }

        guard !setting.modifiers.isEmpty else {
            return .missingModifier
        }

        if setting.mode == .currentAppWindowSwitching,
           Self.applicationSwitchingReservedShortcuts.contains(where: {
               $0.hasSamePhysicalKey(as: setting) && $0.modifiers == setting.modifiers
           }) {
            return .duplicate
        }

        for existingSetting in settings
            where existingSetting.id != setting.id
                && existingSetting.hasSamePhysicalKey(as: setting)
                && existingSetting.modifiers == setting.modifiers {
            return .duplicate
        }

        return .valid
    }
}
