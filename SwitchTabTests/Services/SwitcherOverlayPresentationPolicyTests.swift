import AppKit
@testable import SwitchTab

@MainActor
enum SwitcherOverlayPresentationPolicyTests {
    static func run() throws {
        try testSwitcherOverlayDoesNotActivateApplication()
        try testSwitcherOverlayCanBecomeKeyWithoutBecomingMain()
        try testSwitcherOverlayCentersPanelInScreen()
        try testLocalEventMonitorSkipsKeyUpEvents()
        try testEventTapConsumesNavigationKeysAndPassesThroughOtherKeys()
        try testEventTapProducesOneDecisionForEachKeyDownIncludingAutorepeat()
        try testDisabledEventTapRequestsReenableWithoutDispatchingACommand()
        try testEventTapOwnerLifecycleAndExactOnceDispatch()
        try testEventTapOwnerInstallFailureAndReplacementAreSafe()
        try testControllerWiresDiagnosticsReplacementAndInstallFailure()
        try testOverlayControllerBuildsApplicationIconStoreInsideMainActorInitializer()
        try testActiveScreenFramePrefersScreenContainingPointer()
        try testActiveScreenFrameFallsBackWhenPointerOutsideAllScreens()
    }

    static func testSwitcherOverlayDoesNotActivateApplication() throws {
        try expectTrue(SwitcherOverlayPresentationPolicy.styleMask.contains(.nonactivatingPanel))
    }

    static func testSwitcherOverlayCanBecomeKeyWithoutBecomingMain() throws {
        try expectTrue(SwitcherOverlayPresentationPolicy.canBecomeKey)
        try expectFalse(SwitcherOverlayPresentationPolicy.canBecomeMain)
    }

    static func testSwitcherOverlayCentersPanelInScreen() throws {
        let origin = SwitcherOverlayPresentationPolicy.panelOrigin(
            panelSize: CGSize(width: 400, height: 200),
            screenFrame: CGRect(x: 100, y: 50, width: 1200, height: 800)
        )

        try expectEqual(origin.x, 500)
        try expectEqual(origin.y, 350)
    }

    static func testLocalEventMonitorSkipsKeyUpEvents() throws {
        try expectTrue(SwitcherOverlayEventMonitorPolicy.localMask.contains(.keyDown))
        try expectTrue(SwitcherOverlayEventMonitorPolicy.localMask.contains(.flagsChanged))
        try expectFalse(SwitcherOverlayEventMonitorPolicy.localMask.contains(.keyUp))
    }

