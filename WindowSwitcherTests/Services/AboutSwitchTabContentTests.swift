import WindowSwitcher

enum AboutSwitchTabContentTests {
    @MainActor
    static func run() throws {
        try testFormatsVersionWithBuild()
        try testFormatsUsageSummaryForToday()
        try testAboutWindowControllerDefersContentUntilShown()
    }

    static func testFormatsVersionWithBuild() throws {
        let content = AboutSwitchTabContent(
            version: "1.2.3",
            build: "45",
            usageDashboard: .empty
        )

        try expectEqual(content.versionLine, "Version 1.2.3 (45)")
    }

    static func testFormatsUsageSummaryForToday() throws {
        let content = AboutSwitchTabContent(
            version: "1.0",
            build: "1",
            usageDashboard: UsageDashboardSnapshot(
                totalCount: 2,
                rows: [
                    UsageDashboardRow(
                        title: "Window Switches",
                        shortcutLabel: "Option + `",
                        count: 2
                    )
                ]
            )
        )

        try expectEqual(content.todaySummaryLine, "SwitchTab handled 2 shortcuts today")
    }

    @MainActor
    static func testAboutWindowControllerDefersContentUntilShown() throws {
        var contentProviderCallCount = 0

        _ = AboutWindowController {
            contentProviderCallCount += 1
            return AboutSwitchTabContent(
                version: "1.0",
                build: "1",
                usageDashboard: .empty
            )
        }

        try expectEqual(contentProviderCallCount, 0)
    }
}
