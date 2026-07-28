import SwitchTab

enum SwitcherOverlayStateTests {
    static func run() throws {
        try testArrowKeysMoveSelection()
        try testArrowKeysDoNotRenderWhenSelectionCannotMove()
        try testLargeNegativeSelectionDeltaWrapsWithinItems()
        try testTypingKeyDoesNotMapToSwitcherCommand()
        try testHorizontalArrowKeyCodesMoveSelection()
        try testConfirmAndCancelProduceExplicitResults()
        try testArrowThenShortcutReleaseConfirmsChangedSelection()
        try testShiftReleaseThenArrowThenCommandReleaseConfirmsSelection()
        try testHoverSelectionMovesHighlightWithoutConfirming()
        try testHoverSelectionIgnoresNoOpAndOutOfRangeIndices()
    }

    static func testArrowKeysMoveSelection() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil),
                SwitcherListItem(id: "notes", title: "Notes", subtitle: nil)
            ]
        )

        _ = state.handle(.moveDown)

        try expectEqual(state.session?.selectedItem?.title, "Safari")
    }

    static func testArrowKeysDoNotRenderWhenSelectionCannotMove() throws {
        var singleItemState = SwitcherOverlayState()
        singleItemState.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "finder", title: "Finder", subtitle: nil)]
        )
        var emptyState = SwitcherOverlayState()
        emptyState.present(mode: .currentAppWindowSwitching, items: [])

        let singleItemResult = singleItemState.handle(.moveDown)
        let emptyResult = emptyState.handle(.moveUp)

        try expectEqual(singleItemResult, .none)
        try expectEqual(emptyResult, .none)
    }

    static func testLargeNegativeSelectionDeltaWrapsWithinItems() throws {
        var session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil),
                SwitcherListItem(id: "notes", title: "Notes", subtitle: nil)
            ]
        )

        let didMove = session.moveSelection(by: -4)

        try expectTrue(didMove)
        try expectEqual(session.selectedIndex, 2)
        try expectEqual(session.selectedItem?.id, "notes")
    }

    static func testTypingKeyDoesNotMapToSwitcherCommand() throws {
        try expectEqual(SwitcherCommand(keyCode: 0), nil)
    }

    static func testHorizontalArrowKeyCodesMoveSelection() throws {
        try expectEqual(
            SwitcherCommand(keyCode: 123),
            .moveUp
        )
        try expectEqual(
            SwitcherCommand(keyCode: 124),
            .moveDown
        )
        try expectEqual(
            SwitcherCommand(keyCode: 126),
            .moveUp
        )
        try expectEqual(
            SwitcherCommand(keyCode: 125),
            .moveDown
        )
    }

    static func testConfirmAndCancelProduceExplicitResults() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "finder", title: "Finder", subtitle: nil)]
        )

        let confirmed = state.handle(.confirm)
        try expectEqual(
            confirmed,
            .confirmed(item: SwitcherListItem(id: "finder", title: "Finder", subtitle: nil), index: 0)
        )
        try expectFalse(state.isPresented)

        state.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "notes", title: "Notes", subtitle: nil)]
        )

        try expectEqual(state.handle(.cancel), .cancelled)
        try expectFalse(state.isPresented)
    }

    static func testArrowThenShortcutReleaseConfirmsChangedSelection() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil),
                SwitcherListItem(id: "notes", title: "Notes", subtitle: nil)
            ],
            selectedIndex: 0
        )

        _ = state.handle(.moveDown)

        try expectEqual(
            state.handle(.releaseShortcut),
            .confirmed(
                item: SwitcherListItem(id: "safari", title: "Safari", subtitle: nil),
                index: 1
            )
        )
    }

    static func testShiftReleaseThenArrowThenCommandReleaseConfirmsSelection() throws {
        let reverse = ShortcutSetting.defaultCurrentAppWindowSwitching
            .reverseVariant(id: "current-app-window-switching-reverse")
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil),
                SwitcherListItem(id: "notes", title: "Notes", subtitle: nil)
            ],
            selectedIndex: 1
        )

        try expectEqual(
            SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: .command),
                triggerReleaseModifiers: SwitcherShortcutModifiers.releaseRelevantModifiers(reverse)
            ),
            .none
        )

        _ = state.handle(.moveDown)

        try expectEqual(
            SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: []),
                triggerReleaseModifiers: SwitcherShortcutModifiers.releaseRelevantModifiers(reverse)
            ),
            .releaseShortcut
        )
        try expectEqual(
            state.handle(.releaseShortcut),
            .confirmed(
                item: SwitcherListItem(id: "notes", title: "Notes", subtitle: nil),
                index: 2
            )
        )
    }

    static func testHoverSelectionMovesHighlightWithoutConfirming() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: hoverItems(), selectedIndex: 1)

        let result = state.selectItem(at: 2)

        try expectEqual(result, .updated)
        try expectEqual(state.session?.selectedIndex, 2)
        try expectTrue(state.isPresented)
    }

    static func testHoverSelectionIgnoresNoOpAndOutOfRangeIndices() throws {
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: hoverItems(), selectedIndex: 1)

        try expectEqual(state.selectItem(at: 1), SwitcherInteractionResult.none)
        try expectEqual(state.selectItem(at: 9), SwitcherInteractionResult.none)
        try expectEqual(state.selectItem(at: -1), SwitcherInteractionResult.none)
        try expectEqual(state.session?.selectedIndex, 1)
    }

    private static func hoverItems() -> [SwitcherListItem] {
        [
            SwitcherListItem(id: "one", title: "One", subtitle: nil),
            SwitcherListItem(id: "two", title: "Two", subtitle: nil),
            SwitcherListItem(id: "three", title: "Three", subtitle: nil)
        ]
    }
}
