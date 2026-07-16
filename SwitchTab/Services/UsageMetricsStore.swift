import Foundation

public struct UsageDashboardRow: Equatable, Sendable {
    public let title: String
    public let shortcutLabel: String
    public let count: Int

    public init(title: String, shortcutLabel: String, count: Int) {
        self.title = title
        self.shortcutLabel = shortcutLabel
        self.count = count
    }
}

public struct UsageDashboardSnapshot: Equatable, Sendable {
    public static let empty = UsageDashboardSnapshot(totalCount: 0, rows: [])

    public let totalCount: Int
    public let rows: [UsageDashboardRow]

    public init(totalCount: Int, rows: [UsageDashboardRow]) {
        self.totalCount = totalCount
        self.rows = rows
    }
}

public protocol UsageMetricsPersisting: AnyObject {
    func integer(forKey key: String) -> Int
    func set(_ value: Int, forKey key: String)
}

extension UserDefaults: UsageMetricsPersisting {}

public final class UsageMetricsStore {
    private let persistence: any UsageMetricsPersisting
    private let calendar: Calendar
    private let now: () -> Date
    private var cachedWindowCount: Int?
    private var isWindowUsageDirty = false
    private var cachedDayStart: Date?
    private var cachedNextDayStart: Date?
    private var cachedDayKey: String?
    private var cachedWindowUsageStorageKey: String?

    public init(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = userDefaults
        self.calendar = calendar
        self.now = now
    }

    public init(
        persistence: any UsageMetricsPersisting,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
    }

    public func recordWindowShortcutUse() {
        let date = now()
        cachedWindowCount = cachedWindowUsageCount(on: date) + 1
        isWindowUsageDirty = true
    }

    public func windowCount(on date: Date) -> Int {
        cachedWindowUsageCount(on: date)
    }

    public func flush() {
        guard isWindowUsageDirty else {
            return
        }

        if isWindowUsageDirty,
           let cachedWindowCount,
           let cachedWindowUsageStorageKey {
            persistence.set(cachedWindowCount, forKey: cachedWindowUsageStorageKey)
            isWindowUsageDirty = false
        }
    }

    public func todayDashboard(windowShortcutLabel: String) -> UsageDashboardSnapshot {
        let date = now()
        let windowCount = cachedWindowUsageCount(on: date)
        let rows = [
            UsageDashboardRow(
                title: "Window Switches",
                shortcutLabel: windowShortcutLabel,
                count: windowCount
            )
        ]

        return UsageDashboardSnapshot(totalCount: windowCount, rows: rows)
    }

    private func windowUsageStorageKey(dayKey: String) -> String {
        if let cachedWindowUsageStorageKey {
            return cachedWindowUsageStorageKey
        }

        let key = "SwitchTab.usage.\(dayKey).currentAppWindowSwitching"
        cachedWindowUsageStorageKey = key
        return key
    }

    private func cachedWindowUsageCount(on date: Date) -> Int {
        let dayKey = dayKey(for: date)
        if let cachedWindowCount {
            return cachedWindowCount
        }

        let key = windowUsageStorageKey(dayKey: dayKey)
        let persistedCount = persistence.integer(forKey: key)
        cachedWindowCount = persistedCount
        return persistedCount
    }

    private func dayKey(for date: Date) -> String {
        if let cachedDayStart,
           let cachedNextDayStart,
           let cachedDayKey,
           date >= cachedDayStart,
           date < cachedNextDayStart {
            return cachedDayKey
        }

        flush()
        let dayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            preconditionFailure("Calendar did not provide day components")
        }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        cachedDayStart = dayStart
        cachedNextDayStart = nextDayStart
        cachedDayKey = dayKey
        cachedWindowCount = nil
        cachedWindowUsageStorageKey = nil
        return dayKey
    }
}
