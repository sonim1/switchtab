import SwitchTab

enum WindowEdgeCaseTests {
    static func run() throws {
        try testClosedWindowsAreRemovedButUnavailableWindowsStayVisible()
        try testHiddenAndOtherSpaceWindowsCannotFocus()
        try testMinimizedWindowCanFocusForRestore()
    }

    static func availableWindow() -> WindowItem {
        WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            isMinimized: false,
            availability: .available
        )
    }

    static func testClosedWindowsAreRemovedButUnavailableWindowsStayVisible() throws {
        let provider = AccessibilityWindowProvider(
            activeApplicationProvider: FakeActiveApplicationProvider(
                activeApplication: ActiveApplicationSnapshot(
                    processIdentifier: 42
                )
            ),
            windowSnapshotProvider: FakeWindowSnapshotProvider(
                snapshots: [
                    AccessibilityWindowSnapshot(
                        windowIdentifier: 1,
                        ownerProcessIdentifier: 42,
                        ownerName: "Notes",
                        title: "Closed",
                        isMinimized: false,
                        availability: .closed
                    ),
                    AccessibilityWindowSnapshot(
                        windowIdentifier: 2,
                        ownerProcessIdentifier: 42,
                        ownerName: "Notes",
                        title: "Other Space",
                        isMinimized: false,
                        availability: .otherSpace
                    )
                ]
            )
        )

        try expectEqual(provider.currentApplicationWindows().map(\.switcherListItem.title), ["Other Space"])
    }

    static func testHiddenAndOtherSpaceWindowsCannotFocus() throws {
        let blockedAvailability: [WindowAvailability] = [.hiddenApplication, .otherSpace]

        for availability in blockedAvailability {
            let window = WindowItem(
                windowIdentifier: 10,
                ownerProcessIdentifier: 42,
                ownerName: "Notes",
                title: "Blocked",
                isMinimized: false,
                availability: availability
            )

            try expectFalse(window.canFocus)
        }
    }

    static func testMinimizedWindowCanFocusForRestore() throws {
        let window = WindowItem(
            windowIdentifier: 10,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Minimized",
            isMinimized: true,
            availability: .minimized
        )

        try expectTrue(window.canFocus)
    }
}
