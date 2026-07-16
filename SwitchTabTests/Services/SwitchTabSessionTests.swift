import SwitchTab

enum SwitchTabSessionTests {
    static func run() throws {
        try testWindowModeStoresPresentedWindows()
        try testEnterConfirmsSelectedWindow()
        try testShortcutReleaseConfirmsSelectedWindow()
    }

    static func testWindowModeStoresPresentedWindows() throws {
        let items = [
            WindowEdgeCaseTests.availableWindow().switcherListItem,
            WindowItem(
                windowIdentifier: 8,
                ownerProcessIdentifier: 42,
                ownerName: "Notes",
                title: "Ideas",
                isMinimized: false,
                availability: .available
            ).switcherListItem
        ]
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: items
        )

        try expectEqual(state.session?.items.map(\.title), ["Project", "Ideas"])
    }

    static func testEnterConfirmsSelectedWindow() throws {
        let first = SwitcherListItem(id: "window-1", title: "First", subtitle: "Notes")
        let second = SwitcherListItem(id: "window-2", title: "Second", subtitle: "Notes")

        var enterState = SwitcherOverlayState()
        enterState.present(
            mode: .currentAppWindowSwitching,
            items: [first, second],
            selectedIndex: 1
        )

        try expectEqual(enterState.handle(.confirm), .confirmed(item: second, index: 1))
    }

    static func testShortcutReleaseConfirmsSelectedWindow() throws {
        let first = SwitcherListItem(id: "window-1", title: "First", subtitle: "Notes")
        let second = SwitcherListItem(id: "window-2", title: "Second", subtitle: "Notes")
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [first, second],
            selectedIndex: 1
        )

        let result = state.handle(.releaseShortcut)

        try expectEqual(result, .confirmed(item: second, index: 1))
        try expectFalse(state.isPresented)
    }
}