    static func testEventTapConsumesNavigationKeysAndPassesThroughOtherKeys() throws {
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 123,
                isAutorepeat: false
            ),
            .consume(.moveUp)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 124,
                isAutorepeat: false
            ),
            .consume(.moveDown)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 125,
                isAutorepeat: false
            ),
            .consume(.moveDown)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 126,
                isAutorepeat: false
            ),
            .consume(.moveUp)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 36,
                isAutorepeat: false
            ),
            .consume(.confirm)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 53,
                isAutorepeat: false
            ),
            .consume(.cancel)
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 50,
                isAutorepeat: false
            ),
            .passThrough
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 0,
                isAutorepeat: false
            ),
            .passThrough
        )
    }

    static func testEventTapProducesOneDecisionForEachKeyDownIncludingAutorepeat() throws {
        let decisions = [false, true, true].map { isAutorepeat in
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .keyDown,
                keyCode: 125,
                isAutorepeat: isAutorepeat
            )
        }

        try expectEqual(
            decisions,
            [.consume(.moveDown), .consume(.moveDown), .consume(.moveDown)]
        )
    }

    static func testDisabledEventTapRequestsReenableWithoutDispatchingACommand() throws {
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .tapDisabledByTimeout,
                keyCode: 125,
                isAutorepeat: false
            ),
            .reenable
        )
        try expectEqual(
            SwitcherOverlayEventTapPolicy.decision(
                eventType: .tapDisabledByUserInput,
                keyCode: 36,
                isAutorepeat: false
            ),
            .reenable
        )
    }

    static func testEventTapOwnerLifecycleAndExactOnceDispatch() throws {
        let backend = RecordingSwitcherOverlayEventTapBackend()
        let sink = RecordingSwitcherOverlayEventSink()
        var commands: [SwitcherCommand] = []
        var owner: SwitcherOverlayEventTapOwner?
        owner = SwitcherOverlayEventTapOwner(backend: backend, eventSink: sink) { command in
            commands.append(command)
            if command == .confirm {
                owner?.remove()
            }
        }

        try expectTrue(owner?.install() == true)
        guard let connection = backend.connections.first else {
            throw TestFailure.failed("Expected installed event-tap connection")
        }
        try expectTrue(connection.emit(keyCode: 125, isAutorepeat: false))
        try expectTrue(connection.emit(keyCode: 125, isAutorepeat: true))
        try expectEqual(commands, [.moveDown, .moveDown])

        try expectFalse(connection.emit(eventType: .tapDisabledByTimeout, keyCode: 0))
        try expectEqual(connection.reenableCount, 1)
        try expectEqual(commands, [.moveDown, .moveDown])
        try expectTrue(sink.events.contains(.tapReenabled(reasonCode: 1)))

        try expectTrue(connection.emit(keyCode: 36))
        try expectEqual(commands, [.moveDown, .moveDown, .confirm])
        try expectEqual(connection.invalidateCount, 1)
        try expectFalse(connection.emit(keyCode: 125))
        owner?.remove()
        try expectEqual(connection.invalidateCount, 1)
        try expectEqual(sink.events.filter { $0 == .tapRemoved }.count, 1)

        let cancelBackend = RecordingSwitcherOverlayEventTapBackend()
        var cancelCommands: [SwitcherCommand] = []
        var cancelOwner: SwitcherOverlayEventTapOwner?
        cancelOwner = SwitcherOverlayEventTapOwner(backend: cancelBackend, eventSink: sink) { command in
            cancelCommands.append(command)
            cancelOwner?.remove()
        }
        try expectTrue(cancelOwner?.install() == true)
        guard let cancelConnection = cancelBackend.connections.first else {
            throw TestFailure.failed("Expected cancel event-tap connection")
        }
        try expectTrue(cancelConnection.emit(keyCode: 53))
        try expectEqual(cancelCommands, [.cancel])
        try expectEqual(cancelConnection.invalidateCount, 1)
    }

    static func testEventTapOwnerInstallFailureAndReplacementAreSafe() throws {
        let failingBackend = RecordingSwitcherOverlayEventTapBackend(shouldInstall: false)
        let sink = RecordingSwitcherOverlayEventSink()
        let failingOwner = SwitcherOverlayEventTapOwner(
            backend: failingBackend,
            eventSink: sink,
            commandHandler: { _ in }
        )
        try expectFalse(failingOwner.install())
        failingOwner.remove()
        try expectEqual(sink.events, [])

        let backend = RecordingSwitcherOverlayEventTapBackend()
        let owner = SwitcherOverlayEventTapOwner(
            backend: backend,
            eventSink: sink,
            commandHandler: { _ in }
        )
        try expectTrue(owner.install())
        guard let first = backend.connections.first else {
            throw TestFailure.failed("Expected first event-tap connection")
        }
        try expectTrue(owner.install())
        try expectEqual(first.invalidateCount, 1)
        try expectEqual(backend.connections.count, 2)
        try expectFalse(first.emit(keyCode: 125))
        owner.remove()
        owner.remove()
        try expectEqual(backend.connections[1].invalidateCount, 1)
    }

    static func testControllerWiresDiagnosticsReplacementAndInstallFailure() throws {
        let item = SwitcherListItem(id: "qa", title: "QA", subtitle: nil)
        let backend = RecordingSwitcherOverlayEventTapBackend()
        let sink = RecordingSwitcherOverlayEventSink()
        let controller = SwitcherOverlayController(
            thumbnailStore: WindowThumbnailStore(),
            eventTapBackend: backend,
            eventSink: sink
        )

        controller.present(mode: .currentAppWindowSwitching, items: [item])
        guard let first = backend.connections.first else {
            throw TestFailure.failed("Expected controller event-tap connection")
        }
        try expectEqual(
            sink.events.first,
            .presented(itemCount: 1, selectedIndex: 0, tapInstalled: true)
        )

        controller.present(mode: .currentAppWindowSwitching, items: [item])
        try expectEqual(first.invalidateCount, 1)
        guard let second = backend.connections.last else {
            throw TestFailure.failed("Expected replacement event-tap connection")
        }
        try expectTrue(second.emit(keyCode: 36))
        try expectEqual(
            Array(sink.events.suffix(2)),
            [
                .command(commandCode: 3, beforeIndex: 0, afterIndex: 0, resultCode: 2),
                .tapRemoved
            ]
        )

        let failingBackend = RecordingSwitcherOverlayEventTapBackend(shouldInstall: false)
        let failingSink = RecordingSwitcherOverlayEventSink()
        let fallbackController = SwitcherOverlayController(
            thumbnailStore: WindowThumbnailStore(),
            eventTapBackend: failingBackend,
            eventSink: failingSink
        )
        fallbackController.present(mode: .currentAppWindowSwitching, items: [item])
        try expectEqual(
            failingSink.events,
            [.presented(itemCount: 1, selectedIndex: 0, tapInstalled: false)]
        )
        fallbackController.dismiss()
    }

    static func testOverlayControllerBuildsApplicationIconStoreInsideMainActorInitializer() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("SwitchTab/UI/Overlay/SwitcherOverlayController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains("applicationIconStore: ApplicationIconStore? = nil"))
        try expectTrue(source.contains("self.applicationIconStore = applicationIconStore ?? ApplicationIconStore()"))
        try expectFalse(source.contains("applicationIconStore: ApplicationIconStore = ApplicationIconStore()"))
    }

    static func testActiveScreenFramePrefersScreenContainingPointer() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)

        let frame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: CGPoint(x: 2000, y: 400),
            screenFrames: [primary, secondary],
            fallback: primary
        )

        try expectEqual(frame, secondary)
    }

    static func testActiveScreenFrameFallsBackWhenPointerOutsideAllScreens() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let frame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: CGPoint(x: -50, y: -50),
            screenFrames: [primary],
            fallback: primary
        )

        try expectEqual(frame, primary)
    }
}

