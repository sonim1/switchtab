import AppKit
import CoreGraphics

enum WindowPlacementPolicy {
    static func centeredOrigin(windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )
    }

    @MainActor
    static func centerWindowIfNeeded(_ window: NSWindow, screenFrame: CGRect?) {
        guard !window.isVisible,
              let screenFrame else {
            return
        }

        window.setFrameOrigin(
            centeredOrigin(windowSize: window.frame.size, screenFrame: screenFrame)
        )
    }
}

public enum SwitcherOverlayPresentationPolicy {
    public static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    public static let canBecomeKey = true
    public static let canBecomeMain = false

    public static func panelOrigin(panelSize: CGSize, screenFrame: CGRect) -> CGPoint {
        WindowPlacementPolicy.centeredOrigin(
            windowSize: panelSize,
            screenFrame: screenFrame
        )
    }

    public static func activeScreenFrame(
        pointerLocation: CGPoint,
        screenFrames: [CGRect],
        fallback: CGRect?
    ) -> CGRect? {
        screenFrames.first { $0.contains(pointerLocation) } ?? fallback
    }
}

public enum SwitcherOverlayEventMonitorPolicy {
    public static let localMask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .mouseMoved]
    public static let globalMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .flagsChanged,
        .mouseMoved
    ]
}

enum SwitcherOverlayEventTapDecision: Equatable, Sendable {
    case passThrough
    case consume(SwitcherCommand)
    case handleAndPassThrough(SwitcherCommand)
    /// Swallow the key without acting on it, so a held key cannot repeat a
    /// destructive command while the overlay still owns the keyboard.
    case consumeWithoutCommand
    case reenable
}

enum SwitcherOverlayTriggerPolicy {
    static func command(
        keyCode: UInt16,
        modifiers: SwitcherShortcutModifiers,
        triggerShortcut: ShortcutSetting?
    ) -> SwitcherCommand? {
        guard let triggerShortcut,
              triggerShortcut.isUsable,
              let triggerKeyCode = triggerShortcut.keyCode
                ?? ShortcutKeyCodeResolver.keyCode(for: triggerShortcut.keyEquivalent),
              keyCode == triggerKeyCode else {
            return nil
        }

        let forwardModifiers = SwitcherShortcutModifiers(
            modifiers: triggerShortcut.modifiers
        )
        if modifiers == forwardModifiers {
            return .moveDown
        }

        let reverseShortcut = triggerShortcut.reverseVariant(
            id: "\(triggerShortcut.id)-overlay-reverse"
        )
        let reverseModifiers = SwitcherShortcutModifiers(
            modifiers: reverseShortcut.modifiers
        )
        return modifiers == reverseModifiers ? .moveUp : nil
    }
}

enum SwitcherOverlayEventTapPolicy {
    static let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    static func decision(
        eventType: CGEventType,
        keyCode: UInt16,
        isAutorepeat: Bool,
        modifiers: SwitcherShortcutModifiers = [],
        triggerReleaseModifiers: SwitcherShortcutModifiers? = nil,
        triggerShortcut: ShortcutSetting? = nil
    ) -> SwitcherOverlayEventTapDecision {
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .reenable
        case .flagsChanged:
            let decision = SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: modifiers),
                triggerReleaseModifiers: triggerReleaseModifiers
            )
            return decision == .releaseShortcut
                ? .handleAndPassThrough(.releaseShortcut)
                : .passThrough
        case .keyDown:
            if let triggerCommand = SwitcherOverlayTriggerPolicy.command(
                keyCode: keyCode,
                modifiers: modifiers,
                triggerShortcut: triggerShortcut
            ) {
                return .consume(triggerCommand)
            }
            guard let command = SwitcherCommand(keyCode: keyCode, modifiers: modifiers) else {
                return .passThrough
            }
            guard !(isAutorepeat && command.repeatsAreDestructive) else {
                return .consumeWithoutCommand
            }
            return .consume(command)
        default:
            return .passThrough
        }
    }
}
