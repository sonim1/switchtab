import CoreGraphics
import Foundation
@testable import SwitchTab

enum WindowCloseServiceTests {
    static func run() throws {
        try testMissingAccessibilityBlocksWindowClose()
        try testWindowCloseRequestsTargetWindow()
        try testFailedCloseReportsUnavailableTarget()
        try testCloseCommandNeedsCommandModifier()
        try testHeldCloseKeyDoesNotRepeatTheClose()
        try testCloseSelectedReportsCloseRequest()
        try testRemovingClosedItemKeepsOverlayOnNextWindow()
        try testRemovingLastItemDismissesOverlay()
        try testRemovingEarlierItemKeepsSelectionOnSameWindow()
        try testRemovingOutOfRangeItemIsIgnored()
        try testSnapshotResolvesElementsByIdentity()
        try testWindowTileRendersACloseButton()
    }

    static func testMissingAccessibilityBlocksWindowClose() throws {
        let closer = RecordingWindowCloser()
        let service = WindowCloseService(closer: closer)

        let result = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted)
        )

        try expectEqual(result, .permissionBlocked)
        try expectEqual(closer.requestedWindowIdentifier, nil)
    }

    static func testWindowCloseRequestsTargetWindow() throws {
        let closer = RecordingWindowCloser()
        let service = WindowCloseService(closer: closer)
        let window = WindowEdgeCaseTests.availableWindow()

        let result = service.close(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .closed)
        try expectEqual(closer.requestedWindowIdentifier, window.windowIdentifier)
    }

    static func testFailedCloseReportsUnavailableTarget() throws {
        let closer = RecordingWindowCloser(succeeds: false)
        let service = WindowCloseService(closer: closer)

        let result = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .unavailableTarget)
    }

    static func testCloseCommandNeedsCommandModifier() throws {
        try expectEqual(
            SwitcherCommand(keyCode: SwitcherCommand.closeSelectedKeyCode, modifiers: .command),
            .closeSelected
        )
        try expectEqual(
            SwitcherCommand(keyCode: SwitcherCommand.closeSelectedKeyCode, modifiers: [.command, .shift]),
            .closeSelected
        )
        try expectEqual(SwitcherCommand(keyCode: SwitcherCommand.closeSelectedKeyCode), nil)
        try expectEqual(
            SwitcherCommand(keyCode: SwitcherCommand.closeSelectedKeyCode, modifiers: .option),
            nil
        )
    }

    static func testHeldCloseKeyDoesNotRepeatTheClose() throws {
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: SwitcherCommand.closeSelectedKeyCode,
                isAutorepeat: false,
                modifiers: .command
            ),
            .consume(.closeSelected)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: SwitcherCommand.closeSelectedKeyCode,
                isAutorepeat: true,
                modifiers: .command
            ),
            .consumeWithoutCommand
        )
        // Navigation keys still repeat while held.
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 125,
                isAutorepeat: true
            ),
            .consume(.moveDown)
        )
    }

    static func testCloseSelectedReportsCloseRequest() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 3), selectedIndex: 1)

        let result = state.handle(.closeSelected)

        try expectEqual(result, .closeRequested(item: items(count: 3)[1], index: 1))
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.items.count, 3)
    }

    static func testRemovingClosedItemKeepsOverlayOnNextWindow() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 3), selectedIndex: 1)

        let result = state.removeItem(at: 1)

        try expectEqual(result, .updated)
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.items.map(\.id), ["window-0", "window-2"])
        try expectEqual(state.session?.selectedIndex, 1)
        try expectEqual(state.session?.selectedItem?.id, "window-2")
    }

    static func testRemovingLastItemDismissesOverlay() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 1))

        let result = state.removeItem(at: 0)

        try expectEqual(result, .cancelled)
        try expectFalse(state.isPresented)
        try expectEqual(state.session, nil)
    }

    static func testRemovingEarlierItemKeepsSelectionOnSameWindow() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 3), selectedIndex: 2)

        let result = state.removeItem(at: 0)

        try expectEqual(result, .updated)
        try expectEqual(state.session?.selectedIndex, 1)
        try expectEqual(state.session?.selectedItem?.id, "window-2")
    }

    static func testRemovingOutOfRangeItemIsIgnored() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 2))

        try expectEqual(state.removeItem(at: 5), SwitcherInteractionResult.none)
        try expectEqual(state.removeItem(at: -1), SwitcherInteractionResult.none)
        try expectEqual(state.session?.items.count, 2)
    }

    static func testSnapshotResolvesElementsByIdentity() throws {
        let windows = items(count: 3)
        let snapshot = SwitcherPresentationSnapshot(elements: windows, reverse: false) { $0 }

        // Closing shifts live indices, so identity lookup must stay stable.
        try expectEqual(snapshot.element(withID: "window-2")?.id, "window-2")
        try expectEqual(snapshot.element(withID: "missing")?.id, nil)
    }

    static func testWindowTileRendersACloseButton() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("SwitchTab/UI/Overlay/SwitcherIconStripView.swift"),
            encoding: .utf8
        )

        try expectTrue(source.contains("onClose(item, index)"))
        try expectTrue(source.contains("xmark.circle.fill"))
        try expectTrue(source.contains(".accessibilityLabel(Text(\"Close window\"))"))
    }

    private static func items(count: Int) -> [SwitcherListItem] {
        (0..<count).map { index in
            SwitcherListItem(id: "window-\(index)", title: "Window \(index)", subtitle: "App")
        }
    }
}

private final class RecordingWindowCloser: WindowClosing {
    private let succeeds: Bool
    private(set) var requestedWindowIdentifier: Int?

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    func close(window: WindowItem) -> Bool {
        requestedWindowIdentifier = window.windowIdentifier
        return succeeds
    }
}
