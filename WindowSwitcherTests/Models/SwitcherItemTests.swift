import WindowSwitcher

enum SwitcherItemTests {
    static func run() throws {
        try testWindowItemAllowsMissingTitleAndBlocksUnavailableFocus()
        try testReadableTextTrimsAsciiAndUnicodeBoundaryWhitespace()
    }

    static func testWindowItemAllowsMissingTitleAndBlocksUnavailableFocus() throws {
        let untitled = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "",
            isMinimized: false,
            availability: .closed
        )

        try expectEqual(untitled.switcherListItem.title, "Untitled Window")
        try expectFalse(untitled.canFocus)
    }

    static func testReadableTextTrimsAsciiAndUnicodeBoundaryWhitespace() throws {
        let asciiSpacedWindow = WindowItem(
            windowIdentifier: 6,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: " Notes ",
            isMinimized: false,
            availability: .available
        )
        let unicodeSpacedWindow = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "\u{00A0}Project\u{00A0}",
            isMinimized: false,
            availability: .available
        )
        let plainWindow = WindowItem(
            windowIdentifier: 8,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            isMinimized: false,
            availability: .available
        )

        try expectEqual(asciiSpacedWindow.switcherListItem.title, "Notes")
        try expectEqual(unicodeSpacedWindow.switcherListItem.title, "Project")
        try expectEqual(plainWindow.switcherListItem.title, "Project")
    }
}
