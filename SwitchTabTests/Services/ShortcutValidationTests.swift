import SwitchTab

enum ShortcutValidationTests {
    static func run() throws {
        try testDefaultShortcutsAreValid()
        try testUnusableShortcutIsRejected()
        try testOnlySuppliedShortcutsAreReserved()
        try testSuppliedPhysicalConflictIsRejected()
        try testMatchingIdentifiersDoNotHidePhysicalConflict()
        try testApplicationReverseVariantCannotCollideWithWindowShortcut()
    }

    static func testDefaultShortcutsAreValid() throws {
        let validator = ShortcutValidationService()

        try expectEqual(
            validator.validate(
                .defaultCurrentAppWindowSwitching,
                existing: []
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

    static func testOnlySuppliedShortcutsAreReserved() throws {
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

        try expectEqual(validator.validate(forwardWindowShortcut, existing: []), .valid)
        try expectEqual(validator.validate(reverseWindowShortcut, existing: []), .valid)
        try expectEqual(
            validator.validate(.defaultApplicationSwitching, existing: []),
            .valid
        )
        try expectEqual(
            validator.validate(.defaultApplicationSwitchingReverse, existing: []),
            .valid
        )
    }

    static func testSuppliedPhysicalConflictIsRejected() throws {
        let candidate = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            keyCode: 40,
            modifiers: ["option"],
            isUsable: true
        )
        let existing = ShortcutSetting(
            id: "application-switching",
            mode: .applicationSwitching,
            keyEquivalent: "λ",
            keyCode: 40,
            modifiers: ["option"],
            isUsable: true
        )

        try expectEqual(
            ShortcutValidationService().validate(candidate, existing: [existing]),
            .duplicate
        )
    }

    static func testMatchingIdentifiersDoNotHidePhysicalConflict() throws {
        let candidate = ShortcutSetting(
            id: "shared-id",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            keyCode: 40,
            modifiers: ["control"],
            isUsable: true
        )
        let existing = ShortcutSetting(
            id: "shared-id",
            mode: .applicationSwitching,
            keyEquivalent: "K",
            keyCode: 40,
            modifiers: ["control"],
            isUsable: true
        )

        try expectEqual(
            ShortcutValidationService().validate(candidate, existing: [existing]),
            .duplicate
        )
    }

    static func testApplicationReverseVariantCannotCollideWithWindowShortcut() throws {
        let application = ShortcutSetting(
            id: "application-switching",
            mode: .applicationSwitching,
            keyEquivalent: "K",
            modifiers: ["command"],
            isUsable: true
        )
        let window = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: ["command", "shift"],
            isUsable: true
        )

        try expectEqual(
            ShortcutValidationService().validate(
                application.reverseVariant(id: "application-switching-reverse"),
                existing: [window]
            ),
            .duplicate
        )
    }
}
