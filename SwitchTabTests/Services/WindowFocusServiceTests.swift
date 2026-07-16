import SwitchTab

enum WindowFocusServiceTests {
    static func run() throws {
        try testUnavailableWindowIsNotFocused()
        try testMissingAccessibilityBlocksWindowFocus()
        try testWindowFocusRequestsTargetWindow()
        try testMinimizedWindowIsForwardedToFocuserForRestore()
        try testFailedFocusDoesNotRecordRecency()
        try testSuccessfulFocusRecordsAndFlushesRecency()
        try testApplicationActivationAloneIsNotWindowFocusSuccess()
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

    static func testFailedFocusDoesNotRecordRecency() throws {
        let recencyStore = RecordingWindowSelectionRecencyStore()
        let coordinator = WindowSelectionCoordinator(
            focusService: StubWindowFocusService(result: .unavailableTarget),
            recencyStore: recencyStore
        )

        let result = coordinator.confirm(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .unavailableTarget)
        try expectEqual(recencyStore.recordedIDs, [])
        try expectEqual(recencyStore.flushCount, 0)
    }

    static func testSuccessfulFocusRecordsAndFlushesRecency() throws {
        let recencyStore = RecordingWindowSelectionRecencyStore()
        let window = WindowEdgeCaseTests.availableWindow()
        let coordinator = WindowSelectionCoordinator(
            focusService: StubWindowFocusService(result: .focused),
            recencyStore: recencyStore
        )

        let result = coordinator.confirm(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        try expectEqual(result, .focused)
        try expectEqual(recencyStore.recordedIDs, [window.id])
        try expectEqual(recencyStore.flushCount, 1)
    }

    static func testApplicationActivationAloneIsNotWindowFocusSuccess() throws {
        let didFocus = AXWindowFocusResultPolicy.didFocus(
            didActivateApplication: true,
            didSetFocusedWindow: false,
            didSetMainWindow: false,
            didRaiseWindow: false
        )

        try expectFalse(didFocus)
    }
}

private struct StubWindowFocusService: WindowFocusServicing {
    let result: WindowFocusResult

    func focus(_: WindowItem, permissionState _: PermissionState) -> WindowFocusResult {
        result
    }
}

private final class RecordingWindowSelectionRecencyStore: WindowSelectionRecencyRecording {
    private(set) var recordedIDs: [String] = []
    private(set) var flushCount = 0

    func recordSelection(id: String) {
        recordedIDs.append(id)
    }

    func flush() {
        flushCount += 1
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
