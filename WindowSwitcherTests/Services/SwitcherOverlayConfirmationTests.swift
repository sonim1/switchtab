import WindowSwitcher

enum SwitcherOverlayConfirmationTests {
    static func run() throws {
        try testShortcutReleaseConfirmsSelection()
        try testEnterConfirmsSelection()
        try testShortcutReleaseCancelsWhenNoItemIsSelected()
        try testExternalMouseDismissesOverlay()
        try testExternalModifierReleaseConfirmsReleaseShortcutOverlay()
        try testExternalShiftReleaseDoesNotConfirmReverseShortcut()
        try testEmptyShortcutModifiersRemainEmpty()
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
}
