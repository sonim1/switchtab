import AppKit
import SwiftUI
@testable import SwitchTab

@MainActor
enum WindowCloseServiceTests {
    static func run() throws {
        try testMissingAccessibilityBlocksWindowClose()
        try testAcceptedCloseRequestWaitsForDestruction()
        try testDelayedDestructionCompletesOnce()
        try testObserverFailureDoesNotPressClose()
        try testFailedPressCancelsObservation()
        try testPermissionFailureCancelsExistingObservation()
        try testRetryRefreshesObservationAndIgnoresTheCancelledCallback()
        try testCancelAllCancelsEveryObservationAndIgnoresLateCallbacks()
        try testCloseCommandNeedsCommandModifier()
        try testHeldCloseKeyDoesNotRepeatTheClose()
        try testCloseSelectedReportsCloseRequest()
        try testRemovingClosedItemKeepsOverlayOnNextWindow()
        try testRemovingLastItemDismissesOverlay()
        try testRemovingEarlierItemKeepsSelectionOnSameWindow()
        try testRemovingMissingItemIsIgnored()
        try testSnapshotResolvesElementsByIdentity()
        try testCloseButtonPressDoesNotConfirmTile()
        try testMinimumScaleCloseTargetIsAtLeastTwentyFourPoints()
    }

    static func testMissingAccessibilityBlocksWindowClose() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)

        let result = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted),
            onDestroyed: {}
        )

        try expectEqual(result, .permissionBlocked)
        try expectEqual(driver.events, [])
    }

    static func testAcceptedCloseRequestWaitsForDestruction() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)
        let window = WindowEdgeCaseTests.availableWindow()
        var destructionCount = 0

        let result = service.close(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {
                destructionCount += 1
            }
        )

        try expectEqual(result, .requestAccepted)
        try expectEqual(driver.events, [
            .observe(window.windowIdentifier),
            .press(window.windowIdentifier)
        ])
        try expectEqual(destructionCount, 0)
        try expectEqual(driver.observations.first?.cancelCount, 0)
    }

    static func testDelayedDestructionCompletesOnce() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)
        var destructionCount = 0

        _ = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {
                destructionCount += 1
            }
        )

        driver.observations[0].emitDestruction()
        driver.observations[0].emitDestruction()

        try expectEqual(destructionCount, 1)
        try expectEqual(driver.observations[0].cancelCount, 1)
    }

    static func testObserverFailureDoesNotPressClose() throws {
        let driver = RecordingWindowCloseDriver(canObserve: false)
        let service = WindowCloseService(driver: driver)

        let result = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {}
        )

        try expectEqual(result, .unavailableTarget)
        try expectEqual(driver.events.count, 1)
        try expectEqual(driver.pressCount, 0)
    }

    static func testFailedPressCancelsObservation() throws {
        let driver = RecordingWindowCloseDriver(pressSucceeds: false)
        let service = WindowCloseService(driver: driver)

        let result = service.close(
            WindowEdgeCaseTests.availableWindow(),
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {}
        )

        try expectEqual(result, .unavailableTarget)
        try expectEqual(driver.observations[0].cancelCount, 1)
    }

    static func testPermissionFailureCancelsExistingObservation() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)
        let window = WindowEdgeCaseTests.availableWindow()

        _ = service.close(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {}
        )
        let result = service.close(
            window,
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted),
            onDestroyed: {}
        )

        try expectEqual(result, .permissionBlocked)
        try expectEqual(driver.observations[0].cancelCount, 1)
        try expectEqual(driver.pressCount, 1)
    }

    static func testRetryRefreshesObservationAndIgnoresTheCancelledCallback() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)
        let window = WindowEdgeCaseTests.availableWindow()
        var firstCallbackCount = 0
        var secondCallbackCount = 0

        _ = service.close(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {
                firstCallbackCount += 1
            }
        )
        _ = service.close(
            window,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            onDestroyed: {
                secondCallbackCount += 1
            }
        )

        driver.observations[0].emitDestructionEvenIfCancelled()
        driver.observations[1].emitDestruction()

        try expectEqual(driver.pressCount, 2)
        try expectEqual(driver.observations[0].cancelCount, 1)
        try expectEqual(firstCallbackCount, 0)
        try expectEqual(secondCallbackCount, 1)
    }

    static func testCancelAllCancelsEveryObservationAndIgnoresLateCallbacks() throws {
        let driver = RecordingWindowCloseDriver()
        let service = WindowCloseService(driver: driver)
        var destructionCount = 0

        for window in closeWindows(count: 2) {
            _ = service.close(
                window,
                permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
                onDestroyed: {
                    destructionCount += 1
                }
            )
        }

        service.cancelAll()
        driver.observations.forEach { $0.emitDestructionEvenIfCancelled() }

        try expectEqual(driver.observations.map(\.cancelCount), [1, 1])
        try expectEqual(destructionCount, 0)
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

        let result = state.removeItem(withID: "window-1")

        try expectEqual(result, .updated)
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.items.map(\.id), ["window-0", "window-2"])
        try expectEqual(state.session?.selectedIndex, 1)
        try expectEqual(state.session?.selectedItem?.id, "window-2")
    }

    static func testRemovingLastItemDismissesOverlay() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 1))

        let result = state.removeItem(withID: "window-0")

        try expectEqual(result, .cancelled)
        try expectFalse(state.isPresented)
        try expectEqual(state.session, nil)
    }

    static func testRemovingEarlierItemKeepsSelectionOnSameWindow() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 3), selectedIndex: 2)

        let result = state.removeItem(withID: "window-0")

        try expectEqual(result, .updated)
        try expectEqual(state.session?.selectedIndex, 1)
        try expectEqual(state.session?.selectedItem?.id, "window-2")
    }

    static func testRemovingMissingItemIsIgnored() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: items(count: 2))

        try expectEqual(state.removeItem(withID: "missing"), SwitcherInteractionResult.none)
        try expectEqual(state.session?.items.count, 2)
    }

    static func testSnapshotResolvesElementsByIdentity() throws {
        let windows = items(count: 3)
        let snapshot = SwitcherPresentationSnapshot(elements: windows, reverse: false) { $0 }

        // Closing shifts live indices, so identity lookup must stay stable.
        try expectEqual(snapshot.element(withID: "window-2")?.id, "window-2")
        try expectEqual(snapshot.element(withID: "missing")?.id, nil)
    }

    static func testCloseButtonPressDoesNotConfirmTile() throws {
        let item = items(count: 1)[0]
        var confirmedIDs: [String] = []
        var closedIDs: [String] = []
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: .default)
        let rootView = SwitcherIconStripView(
            items: [item],
            selectedIndex: 0,
            gridColumns: SwitcherIconStripView.gridColumns(columnCount: 1, metrics: metrics),
            layoutMetrics: metrics,
            showsThumbnails: false,
            hoverEnabled: true,
            scrollToken: 0,
            thumbnailStore: WindowThumbnailStore(),
            applicationIconStore: ApplicationIconStore(),
            onConfirm: { item, _ in confirmedIDs.append(item.id) },
            onClose: { item, _ in closedIDs.append(item.id) },
            onHover: { _ in }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let frame = NSRect(
            origin: .zero,
            size: CGSize(width: metrics.tileSize.width, height: metrics.tileSize.height)
        )
        hostingController.view.frame = frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        hostingController.view.layoutSubtreeIfNeeded()
        hostingController.view.displayIfNeeded()
        let hitTarget = metrics.closeButtonHitTargetSize
        let localPoint = NSPoint(
            x: metrics.tileSize.width - (hitTarget.width / 2),
            y: hostingController.view.isFlipped
                ? hitTarget.height / 2
                : metrics.tileSize.height - (hitTarget.height / 2)
        )
        let windowPoint = hostingController.view.convert(localPoint, to: nil)
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )
        guard let mouseDown, let mouseUp else {
            throw TestFailure.failed("Expected synthetic close-button mouse events")
        }
        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)

        try expectEqual(confirmedIDs, [])
        try expectEqual(closedIDs, ["window-0"])
    }

    static func testMinimumScaleCloseTargetIsAtLeastTwentyFourPoints() throws {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(
            for: OverlaySizeScale(OverlaySizeScale.minimum)
        )

        try expectTrue(metrics.closeButtonHitTargetSize.width >= 24)
        try expectTrue(metrics.closeButtonHitTargetSize.height >= 24)
        try expectTrue(metrics.closeButtonSize < metrics.closeButtonHitTargetSize.width)
    }

    private static func items(count: Int) -> [SwitcherListItem] {
        (0..<count).map { index in
            SwitcherListItem(id: "window-\(index)", title: "Window \(index)", subtitle: "App")
        }
    }

    private static func closeWindows(count: Int) -> [WindowItem] {
        (0..<count).map { index in
            WindowItem(
                windowIdentifier: 200 + index,
                ownerProcessIdentifier: 100 + index,
                ownerName: "App \(index)",
                title: "Window \(index)",
                isMinimized: false,
                availability: .available,
                isFocused: index == 0
            )
        }
    }

}

