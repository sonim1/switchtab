import Foundation

public struct AboutSwitchTabContent: Equatable, Sendable {
    public let version: String
    public let build: String
    public let usageDashboard: UsageDashboardSnapshot

    public init(version: String, build: String, usageDashboard: UsageDashboardSnapshot) {
        self.version = version
        self.build = build
        self.usageDashboard = usageDashboard
    }

    public static func current(
        bundle: Bundle = .main,
        usageDashboard: UsageDashboardSnapshot
    ) -> AboutSwitchTabContent {
        AboutSwitchTabContent(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            usageDashboard: usageDashboard
        )
    }

    public var versionLine: String {
        "Version \(version)"
    }

    public var buildLine: String? {
        guard !build.isEmpty else {
            return nil
        }

        return "Build Number \(build)"
    }

    public var todaySummaryLine: String {
        let suffix = usageDashboard.totalCount == 1 ? "shortcut" : "shortcuts"
        return "SwitchTab handled \(usageDashboard.totalCount) \(suffix) today"
    }
}
