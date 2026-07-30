import SwitchTab

enum AboutSwitchTabContentTests {
    @MainActor
    static func run() throws {
        try testFormatsVersionAndBuildSeparately()
        try testOmitsEmptyBuildNumber()
        try testFormatsUsageSummaryForToday()
        try testAboutWindowControllerDefersContentUntilShown()
    }

    static func testFormatsVersionAndBuildSeparately() throws {
        let content = AboutSwitchTabContent(
            version: "1.2.3",
            build: "45",
            usageDashboard: .empty
        )

        try expectEqual(content.versionLine, "Version 1.2.3")
        try expectEqual(content.buildLine, "Build Number 45")
    }

    static func testOmitsEmptyBuildNumber() throws {
        let content = AboutSwitchTabContent(
            version: "1.2.3",
            build: "",
            usageDashboard: .empty
        )

        try expectEqual(content.versionLine, "Version 1.2.3")
        try expectEqual(content.buildLine, nil)
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
