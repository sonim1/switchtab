import SwitchTab

enum ShortcutValidationTests {
    static func run() throws {
        try testDefaultShortcutsAreValid()
        try testUnusableShortcutIsRejected()
        try testApplicationShortcutsAreReservedFromWindowMode()
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

    static func testApplicationShortcutsAreReservedFromWindowMode() throws {
        let validator = ShortcutValidationService()
        let forwardWindowShortcut = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "Tab",
            keyCode: 48,
            modifiers: ["command"],
            isUsable: true
        )
        let reverseWindowShortcut = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "Tab",
            keyCode: 48,
            modifiers: ["command", "shift"],
            isUsable: true
        )

        try expectEqual(validator.validate(forwardWindowShortcut, existing: []), .duplicate)
        try expectEqual(validator.validate(reverseWindowShortcut, existing: []), .duplicate)
        try expectEqual(
            validator.validate(.defaultApplicationSwitching, existing: []),
            .valid
        )
        try expectEqual(
            validator.validate(.defaultApplicationSwitchingReverse, existing: []),
            .valid
        )
    }
}
