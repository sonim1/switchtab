import WindowSwitcher

enum PermissionServiceTests {
    static func run() throws {
        try testPermissionServiceBuildsPermissionStatusItems()
        try testShortcutValidationRejectsModifierlessShortcuts()
    }

    static func testPermissionServiceBuildsPermissionStatusItems() throws {
        let state = PermissionState(
            accessibility: .missing,
            screenRecording: .missing
        )

        try expectEqual(state.permissionStatusItems.map(\.permissionName), ["Accessibility", "Screen Recording"])
        try expectTrue(state.permissionStatusItems[0].detailText.contains("focus"))
        try expectTrue(state.permissionStatusItems[1].detailText.contains("System Settings"))
    }

    static func testShortcutValidationRejectsModifierlessShortcuts() throws {
        let validator = ShortcutValidationService()
        let modifierless = ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
            keyEquivalent: "K",
            modifiers: [],
            isUsable: true
        )

        try expectEqual(validator.validate(modifierless, existing: []), .missingModifier)
    }
}
