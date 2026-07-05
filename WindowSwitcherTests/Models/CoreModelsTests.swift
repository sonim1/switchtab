import Foundation
import WindowSwitcher

enum CoreModelsTests {
    static func run() throws {
        try testSwitcherModeNamesAreStable()
        try testPermissionStateBlocksOnlyMissingCapabilities()
        try testShortcutSettingRejectsUnusableReplacement()
    }

    static func testSwitcherModeNamesAreStable() throws {
        try expectEqual(SwitcherMode.currentAppWindowSwitching.displayName, "Current App Windows")
        try expectEqual(SwitcherMode.currentAppWindowSwitching.displayName, "Current App Windows")
    }

    static func testPermissionStateBlocksOnlyMissingCapabilities() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .granted)

        try expectTrue(state.blocksFocusChanges)
        try expectFalse(state.blocksWindowPreviews)
        try expectEqual(state.permissionStatusItems.first?.permissionName, "Accessibility")
    }

    static func testShortcutSettingRejectsUnusableReplacement() throws {
        let original = ShortcutSetting.defaultCurrentAppWindowSwitching
        let rejected = original.replacingWithValidation(
            keyEquivalent: "A",
            modifiers: [],
            isUsable: false
        )

        try expectEqual(rejected.keyEquivalent, original.keyEquivalent)
        try expectEqual(rejected.modifiers, original.modifiers)
        try expectFalse(rejected.isUsable)
        try expectEqual(rejected.lastValidValue?.keyEquivalent, original.keyEquivalent)
    }
}
