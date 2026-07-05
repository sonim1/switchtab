import AppKit

public enum ShortcutModifierResolver {
    private static let shortcutModifierMask = NSEvent.ModifierFlags.command.rawValue
        | NSEvent.ModifierFlags.option.rawValue
        | NSEvent.ModifierFlags.control.rawValue
        | NSEvent.ModifierFlags.shift.rawValue

    public static func shortcutModifiers(from modifierFlags: NSEvent.ModifierFlags) -> SwitcherShortcutModifiers {
        let activeShortcutModifierRawValue = modifierFlags.rawValue & Self.shortcutModifierMask
        guard activeShortcutModifierRawValue != 0 else {
            return []
        }

        var shortcutModifierRawValue: UInt8 = 0
        if activeShortcutModifierRawValue & NSEvent.ModifierFlags.command.rawValue != 0 {
            shortcutModifierRawValue |= SwitcherShortcutModifiers.command.rawValue
        }
        if activeShortcutModifierRawValue & NSEvent.ModifierFlags.option.rawValue != 0 {
            shortcutModifierRawValue |= SwitcherShortcutModifiers.option.rawValue
        }
        if activeShortcutModifierRawValue & NSEvent.ModifierFlags.control.rawValue != 0 {
            shortcutModifierRawValue |= SwitcherShortcutModifiers.control.rawValue
        }
        if activeShortcutModifierRawValue & NSEvent.ModifierFlags.shift.rawValue != 0 {
            shortcutModifierRawValue |= SwitcherShortcutModifiers.shift.rawValue
        }

        return SwitcherShortcutModifiers(rawValue: shortcutModifierRawValue)
    }

    public static func modifierNames(from modifierFlags: NSEvent.ModifierFlags) -> [String] {
        let shortcutModifiers = shortcutModifiers(from: modifierFlags)

        var names: [String] = []
        names.reserveCapacity(4)
        if shortcutModifiers.contains(.command) {
            names.append("command")
        }
        if shortcutModifiers.contains(.option) {
            names.append("option")
        }
        if shortcutModifiers.contains(.control) {
            names.append("control")
        }
        if shortcutModifiers.contains(.shift) {
            names.append("shift")
        }
        return names
    }
}
