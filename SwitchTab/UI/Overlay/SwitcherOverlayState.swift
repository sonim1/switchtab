import CoreGraphics

public enum SwitcherOverlayChromePolicy {
    public static let usesNativeBlurBackground = true
}

public enum SwitcherOverlayThumbnailPolicy {
    public static func showsThumbnails(for mode: SwitcherMode) -> Bool {
        mode == .currentAppWindowSwitching
    }
}

public enum SwitcherOverlayClosePolicy {
    public static func allowsClose(for mode: SwitcherMode) -> Bool {
        mode == .currentAppWindowSwitching
    }
}

public enum SwitcherOverlayAccessibilityPolicy {
    public static func switchHint(for mode: SwitcherMode) -> String {
        switch mode {
        case .currentAppWindowSwitching:
            return "Switch to this window."
        case .applicationSwitching:
            return "Switch to this application."
        }
    }
}

public struct SwitcherOverlayState: Equatable, Sendable {
    public private(set) var isPresented: Bool
    public private(set) var session: SwitcherSession?

    public init(
        isPresented: Bool = false,
        session: SwitcherSession? = nil
    ) {
        self.isPresented = isPresented
        self.session = session
    }

    public mutating func present(
        mode: SwitcherMode,
        items: [SwitcherListItem],
        selectedIndex: Int = 0
    ) {
        self.isPresented = true
        self.session = SwitcherSession(
            mode: mode,
            items: items,
            selectedIndex: selectedIndex
        )
    }

    public mutating func dismiss() {
        isPresented = false
        session = nil
    }

    public mutating func handle(_ command: SwitcherCommand) -> SwitcherInteractionResult {
        switch command {
        case .moveUp:
            return moveSelection(by: -1)
        case .moveDown:
            return moveSelection(by: 1)
        case .closeSelected:
            guard let activeSession = session,
                  SwitcherOverlayClosePolicy.allowsClose(for: activeSession.mode),
                  let selectedItem = activeSession.selectedItem else {
                return .none
            }

            return .closeRequested(item: selectedItem, index: activeSession.selectedIndex)
        case .quitSelectedApplication:
            guard let activeSession = session,
                  activeSession.mode == .applicationSwitching,
                  let selectedItem = activeSession.selectedItem else {
                return .none
            }

            return .quitRequested(item: selectedItem, index: activeSession.selectedIndex)
        case .confirm:
            guard let activeSession = session else {
                return .none
            }

            return confirm(activeSession.selectedItem, index: activeSession.selectedIndex)
        case .releaseShortcut:
            guard let activeSession = session else {
                return .none
            }

            guard let selectedItem = activeSession.selectedItem else {
                dismiss()
                return .cancelled
            }

            return confirm(selectedItem, index: activeSession.selectedIndex)
        case .cancel:
            guard session != nil else {
                return .none
            }

            dismiss()
            return .cancelled
        }
    }

    /// Applies a pointer hover to the highlight without confirming anything.
    public mutating func selectItem(at index: Int) -> SwitcherInteractionResult {
        guard session?.selectItem(at: index) == true else {
            return .none
        }

        return .updated
    }

    /// Drops a window that has just been closed. Dismisses when nothing is left.
    public mutating func removeItem(at index: Int) -> SwitcherInteractionResult {
        guard session?.removeItem(at: index) == true else {
            return .none
        }

        guard session?.items.isEmpty == false else {
            dismiss()
            return .cancelled
        }

        return .updated
    }

    /// Drops a confirmed-closed window by identity so selection changes cannot
    /// make a delayed Accessibility callback remove the wrong tile.
    public mutating func removeItem(withID id: String) -> SwitcherInteractionResult {
        guard session?.removeItem(withID: id) == true else {
            return .none
        }

        guard session?.items.isEmpty == false else {
            dismiss()
            return .cancelled
        }

        return .updated
    }

    private mutating func moveSelection(by delta: Int) -> SwitcherInteractionResult {
        guard session?.moveSelection(by: delta) == true else {
            return .none
        }

        return .updated
    }

    private mutating func confirm(_ selectedItem: SwitcherListItem?, index: Int) -> SwitcherInteractionResult {
        guard let selectedItem else {
            return .none
        }

        dismiss()
        return .confirmed(item: selectedItem, index: index)
    }
}

