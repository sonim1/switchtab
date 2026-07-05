import WindowSwitcher

enum WindowFocusServiceTests {
    static func run() throws {
        try testUnavailableWindowIsNotFocused()
        try testMissingAccessibilityBlocksWindowFocus()
        try testWindowFocusRequestsTargetWindow()
        try testMinimizedWindowIsForwardedToFocuserForRestore()
    }

    static func testUnavailableWindowIsNotFocused() throws {
        let focuser = RecordingWindowFocuser()
        let service = WindowFocusService(focuser: focuser)
        var closed = WindowEdgeCaseTests.availableWindow()
        closed = WindowItem(
            windowIdentifier: closed.windowIdentifier,
            ownerProcessIdentifier: closed.ownerProcessIdentifier,
            ownerName: closed.switcherListItem.subtitle ?? "",
            title: closed.switcherListItem.title,
            isMinimized: closed.isMinimized,
            availability: .closed
        )

        let result = service.focus(
            closed,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .unavailableTarget)
        try expectEqual(focuser.requestedWindowIdentifier, nil)
    }

    static func testMissingAccessibilityBlocksWindowFocus() throws {
        let focuser = RecordingWindowFocuser()
        let service = WindowFocusService(focuser: focuser)

        let result = service.focus(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted)
        )

        try expectEqual(result, .permissionBlocked)
        try expectEqual(focuser.requestedWindowIdentifier, nil)
    }

    static func testWindowFocusRequestsTargetWindow() throws {
        let focuser = RecordingWindowFocuser()
        let service = WindowFocusService(focuser: focuser)
        let window = WindowEdgeCaseTests.availableWindow()

        let result = service.focus(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .focused)
        try expectEqual(focuser.requestedWindowIdentifier, window.windowIdentifier)
    }

    static func testMinimizedWindowIsForwardedToFocuserForRestore() throws {
        let focuser = RecordingWindowFocuser()
        let service = WindowFocusService(focuser: focuser)
        let minimized = WindowItem(
            windowIdentifier: 11,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Minimized",
            isMinimized: true,
            availability: .minimized
        )

        let result = service.focus(
            minimized,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .focused)
        try expectEqual(focuser.requestedWindowIdentifier, 11)
    }
}

final class RecordingWindowFocuser: WindowFocusing {
    var requestedWindowIdentifier: Int?
    var focusResult = true

    func focus(window: WindowItem) -> Bool {
        requestedWindowIdentifier = window.windowIdentifier
        return focusResult
    }
}
