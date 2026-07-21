import AppKit
import Foundation
import SwitchTab

enum ShortcutCaptureTests {
    static func run() throws {
        try testDisplayTextShowsAllModifiersInStableOrder()
        try testDisplayTextDoesNotRequireCommandModifier()
        try testDisplayTextWithoutModifiersReturnsKeyOnly()
        try testDisplayTextWithSingleModifierUsesExpectedName()
        try testWonCurrencyKeyNormalizesToBacktick()
        try testShortcutCaptureUsesKeyCodeForCanonicalKeyEquivalent()
        try testShortcutSettingStoresNormalizedShortcutValue()
        try testShortcutSettingDecodingNormalizesShortcutValue()
        try testShortcutSettingDecodingInfersLegacyKeyCode()
        try testReverseVariantTogglesShiftModifier()
        try testReverseVariantKeepsPhysicalKeyCode()
        try testViewModelSavesRecordedShortcut()
        try testViewModelSavesRecordedShortcutKeyCodeIndependentOfInputLanguage()
        try testCocoaModifierResolverReturnsShortcutModifiers()
        try testCocoaModifierResolverReturnsShortcutModifierNames()
    }

    static func testDisplayTextShowsAllModifiersInStableOrder() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "k",
            modifiers: ["shift", "command", "option", "control"],
            isUsable: true
        )

        try expectEqual(setting.keyEquivalent, "K")
        try expectEqual(setting.modifiers, ["command", "option", "control", "shift"])
        try expectEqual(setting.displayText, "Cmd + Option + Ctrl + Shift + K")
    }

    static func testDisplayTextDoesNotRequireCommandModifier() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "`",
            modifiers: ["control", "option"],
            isUsable: true
        )

        try expectEqual(setting.displayText, "Option + Ctrl + `")
    }

    static func testDisplayTextWithoutModifiersReturnsKeyOnly() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            modifiers: [],
            isUsable: true
        )

        try expectEqual(setting.modifiers, [])
        try expectEqual(setting.displayText, "K")
    }

    static func testDisplayTextWithSingleModifierUsesExpectedName() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "`",
            modifiers: ["command"],
            isUsable: true
        )

        try expectEqual(setting.displayText, "Cmd + `")
    }

    static func testWonCurrencyKeyNormalizesToBacktick() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "₩",
            modifiers: ["command"],
            isUsable: true
        )

        try expectEqual(setting.keyEquivalent, "`")
        try expectEqual(setting.displayText, "Cmd + `")
    }

    static func testShortcutCaptureUsesKeyCodeForCanonicalKeyEquivalent() throws {
        let capture = ShortcutCapture(keyEquivalent: "λ", modifiers: ["command"], keyCode: 40)

        try expectEqual(capture.keyEquivalent, "K")
        try expectEqual(capture.keyCode, 40)
        try expectEqual(capture.modifiers, ["command"])
    }

    static func testShortcutSettingStoresNormalizedShortcutValue() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "j",
            modifiers: ["shift", "control", "command", "option"],
            isUsable: true
        )

        try expectEqual(setting.keyEquivalent, "J")
        try expectEqual(setting.keyCode, 38)
        try expectEqual(setting.modifiers, ["command", "option", "control", "shift"])
    }

    static func testShortcutSettingDecodingNormalizesShortcutValue() throws {
        let data = Data(
            """
            {
              "id": "custom",
              "mode": "currentAppWindowSwitching",
              "keyEquivalent": "j",
              "modifiers": ["shift", "control", "command", "option"],
              "isUsable": true,
              "lastValidValue": {
                "keyEquivalent": "k",
                "modifiers": ["control", "command"]
              }
            }
            """.utf8
        )

        let setting = try JSONDecoder().decode(ShortcutSetting.self, from: data)

        try expectEqual(setting.keyEquivalent, "J")
        try expectEqual(setting.keyCode, 38)
        try expectEqual(setting.modifiers, ["command", "option", "control", "shift"])
        try expectEqual(setting.lastValidValue?.keyEquivalent, "K")
        try expectEqual(setting.lastValidValue?.keyCode, 40)
        try expectEqual(setting.lastValidValue?.modifiers, ["command", "control"])
    }

    static func testShortcutSettingDecodingInfersLegacyKeyCode() throws {
        let data = Data(
            """
            {
              "id": "custom",
              "mode": "currentAppWindowSwitching",
              "keyEquivalent": "`",
              "modifiers": ["command"],
              "isUsable": true
            }
            """.utf8
        )

        let setting = try JSONDecoder().decode(ShortcutSetting.self, from: data)

        try expectEqual(setting.keyEquivalent, "`")
        try expectEqual(setting.keyCode, 50)
        try expectEqual(setting.modifiers, ["command"])
    }

    static func testReverseVariantTogglesShiftModifier() throws {
        let reverse = ShortcutSetting.defaultCurrentAppWindowSwitching.reverseVariant(id: "current-app-window-switching-reverse")

        try expectEqual(reverse.keyEquivalent, "`")
        try expectEqual(reverse.modifiers, ["command", "shift"])
        try expectEqual(reverse.displayText, "Cmd + Shift + `")

        let forwardWithShift = ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
            keyEquivalent: "K",
            modifiers: ["command", "shift"],
            isUsable: true
        )

        let reverseWithoutShift = forwardWithShift.reverseVariant(id: "custom-reverse")

        try expectEqual(reverseWithoutShift.modifiers, ["command"])
    }

    static func testReverseVariantKeepsPhysicalKeyCode() throws {
        let setting = ShortcutSetting(
            id: "custom",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "λ",
            keyCode: 40,
            modifiers: ["command"],
            isUsable: true
        )

        let reverse = setting.reverseVariant(id: "custom-reverse")

        try expectEqual(reverse.keyEquivalent, "K")
        try expectEqual(reverse.keyCode, 40)
        try expectEqual(reverse.modifiers, ["command", "shift"])
    }

    static func testViewModelSavesRecordedShortcut() throws {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let viewModel = ShortcutSettingsViewModel(store: store)

        let saved = viewModel.record(
            capture: ShortcutCapture(keyEquivalent: "j", modifiers: ["option", "control"]),
            isUsable: true
        )

        try expectTrue(saved)
        try expectEqual(store.load().keyEquivalent, "J")
        try expectEqual(store.load().modifiers, ["option", "control"])
    }

    static func testViewModelSavesRecordedShortcutKeyCodeIndependentOfInputLanguage() throws {
        let suiteName = "SwitchTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(userDefaults: defaults)
        let viewModel = ShortcutSettingsViewModel(store: store)

        let saved = viewModel.record(
            capture: ShortcutCapture(keyEquivalent: "λ", modifiers: ["command"], keyCode: 40),
            isUsable: true
        )

        try expectTrue(saved)
        try expectEqual(store.load().keyEquivalent, "K")
        try expectEqual(store.load().keyCode, 40)
        try expectEqual(store.load().modifiers, ["command"])
    }

    static func testCocoaModifierResolverReturnsShortcutModifiers() throws {
        try expectEqual(
            ShortcutModifierResolver.shortcutModifiers(from: [.command]),
            .command
        )
        try expectEqual(
            ShortcutModifierResolver.shortcutModifiers(from: [.option, .control]),
            [.option, .control]
        )
        try expectEqual(
            ShortcutModifierResolver.shortcutModifiers(from: [.command, .shift]),
            [.command, .shift]
        )
        try expectEqual(
            ShortcutModifierResolver.shortcutModifiers(from: [.option, .control, .shift]),
            [.option, .control, .shift]
        )
    }

    static func testCocoaModifierResolverReturnsShortcutModifierNames() throws {
        try expectEqual(
            ShortcutModifierResolver.modifierNames(from: []),
            []
        )
        try expectEqual(
            ShortcutModifierResolver.modifierNames(from: [.command]),
            ["command"]
        )
        try expectEqual(
            ShortcutModifierResolver.modifierNames(from: [.option, .control]),
            ["option", "control"]
        )
        try expectEqual(
            ShortcutModifierResolver.modifierNames(from: [.command, .option, .control, .shift]),
            ["command", "option", "control", "shift"]
        )
    }
}