public enum SwitcherCommand: Equatable, Sendable {
    case moveUp
    case moveDown
    case confirm
    case releaseShortcut
    case cancel
    case closeSelected
    case quitSelectedApplication
}

public extension SwitcherCommand {
    /// Holding the key must not fire this command repeatedly.
    var repeatsAreDestructive: Bool {
        self == .closeSelected || self == .quitSelectedApplication
    }

    /// Key code 13 is `W`; it only closes while a modifier is held so the
    /// switcher never swallows a bare keystroke.
    static let closeSelectedKeyCode: UInt16 = 13
    /// Key code 12 is `Q`; Command-Q mirrors the native application switcher.
    static let quitSelectedApplicationKeyCode: UInt16 = 12

    init?(keyCode: UInt16, modifiers: SwitcherShortcutModifiers = []) {
        switch keyCode {
        case 36:
            self = .confirm
        case 53:
            self = .cancel
        case 123, 126:
            self = .moveUp
        case 124, 125:
            self = .moveDown
        case Self.closeSelectedKeyCode where modifiers.contains(.command):
            self = .closeSelected
        case Self.quitSelectedApplicationKeyCode where modifiers.contains(.command):
            self = .quitSelectedApplication
        default:
            return nil
        }
    }
}

public enum SwitcherInteractionResult: Equatable, Sendable {
    case none
    case updated
    case confirmed(item: SwitcherListItem, index: Int)
    case cancelled
    case closeRequested(item: SwitcherListItem, index: Int)
    case quitRequested(item: SwitcherListItem, index: Int)
}

public struct SwitcherShortcutModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = SwitcherShortcutModifiers(rawValue: 1 << 0)
    public static let option = SwitcherShortcutModifiers(rawValue: 1 << 1)
    public static let control = SwitcherShortcutModifiers(rawValue: 1 << 2)
    public static let shift = SwitcherShortcutModifiers(rawValue: 1 << 3)

    public init(modifiers: [String]) {
        var modifierRawValue: UInt8 = 0

        for modifier in modifiers {
            modifierRawValue |= Self.rawValue(for: modifier)
        }

        self.init(rawValue: modifierRawValue)
    }

    private static func rawValue(for modifier: String) -> UInt8 {
        switch modifier {
        case "command", "cmd":
            Self.command.rawValue
        case "option", "alt":
            Self.option.rawValue
        case "control", "ctrl":
            Self.control.rawValue
        case "shift":
            Self.shift.rawValue
        default:
            0
        }
    }

    public static func releaseRelevantModifiers(_ shortcut: ShortcutSetting) -> SwitcherShortcutModifiers {
        // Shift is treated as a non-releasing modifier: releasing it should not
        // dismiss the overlay, so dismissal tracks the non-shift modifiers. When
        // only shift is held, fall back to tracking shift itself.
        let allModifiers = SwitcherShortcutModifiers(modifiers: shortcut.modifiers)
        let nonShiftRawValue = allModifiers.rawValue & ~Self.shift.rawValue
        return nonShiftRawValue == 0 ? allModifiers : Self(rawValue: nonShiftRawValue)
    }
}

public enum SwitcherOverlayExternalEvent: Equatable, Sendable {
    case mouseDown
    case flagsChanged(activeModifiers: SwitcherShortcutModifiers)
}

public enum SwitcherOverlayExternalEventDecision: Equatable, Sendable {
    case none
    case cancel
    case releaseShortcut
}

public enum SwitcherOverlayExternalEventPolicy {
    public static func decision(
        for event: SwitcherOverlayExternalEvent,
        triggerReleaseModifiers: SwitcherShortcutModifiers?
    ) -> SwitcherOverlayExternalEventDecision {
        switch event {
        case .mouseDown:
            return .cancel
        case .flagsChanged(let activeModifiers):
            guard let triggerReleaseModifiers else {
                return activeModifiers.isEmpty ? .releaseShortcut : .none
            }

            return activeModifiers.rawValue & triggerReleaseModifiers.rawValue == 0
                ? .releaseShortcut
                : .none
        }
    }
}
