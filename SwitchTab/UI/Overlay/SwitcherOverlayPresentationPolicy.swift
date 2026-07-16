import AppKit

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
    public static let localMask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
    public static let globalMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .flagsChanged
    ]
}
