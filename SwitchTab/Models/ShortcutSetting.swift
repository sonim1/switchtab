public struct ShortcutValue: Codable, Equatable, Sendable {
    public let keyEquivalent: String
    public let keyCode: UInt16?
    public let modifiers: [String]

    public init(keyEquivalent: String, modifiers: [String], keyCode: UInt16? = nil) {
        self.keyEquivalent = keyEquivalent
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

}

public struct ShortcutCapture: Equatable, Sendable {
    public let keyEquivalent: String
    public let keyCode: UInt16?
    public let modifiers: [String]

    public init(keyEquivalent: String, modifiers: [String], keyCode: UInt16? = nil) {
        let normalizedKey = keyCode.flatMap(ShortcutKeyCodeResolver.keyEquivalent(for:))
            ?? Self.normalizedKey(keyEquivalent)
        self.keyEquivalent = normalizedKey
        self.keyCode = keyCode ?? ShortcutKeyCodeResolver.keyCode(for: normalizedKey)
        self.modifiers = Self.normalizedModifiers(modifiers)
    }

    fileprivate static func formattedDisplayText(keyEquivalent: String, modifiers: [String]) -> String {
        guard !modifiers.isEmpty else {
            return keyEquivalent
        }

        var text = ""
        text.reserveCapacity((modifiers.count * 8) + keyEquivalent.count)

        for modifier in modifiers {
            if !text.isEmpty {
                text += " + "
            }
            text += Self.displayName(for: modifier)
        }

        if !text.isEmpty {
            text += " + "
        }
        text += keyEquivalent
        return text
    }

    fileprivate static func normalizedKey(_ keyEquivalent: String) -> String {
        switch keyEquivalent {
        case " ":
            return "Space"
        case "\t":
            return "Tab"
        case "\r":
            return "Return"
        case "\u{1B}":
            return "Esc"
        case "\u{7F}":
            return "Delete"
        case "₩":
            return "`"
        default:
            if let normalizedASCIIKey = normalizedASCIIKey(keyEquivalent) {
                return normalizedASCIIKey
            }

            guard keyEquivalent.count == 1 else {
                return keyEquivalent
            }

            return keyEquivalent.uppercased()
        }
    }

    private static func normalizedASCIIKey(_ keyEquivalent: String) -> String? {
        let utf8 = keyEquivalent.utf8
        guard utf8.count == 1, let byte = utf8.first else {
            return nil
        }

        if byte >= 97 && byte <= 122 {
            return String(UnicodeScalar(byte - 32))
        }
        return keyEquivalent
    }

    fileprivate static func normalizedModifiers(_ modifiers: [String]) -> [String] {
        guard !modifiers.isEmpty else {
            return []
        }

        var hasCommand = false
        var hasOption = false
        var hasControl = false
        var hasShift = false

        for modifier in modifiers {
            switch Self.normalizedModifier(modifier) {
            case .command:
                hasCommand = true
            case .option:
                hasOption = true
            case .control:
                hasControl = true
            case .shift:
                hasShift = true
            case nil:
                break
            }
        }

        var normalized: [String] = []
        normalized.reserveCapacity(4)
        if hasCommand {
            normalized.append("command")
        }
        if hasOption {
            normalized.append("option")
        }
        if hasControl {
            normalized.append("control")
        }
        if hasShift {
            normalized.append("shift")
        }
        return normalized
    }

    fileprivate static func normalizedModifier(_ modifier: String) -> NormalizedShortcutModifier? {
        switch modifier {
        case "command":
            return .command
        case "option":
            return .option
        case "control":
            return .control
        case "shift":
            return .shift
        default:
            if Self.modifier(modifier, matches: "command") {
                return .command
            }
            if Self.modifier(modifier, matches: "option") {
                return .option
            }
            if Self.modifier(modifier, matches: "control") {
                return .control
            }
            if Self.modifier(modifier, matches: "shift") {
                return .shift
            }
            return nil
        }
    }

    fileprivate static func modifier(_ modifier: String, matches normalizedModifier: String) -> Bool {
        if modifier == normalizedModifier {
            return true
        }

        return Self.asciiCaseInsensitiveEquals(modifier, normalizedModifier)
    }

    private static func asciiCaseInsensitiveEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsUTF8 = lhs.utf8
        let rhsUTF8 = rhs.utf8
        var lhsIndex = lhsUTF8.startIndex
        var rhsIndex = rhsUTF8.startIndex

        while rhsIndex < rhsUTF8.endIndex {
            guard lhsIndex < lhsUTF8.endIndex,
                  asciiLowercased(lhsUTF8[lhsIndex]) == rhsUTF8[rhsIndex] else {
                return false
            }

            lhsIndex = lhsUTF8.index(after: lhsIndex)
            rhsIndex = rhsUTF8.index(after: rhsIndex)
        }

        return lhsIndex == lhsUTF8.endIndex
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }

    private static func displayName(for modifier: String) -> String {
        switch modifier {
        case "command":
            "Cmd"
        case "option":
            "Option"
        case "control":
            "Ctrl"
        case "shift":
            "Shift"
        default:
            modifier
        }
    }
}

