import SwitchTab

enum ShortcutValidationTests {
    static func run() throws {
        try testDefaultShortcutsAreValid()
        try testUnusableShortcutIsRejected()
    }

    static func testDefaultShortcutsAreValid() throws {
        let validator = ShortcutValidationService()

        try expectEqual(
            validator.validate(
                .defaultCurrentAppWindowSwitching,
                existing: [.defaultCurrentAppWindowSwitching]
            ),
            .valid
        )
    }

    static func testUnusableShortcutIsRejected() throws {
        let setting = ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
            keyEquivalent: "A",
            modifiers: ["command"],
            isUsable: false
        )

        try expectEqual(ShortcutValidationService().validate(setting, existing: []), .unusable)
    }
}