@MainActor
private final class RecordingSwitcherOverlayEventTapBackend: SwitcherOverlayEventTapBackend {
    let shouldInstall: Bool
    private(set) var connections: [RecordingSwitcherOverlayEventTapConnection] = []

    init(shouldInstall: Bool = true) {
        self.shouldInstall = shouldInstall
    }

    func install(
        handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)? {
        guard shouldInstall else {
            return nil
        }
        let connection = RecordingSwitcherOverlayEventTapConnection(handler: handler)
        connections.append(connection)
        return connection
    }
}

@MainActor
private final class RecordingSwitcherOverlayEventTapConnection: SwitcherOverlayEventTapConnection {
    private let handler: @MainActor (SwitcherOverlayEventTapInput) -> Bool
    private(set) var reenableCount = 0
    private(set) var invalidateCount = 0

    init(handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool) {
        self.handler = handler
    }

    func emit(
        eventType: CGEventType = .keyDown,
        keyCode: UInt16,
        isAutorepeat: Bool = false
    ) -> Bool {
        handler(SwitcherOverlayEventTapInput(
            eventType: eventType,
            keyCode: keyCode,
            isAutorepeat: isAutorepeat
        ))
    }

    func reenable() {
        reenableCount += 1
    }

    func invalidate() {
        invalidateCount += 1
    }
}

@MainActor
private final class RecordingSwitcherOverlayEventSink: SwitcherOverlayEventRecording {
    private(set) var events: [SwitcherOverlayDiagnosticEvent] = []

    func record(_ event: SwitcherOverlayDiagnosticEvent) {
        events.append(event)
    }
}
