import AppKit
@testable import SwitchTab

@MainActor
enum SwitcherOverlayConfirmationTests {
    static func run() throws {
        try testShortcutReleaseConfirmsSelection()
        try testEnterConfirmsSelection()
        try testShortcutReleaseCancelsWhenNoItemIsSelected()
        try testExternalMouseDismissesOverlay()
        try testExternalModifierReleaseConfirmsReleaseShortcutOverlay()
        try testExternalShiftReleaseDoesNotConfirmReverseShortcut()
        try testEmptyShortcutModifiersRemainEmpty()
        try testControllerDeliversQuitWithoutDismissingApplicationOverlay()
        try testConfirmedApplicationTerminationRemovesByIdentityAndPreservesSelection()
        try testTerminationIgnoresWindowModeAndNonmatchingApplication()
        try testStaleTerminationForPreviousProcessDoesNotRemoveRelaunchedApplication()
        try testTerminatingLastPresentedApplicationDismissesOverlay()
    }

    static func testShortcutReleaseConfirmsSelection() throws {
        var state = makeState()
        let safari = SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)

        let result = state.handle(.releaseShortcut)

        try expectEqual(result, .confirmed(item: safari, index: 1))
        try expectFalse(state.isPresented)
    }

    static func testEnterConfirmsSelection() throws {
        var state = makeState()
        let safari = SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)

        let result = state.handle(.confirm)

        try expectEqual(result, .confirmed(item: safari, index: 1))
        try expectFalse(state.isPresented)
    }

    static func testShortcutReleaseCancelsWhenNoItemIsSelected() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: []
        )

        let result = state.handle(.releaseShortcut)

        try expectEqual(result, .cancelled)
        try expectFalse(state.isPresented)
    }

    static func testExternalMouseDismissesOverlay() throws {
        let decision = SwitcherOverlayExternalEventPolicy.decision(
            for: .mouseDown,
            triggerReleaseModifiers: SwitcherShortcutModifiers.releaseRelevantModifiers(.defaultCurrentAppWindowSwitching)
        )

        try expectEqual(decision, .cancel)
    }

    static func testExternalModifierReleaseConfirmsReleaseShortcutOverlay() throws {
        let decision = SwitcherOverlayExternalEventPolicy.decision(
            for: .flagsChanged(activeModifiers: []),
            triggerReleaseModifiers: SwitcherShortcutModifiers.releaseRelevantModifiers(.defaultCurrentAppWindowSwitching)
        )

        try expectEqual(decision, .releaseShortcut)
    }

    static func testExternalShiftReleaseDoesNotConfirmReverseShortcut() throws {
        let reverse = ShortcutSetting.defaultCurrentAppWindowSwitching.reverseVariant(id: "reverse")
        let decision = SwitcherOverlayExternalEventPolicy.decision(
            for: .flagsChanged(activeModifiers: .command),
            triggerReleaseModifiers: SwitcherShortcutModifiers.releaseRelevantModifiers(reverse)
        )

        try expectEqual(decision, .none)
    }

    static func testEmptyShortcutModifiersRemainEmpty() throws {
        try expectTrue(SwitcherShortcutModifiers(modifiers: []).isEmpty)
    }

    static func testControllerDeliversQuitWithoutDismissingApplicationOverlay() throws {
        let controller = makeController()
        let applications = applicationItems()
        var quitRequests: [(String, Int)] = []
        controller.present(
            mode: .applicationSwitching,
            items: applications,
            selectedIndex: 1,
            onQuit: { item, index in
                quitRequests.append((item.id, index))
            }
        )

        let result = controller.handle(.quitSelectedApplication)

        try expectEqual(result, .quitRequested(item: applications[1], index: 1))
        try expectEqual(quitRequests.map(\.0), ["com.example.two"])
        try expectEqual(quitRequests.map(\.1), [1])
        try expectTrue(controller.isPresented)
        controller.dismiss()
    }

    static func testConfirmedApplicationTerminationRemovesByIdentityAndPreservesSelection() throws {
        let controller = makeController()
        var confirmedIDs: [String] = []
        controller.present(
            mode: .applicationSwitching,
            items: applicationItems(),
            selectedIndex: 1,
            onConfirm: { item, _ in confirmedIDs.append(item.id) }
        )

        controller.confirmApplicationTerminated(id: "com.example.two", processIdentifier: 2)

        try expectTrue(controller.isPresented)
        _ = controller.handle(.confirm)
        try expectEqual(confirmedIDs, ["com.example.three"])
    }

    static func testTerminationIgnoresWindowModeAndNonmatchingApplication() throws {
        let controller = makeController()
        var confirmedIDs: [String] = []
        controller.present(
            mode: .applicationSwitching,
            items: applicationItems(),
            selectedIndex: 1,
            onConfirm: { item, _ in confirmedIDs.append(item.id) }
        )

        controller.confirmApplicationTerminated(id: "com.example.missing", processIdentifier: 2)
        _ = controller.handle(.confirm)
        try expectEqual(confirmedIDs, ["com.example.two"])

        confirmedIDs.removeAll()
        controller.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "window", title: "Window", subtitle: "App")],
            onConfirm: { item, _ in confirmedIDs.append(item.id) }
        )
        controller.confirmApplicationTerminated(id: "window", processIdentifier: 2)
        _ = controller.handle(.confirm)
        try expectEqual(confirmedIDs, ["window"])
    }

    static func testStaleTerminationForPreviousProcessDoesNotRemoveRelaunchedApplication() throws {
        let controller = makeController()
        var confirmedIDs: [String] = []
        controller.present(
            mode: .applicationSwitching,
            items: applicationItems(),
            selectedIndex: 1,
            onConfirm: { item, _ in confirmedIDs.append(item.id) }
        )

        controller.confirmApplicationTerminated(
            id: "com.example.two",
            processIdentifier: 200
        )

        _ = controller.handle(.confirm)
        try expectEqual(confirmedIDs, ["com.example.two"])
    }

    static func testTerminatingLastPresentedApplicationDismissesOverlay() throws {
        let controller = makeController()
        controller.present(
            mode: .applicationSwitching,
            items: [applicationItems()[0]]
        )

        controller.confirmApplicationTerminated(id: "com.example.one", processIdentifier: 1)

        try expectFalse(controller.isPresented)
    }

    private static func makeState() -> SwitcherOverlayState {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)
            ],
            selectedIndex: 1
        )
        return state
    }

    private static func makeController() -> SwitcherOverlayController {
        SwitcherOverlayController(
            thumbnailStore: WindowThumbnailStore(),
            eventTapBackend: NonInstallingConfirmationEventTapBackend()
        )
    }

    private static func applicationItems() -> [SwitcherListItem] {
        [
            SwitcherListItem(
                id: "com.example.one",
                title: "One",
                subtitle: "1",
                appIconProcessIdentifier: 1
            ),
            SwitcherListItem(
                id: "com.example.two",
                title: "Two",
                subtitle: "2",
                appIconProcessIdentifier: 2
            ),
            SwitcherListItem(
                id: "com.example.three",
                title: "Three",
                subtitle: nil,
                appIconProcessIdentifier: 3
            )
        ]
    }
}

@MainActor
private final class NonInstallingConfirmationEventTapBackend: SwitcherOverlayEventTapBackend {
    func install(
        handler _: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)? {
        nil
    }
}