@MainActor
private final class RecordingWindowCloseDriver: WindowCloseDriving {
    enum Event: Equatable {
        case observe(Int)
        case press(Int)
    }

    private let canObserve: Bool
    private let pressSucceeds: Bool
    private(set) var events: [Event] = []
    private(set) var observations: [RecordingWindowCloseObservation] = []
    private(set) var pressCount = 0

    init(canObserve: Bool = true, pressSucceeds: Bool = true) {
        self.canObserve = canObserve
        self.pressSucceeds = pressSucceeds
    }

    func observeDestruction(
        of window: WindowItem,
        onDestroyed: @escaping @MainActor () -> Void
    ) -> (any WindowCloseObservation)? {
        events.append(.observe(window.windowIdentifier))
        guard canObserve else {
            return nil
        }

        let observation = RecordingWindowCloseObservation(onDestroyed: onDestroyed)
        observations.append(observation)
        return observation
    }

    func pressCloseButton(of window: WindowItem) -> Bool {
        events.append(.press(window.windowIdentifier))
        pressCount += 1
        return pressSucceeds
    }
}

@MainActor
private final class RecordingWindowCloseObservation: WindowCloseObservation {
    private let onDestroyed: @MainActor () -> Void
    private(set) var cancelCount = 0

    init(onDestroyed: @escaping @MainActor () -> Void) {
        self.onDestroyed = onDestroyed
    }

    func cancel() {
        cancelCount += 1
    }

    func emitDestruction() {
        guard cancelCount == 0 else {
            return
        }

        onDestroyed()
    }

    func emitDestructionEvenIfCancelled() {
        onDestroyed()
    }
}
