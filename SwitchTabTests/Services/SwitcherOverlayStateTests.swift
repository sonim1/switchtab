import AppKit
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
        try testApplicationModeDoesNotShowThumbnails()
        try testClosePolicyOnlyAllowsWindowMode()
        try testSwitchAccessibilityHintMatchesMode()
        try testSwitchAccessibilityLabelIncludesApplicationWindowCount()
        try testApplicationModeIgnoresCloseSelected()
        try testQuitCommandNeedsCommandModifier()
        try testApplicationModeRequestsQuitWithoutDismissing()
        try testWindowModeIgnoresQuitSelectedApplication()
        try testGlobalEventMonitorObservesModifierChanges()
        try testApplicationCommandReleaseConfirmsSelection()
        try testHoverSelectionMovesHighlightWithoutConfirming()
        try testHoverSelectionIgnoresNoOpAndOutOfRangeIndices()
        try testRemovingSelectedMiddleChoosesNextItem()
        try testRemovingSelectedLastChoosesPreviousItem()
        try testRemovingSelectedFirstChoosesNextItem()
        try testDelayedRemovalKeepsCurrentSelectionByStableIdentity()
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

    static func testApplicationModeDoesNotShowThumbnails() throws {
        try expectTrue(
            SwitcherOverlayThumbnailPolicy.showsThumbnails(for: .currentAppWindowSwitching)
        )
        try expectFalse(
            SwitcherOverlayThumbnailPolicy.showsThumbnails(for: .applicationSwitching)
        )
    }

    static func testClosePolicyOnlyAllowsWindowMode() throws {
        try expectTrue(
            SwitcherOverlayClosePolicy.allowsClose(for: .currentAppWindowSwitching)
        )
        try expectFalse(
            SwitcherOverlayClosePolicy.allowsClose(for: .applicationSwitching)
        )
    }

    static func testSwitchAccessibilityHintMatchesMode() throws {
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchHint(for: .currentAppWindowSwitching),
            "Switch to this window."
        )
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchHint(for: .applicationSwitching),
            "Switch to this application."
        )
    }

    static func testSwitchAccessibilityLabelIncludesApplicationWindowCount() throws {
        let oneWindow = SwitcherListItem(
            id: "safari",
            title: "Safari",
            subtitle: "1"
        )
        let noWindows = SwitcherListItem(
            id: "finder",
            title: "Finder",
            subtitle: "0"
        )
        let manyWindows = SwitcherListItem(
            id: "notes",
            title: "Notes",
            subtitle: "2"
        )
        let unavailable = SwitcherListItem(
            id: "mail",
            title: "Mail",
            subtitle: nil
        )

        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchLabel(
                for: oneWindow,
                mode: .applicationSwitching
            ),
            "Safari, 1 window"
        )
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchLabel(
                for: noWindows,
                mode: .applicationSwitching
            ),
            "Finder, 0 windows"
        )
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchLabel(
                for: manyWindows,
                mode: .applicationSwitching
            ),
            "Notes, 2 windows"
        )
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchLabel(
                for: unavailable,
                mode: .applicationSwitching
            ),
            "Mail"
        )
        try expectEqual(
            SwitcherOverlayAccessibilityPolicy.switchLabel(
                for: oneWindow,
                mode: .currentAppWindowSwitching
            ),
            "Safari"
        )
    }

    static func testApplicationModeIgnoresCloseSelected() throws {
        let application = SwitcherListItem(
            id: "com.apple.Safari",
            title: "Safari",
            subtitle: nil
        )
        var state = SwitcherOverlayState()
        state.present(mode: .applicationSwitching, items: [application])

        try expectEqual(state.handle(.closeSelected), .none)
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.selectedItem, application)
    }

    static func testQuitCommandNeedsCommandModifier() throws {
        try expectEqual(
            SwitcherCommand(
                keyCode: SwitcherCommand.quitSelectedApplicationKeyCode,
                modifiers: .command
            ),
            .quitSelectedApplication
        )
        try expectEqual(
            SwitcherCommand(
                keyCode: SwitcherCommand.quitSelectedApplicationKeyCode,
                modifiers: [.command, .shift]
            ),
            .quitSelectedApplication
        )
        try expectEqual(
            SwitcherCommand(keyCode: SwitcherCommand.quitSelectedApplicationKeyCode),
            nil
        )
        try expectEqual(
            SwitcherCommand(
                keyCode: SwitcherCommand.quitSelectedApplicationKeyCode,
                modifiers: .option
            ),
            nil
        )
    }

    static func testApplicationModeRequestsQuitWithoutDismissing() throws {
        let application = SwitcherListItem(
            id: "com.apple.Safari",
            title: "Safari",
            subtitle: "3"
        )
        var state = SwitcherOverlayState()
        state.present(mode: .applicationSwitching, items: [application])

        try expectEqual(
            state.handle(.quitSelectedApplication),
            .quitRequested(item: application, index: 0)
        )
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.selectedItem, application)
    }

    static func testWindowModeIgnoresQuitSelectedApplication() throws {
        let window = SwitcherListItem(id: "window", title: "Window", subtitle: "Safari")
        var state = SwitcherOverlayState()
        state.present(mode: .currentAppWindowSwitching, items: [window])

        try expectEqual(state.handle(.quitSelectedApplication), .none)
        try expectTrue(state.isPresented)
        try expectEqual(state.session?.selectedItem, window)
    }

    static func testGlobalEventMonitorObservesModifierChanges() throws {
        try expectTrue(
            SwitcherOverlayEventMonitorPolicy.globalMask.contains(.flagsChanged)
        )
    }

    static func testApplicationCommandReleaseConfirmsSelection() throws {
        let finder = SwitcherListItem(id: "finder", title: "Finder", subtitle: nil)
        let safari = SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)
        var state = SwitcherOverlayState()
        state.present(
            mode: .applicationSwitching,
            items: [finder, safari],
            selectedIndex: 1
        )
        let releaseModifiers = SwitcherShortcutModifiers.releaseRelevantModifiers(
            .defaultApplicationSwitching
        )

        try expectEqual(
            SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: .command),
                triggerReleaseModifiers: releaseModifiers
            ),
            .none
        )
        try expectEqual(
            SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: []),
                triggerReleaseModifiers: releaseModifiers
            ),
            .releaseShortcut
        )
        try expectEqual(
            state.handle(.releaseShortcut),
            .confirmed(item: safari, index: 1)
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

    static func testRemovingSelectedMiddleChoosesNextItem() throws {
        var session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: removalItems(),
            selectedIndex: 1
        )

        try expectTrue(session.removeItem(withID: "b"))
        try expectEqual(session.selectedItem?.id, "c")
        try expectEqual(session.selectedIndex, 1)
    }

    static func testRemovingSelectedLastChoosesPreviousItem() throws {
        var session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: removalItems(),
            selectedIndex: 2
        )

        try expectTrue(session.removeItem(withID: "c"))
        try expectEqual(session.selectedItem?.id, "b")
        try expectEqual(session.selectedIndex, 1)
    }

    static func testRemovingSelectedFirstChoosesNextItem() throws {
        var session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: removalItems(),
            selectedIndex: 0
        )

        try expectTrue(session.removeItem(withID: "a"))
        try expectEqual(session.selectedItem?.id, "b")
        try expectEqual(session.selectedIndex, 0)
    }

    static func testDelayedRemovalKeepsCurrentSelectionByStableIdentity() throws {
        var session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: removalItems(),
            selectedIndex: 1
        )

        try expectTrue(session.moveSelection(by: 1))
        try expectEqual(session.selectedItem?.id, "c")
        try expectTrue(session.removeItem(withID: "b"))
        try expectEqual(session.selectedItem?.id, "c")
        try expectEqual(session.selectedIndex, 1)
    }

    private static func hoverItems() -> [SwitcherListItem] {
        [
            SwitcherListItem(id: "one", title: "One", subtitle: nil),
            SwitcherListItem(id: "two", title: "Two", subtitle: nil),
            SwitcherListItem(id: "three", title: "Three", subtitle: nil)
        ]
    }

    private static func removalItems() -> [SwitcherListItem] {
        [
            SwitcherListItem(id: "a", title: "A", subtitle: nil),
            SwitcherListItem(id: "b", title: "B", subtitle: nil),
            SwitcherListItem(id: "c", title: "C", subtitle: nil)
        ]
    }
}
