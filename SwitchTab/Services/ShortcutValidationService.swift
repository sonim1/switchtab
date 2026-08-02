public struct ShortcutValidationService: Sendable {
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

        for existingSetting in settings
            where existingSetting.hasSamePhysicalKey(as: setting)
                && existingSetting.modifiers == setting.modifiers {
            return .duplicate
        }

        return .valid
    }
}