fileprivate enum NormalizedShortcutModifier {
    case command
    case option
    case control
    case shift
}

public struct ShortcutRegistrationMessage: Codable, Equatable, Sendable {
    public let mode: SwitcherMode
    public let message: String

    public init(mode: SwitcherMode, message: String) {
        self.mode = mode
        self.message = message
    }
}

public enum ShortcutValidationResult: Equatable, Sendable {
    case valid
    case duplicate
    case missingModifier
    case unusable
}

public struct ShortcutSetting: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mode: SwitcherMode
    public let keyEquivalent: String
    public let keyCode: UInt16?
    public let modifiers: [String]
    public let isUsable: Bool
    public let lastValidValue: ShortcutValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case keyEquivalent
        case keyCode
        case modifiers
        case isUsable
        case lastValidValue
    }

    public init(
        id: String,
        mode: SwitcherMode,
        keyEquivalent: String,
        keyCode: UInt16? = nil,
        modifiers: [String],
        isUsable: Bool,
        lastValidValue: ShortcutValue? = nil
    ) {
        let normalizedKey = keyCode.flatMap(ShortcutKeyCodeResolver.keyEquivalent(for:))
            ?? ShortcutCapture.normalizedKey(keyEquivalent)
        let normalizedKeyCode = keyCode ?? ShortcutKeyCodeResolver.keyCode(for: normalizedKey)
        let normalizedModifiers = ShortcutCapture.normalizedModifiers(modifiers)
        let normalizedLastValidValue: ShortcutValue?
        if let lastValidValue {
            let normalizedLastValidKey = lastValidValue.keyCode.flatMap(ShortcutKeyCodeResolver.keyEquivalent(for:))
                ?? ShortcutCapture.normalizedKey(lastValidValue.keyEquivalent)
            normalizedLastValidValue = ShortcutValue(
                keyEquivalent: normalizedLastValidKey,
                modifiers: ShortcutCapture.normalizedModifiers(lastValidValue.modifiers),
                keyCode: lastValidValue.keyCode ?? ShortcutKeyCodeResolver.keyCode(for: normalizedLastValidKey)
            )
        } else {
            normalizedLastValidValue = nil
        }

        self.init(
            id: id,
            mode: mode,
            normalizedKey: normalizedKey,
            normalizedKeyCode: normalizedKeyCode,
            normalizedModifiers: normalizedModifiers,
            isUsable: isUsable,
            normalizedLastValidValue: normalizedLastValidValue
        )
    }

    private init(
        id: String,
        mode: SwitcherMode,
        normalizedKey: String,
        normalizedKeyCode: UInt16?,
        normalizedModifiers: [String],
        isUsable: Bool,
        normalizedLastValidValue: ShortcutValue?
    ) {
        self.id = id
        self.mode = mode
        self.keyEquivalent = normalizedKey
        self.keyCode = normalizedKeyCode
        self.modifiers = normalizedModifiers
        self.isUsable = isUsable
        self.lastValidValue = normalizedLastValidValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            mode: try container.decode(SwitcherMode.self, forKey: .mode),
            keyEquivalent: try container.decode(String.self, forKey: .keyEquivalent),
            keyCode: try container.decodeIfPresent(UInt16.self, forKey: .keyCode),
            modifiers: try container.decode([String].self, forKey: .modifiers),
            isUsable: try container.decode(Bool.self, forKey: .isUsable),
            lastValidValue: try container.decodeIfPresent(ShortcutValue.self, forKey: .lastValidValue)
        )
    }

    public static let defaultCurrentAppWindowSwitching = ShortcutSetting(
        id: "current-app-window-switching",
        mode: .currentAppWindowSwitching,
        normalizedKey: "`",
        normalizedKeyCode: 50,
        normalizedModifiers: ["command"],
        isUsable: true,
        normalizedLastValidValue: ShortcutValue(keyEquivalent: "`", modifiers: ["command"], keyCode: 50)
    )

    public static let fallbackCurrentAppWindowSwitching = ShortcutSetting(
        id: "current-app-window-switching-fallback",
        mode: .currentAppWindowSwitching,
        normalizedKey: "`",
        normalizedKeyCode: 50,
        normalizedModifiers: ["option", "control"],
        isUsable: true,
        normalizedLastValidValue: ShortcutValue(keyEquivalent: "`", modifiers: ["option", "control"], keyCode: 50)
    )

    public static let fallbackCurrentAppWindowSwitchingReverse = fallbackCurrentAppWindowSwitching.reverseVariant(
        id: "\(fallbackCurrentAppWindowSwitching.id)-reverse"
    )

    public var displayText: String {
        ShortcutCapture.formattedDisplayText(keyEquivalent: keyEquivalent, modifiers: modifiers)
    }

    public var displayName: String {
        mode.displayName
    }

    public var isDefault: Bool {
        keyEquivalent == Self.defaultCurrentAppWindowSwitching.keyEquivalent
            && modifiers == Self.defaultCurrentAppWindowSwitching.modifiers
    }

    func hasSamePhysicalKey(as other: ShortcutSetting) -> Bool {
        if let keyCode, let otherKeyCode = other.keyCode {
            return keyCode == otherKeyCode
        }

        return keyEquivalent == other.keyEquivalent
    }

    public func reverseVariant(id: String) -> ShortcutSetting {
        if modifiers == ["command"] {
            return reverseVariant(id: id, normalizedModifiers: ["command", "shift"])
        }

        if modifiers == ["command", "shift"] {
            return reverseVariant(id: id, normalizedModifiers: ["command"])
        }

        if modifiers == ["option", "control"] {
            return reverseVariant(id: id, normalizedModifiers: ["option", "control", "shift"])
        }

        if modifiers == ["option", "control", "shift"] {
            return reverseVariant(id: id, normalizedModifiers: ["option", "control"])
        }

        var hasCommand = false
        var hasOption = false
        var hasControl = false
        var removedShift = false

        for modifier in modifiers {
            switch modifier {
            case "command":
                hasCommand = true
            case "option":
                hasOption = true
            case "control":
                hasControl = true
            case "shift":
                removedShift = true
            default:
                break
            }
        }

        var normalizedModifiers: [String] = []
        normalizedModifiers.reserveCapacity(4)
        if hasCommand {
            normalizedModifiers.append("command")
        }
        if hasOption {
            normalizedModifiers.append("option")
        }
        if hasControl {
            normalizedModifiers.append("control")
        }
        if !removedShift {
            normalizedModifiers.append("shift")
        }

        return ShortcutSetting(
            id: id,
            mode: mode,
            normalizedKey: keyEquivalent,
            normalizedKeyCode: keyCode,
            normalizedModifiers: normalizedModifiers,
            isUsable: isUsable,
            normalizedLastValidValue: ShortcutValue(
                keyEquivalent: keyEquivalent,
                modifiers: normalizedModifiers,
                keyCode: keyCode
            )
        )
    }

    private func reverseVariant(id: String, normalizedModifiers: [String]) -> ShortcutSetting {
        ShortcutSetting(
            id: id,
            mode: mode,
            normalizedKey: keyEquivalent,
            normalizedKeyCode: keyCode,
            normalizedModifiers: normalizedModifiers,
            isUsable: isUsable,
            normalizedLastValidValue: ShortcutValue(
                keyEquivalent: keyEquivalent,
                modifiers: normalizedModifiers,
                keyCode: keyCode
            )
        )
    }

    public func replacingWithValidation(
        keyEquivalent: String,
        keyCode: UInt16? = nil,
        modifiers: [String],
        isUsable: Bool
    ) -> ShortcutSetting {
        if isUsable {
            let normalizedKey = keyCode.flatMap(ShortcutKeyCodeResolver.keyEquivalent(for:))
                ?? ShortcutCapture.normalizedKey(keyEquivalent)
            let normalizedKeyCode = keyCode ?? ShortcutKeyCodeResolver.keyCode(for: normalizedKey)
            let normalizedModifiers = ShortcutCapture.normalizedModifiers(modifiers)

            if canReuseValidatedShortcut(
                normalizedKey: normalizedKey,
                normalizedKeyCode: normalizedKeyCode,
                normalizedModifiers: normalizedModifiers
            ) {
                return self
            }

            return ShortcutSetting(
                id: id,
                mode: mode,
                normalizedKey: normalizedKey,
                normalizedKeyCode: normalizedKeyCode,
                normalizedModifiers: normalizedModifiers,
                isUsable: true,
                normalizedLastValidValue: ShortcutValue(
                    keyEquivalent: normalizedKey,
                    modifiers: normalizedModifiers,
                    keyCode: normalizedKeyCode
                )
            )
        }

        return ShortcutSetting(
            id: id,
            mode: mode,
            normalizedKey: self.keyEquivalent,
            normalizedKeyCode: self.keyCode,
            normalizedModifiers: self.modifiers,
            isUsable: false,
            normalizedLastValidValue: lastValidValue ?? ShortcutValue(
                keyEquivalent: self.keyEquivalent,
                modifiers: self.modifiers,
                keyCode: self.keyCode
            )
        )
    }

    private func canReuseValidatedShortcut(
        normalizedKey: String,
        normalizedKeyCode: UInt16?,
        normalizedModifiers: [String]
    ) -> Bool {
        guard isUsable,
              keyEquivalent == normalizedKey,
              keyCode == normalizedKeyCode,
              modifiers == normalizedModifiers,
              lastValidValue?.keyEquivalent == normalizedKey,
              lastValidValue?.keyCode == normalizedKeyCode,
              lastValidValue?.modifiers == normalizedModifiers else {
            return false
        }

        return true
    }
}
