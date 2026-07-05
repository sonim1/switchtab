import Foundation
import WindowSwitcher

enum UsageMetricsStoreTests {
    static func run() throws {
        try testRecordsTodayWindowShortcutCounts()
        try testSeparatesCountsByDay()
        try testCachedDayKeyRefreshesWhenDayChanges()
        try testDayChangePersistsDirtyCountsBeforeSwitchingCache()
        try testBuildsTodayDashboardRowsWithShortcutLabels()
        try testUsageDashboardSnapshotExposesSharedEmptySnapshot()
        try testRecordsInMemoryAndPersistsOnFlush()
    }

    static func testRecordsTodayWindowShortcutCounts() throws {
        let store = UsageMetricsStore(
            userDefaults: makeDefaults(),
            calendar: fixedCalendar,
            now: { fixedDate }
        )

        store.recordWindowShortcutUse()
        store.recordWindowShortcutUse()
        store.recordWindowShortcutUse()

        try expectEqual(store.windowCount(on: fixedDate), 3)
    }

    static func testSeparatesCountsByDay() throws {
        let defaults = makeDefaults()
        let store = UsageMetricsStore(
            userDefaults: defaults,
            calendar: fixedCalendar,
            now: { fixedDate }
        )
        let tomorrowStore = UsageMetricsStore(
            userDefaults: defaults,
            calendar: fixedCalendar,
            now: { fixedCalendar.date(byAdding: .day, value: 1, to: fixedDate)! }
        )

        store.recordWindowShortcutUse()
        tomorrowStore.recordWindowShortcutUse()
        tomorrowStore.recordWindowShortcutUse()

        try expectEqual(store.windowCount(on: fixedDate), 1)
        try expectEqual(
            tomorrowStore.windowCount(on: fixedCalendar.date(byAdding: .day, value: 1, to: fixedDate)!),
            2
        )
    }

    static func testCachedDayKeyRefreshesWhenDayChanges() throws {
        let defaults = makeDefaults()
        var currentDate = fixedDate
        let tomorrow = fixedCalendar.date(byAdding: .day, value: 1, to: fixedDate)!
        let store = UsageMetricsStore(
            userDefaults: defaults,
            calendar: fixedCalendar,
            now: { currentDate }
        )

        store.recordWindowShortcutUse()
        currentDate = tomorrow
        store.recordWindowShortcutUse()

        try expectEqual(store.windowCount(on: fixedDate), 1)
        try expectEqual(store.windowCount(on: tomorrow), 1)
    }

    static func testDayChangePersistsDirtyCountsBeforeSwitchingCache() throws {
        let persistence = FakeUsageMetricsPersistence()
        var currentDate = fixedDate
        let tomorrow = fixedCalendar.date(byAdding: .day, value: 1, to: fixedDate)!
        let store = UsageMetricsStore(
            persistence: persistence,
            calendar: fixedCalendar,
            now: { currentDate }
        )

        store.recordWindowShortcutUse()
        currentDate = tomorrow
        store.recordWindowShortcutUse()
        store.flush()

        try expectEqual(persistence.writeCount, 2)
        try expectEqual(
            persistence.values["WindowSwitcher.usage.2026-05-28.currentAppWindowSwitching"],
            1
        )
        try expectEqual(
            persistence.values["WindowSwitcher.usage.2026-05-29.currentAppWindowSwitching"],
            1
        )
    }

    static func testBuildsTodayDashboardRowsWithShortcutLabels() throws {
        let store = UsageMetricsStore(
            userDefaults: makeDefaults(),
            calendar: fixedCalendar,
            now: { fixedDate }
        )

        store.recordWindowShortcutUse()
        store.recordWindowShortcutUse()
        let dashboard = store.todayDashboard(windowShortcutLabel: "Option + `")

        try expectEqual(dashboard.totalCount, 2)
        try expectEqual(dashboard.rows.count, 1)
        try expectEqual(dashboard.rows[0].shortcutLabel, "Option + `")
        try expectEqual(dashboard.rows[0].count, 2)
    }

    static func testUsageDashboardSnapshotExposesSharedEmptySnapshot() throws {
        let dashboard = UsageDashboardSnapshot.empty

        try expectEqual(dashboard.totalCount, 0)
        try expectEqual(dashboard.rows, [])
    }

    static func testRecordsInMemoryAndPersistsOnFlush() throws {
        let persistence = FakeUsageMetricsPersistence()
        let store = UsageMetricsStore(
            persistence: persistence,
            calendar: fixedCalendar,
            now: { fixedDate }
        )

        store.recordWindowShortcutUse()
        store.recordWindowShortcutUse()

        try expectEqual(store.windowCount(on: fixedDate), 2)
        try expectEqual(persistence.readCount, 1)
        try expectEqual(persistence.writeCount, 0)

        store.flush()

        try expectEqual(persistence.writeCount, 1)
        try expectEqual(persistence.values.values.first, 2)
    }

    private static let fixedCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let fixedDate = Date(timeIntervalSince1970: 1_780_000_000)

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "WindowSwitcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class FakeUsageMetricsPersistence: UsageMetricsPersisting {
    private(set) var values: [String: Int] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0

    func integer(forKey key: String) -> Int {
        readCount += 1
        return values[key] ?? 0
    }

    func set(_ value: Int, forKey key: String) {
        writeCount += 1
        values[key] = value
    }
}
