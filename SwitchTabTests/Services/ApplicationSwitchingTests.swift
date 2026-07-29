@testable import SwitchTab

enum ApplicationSwitchingTests {
    static func run() throws {
        try testProviderFiltersNonRegularTerminatedAndOwnBundleApplications()
        try testProviderUsesUnknownApplicationForMissingOrBlankNames()
        try testProviderDeduplicatesBundleIdentifiersUsingActiveRepresentative()
        try testProviderUsesDeterministicProcessScopedFallbackIdentifiers()
        try testProviderPreservesIncomingSnapshotOrder()
        try testProviderMapsApplicationIconsToProcessIdentifiers()
    }

    static func testProviderFiltersNonRegularTerminatedAndOwnBundleApplications() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 10,
                    bundleIdentifier: "com.apple.finder",
                    localizedName: "Finder",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 11,
                    bundleIdentifier: "com.example.helper",
                    localizedName: "Helper",
                    isRegular: false,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 12,
                    bundleIdentifier: "com.example.terminated",
                    localizedName: "Terminated",
                    isRegular: true,
                    isTerminated: true,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 13,
                    bundleIdentifier: "com.royjen.switchtab",
                    localizedName: "SwitchTab",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        try expectEqual(provider.runningApplications().map(\.id), ["com.apple.finder"])
    }

    static func testProviderUsesUnknownApplicationForMissingOrBlankNames() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 20,
                    bundleIdentifier: "com.example.missing-name",
                    localizedName: nil,
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 21,
                    bundleIdentifier: "com.example.blank-name",
                    localizedName: " \t ",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        try expectEqual(
            provider.runningApplications().map(\.switcherListItem.title),
            ["Unknown Application", "Unknown Application"]
        )
    }

    static func testProviderDeduplicatesBundleIdentifiersUsingActiveRepresentative() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 30,
                    bundleIdentifier: "com.example.shared",
                    localizedName: "First",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 32,
                    bundleIdentifier: "com.example.other",
                    localizedName: "Other",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 31,
                    bundleIdentifier: "com.example.shared",
                    localizedName: "Active Duplicate",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.id), ["com.example.shared", "com.example.other"])
        try expectEqual(applications.map(\.processIdentifier), [31, 32])
        try expectEqual(applications.map(\.switcherListItem.title), ["Active Duplicate", "Other"])
        try expectEqual(applications.map(\.bundleIdentifier), ["com.example.shared", "com.example.other"])
        try expectEqual(applications.map(\.isActive), [true, false])
    }

    static func testProviderUsesDeterministicProcessScopedFallbackIdentifiers() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 40,
                    bundleIdentifier: nil,
                    localizedName: "First",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 41,
                    bundleIdentifier: "",
                    localizedName: "Second",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 40,
                    bundleIdentifier: nil,
                    localizedName: "Duplicate PID",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.id), ["pid:40", "pid:41"])
        try expectEqual(applications.map(\.processIdentifier), [40, 41])
        try expectEqual(applications.map(\.switcherListItem.title), ["First", "Second"])
        try expectEqual(applications.map(\.isActive), [false, false])
    }

    static func testProviderPreservesIncomingSnapshotOrder() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 50,
                    bundleIdentifier: "com.example.safari",
                    localizedName: "Safari",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 51,
                    bundleIdentifier: "com.example.finder",
                    localizedName: "Finder",
                    isRegular: true,
                    isTerminated: false,
                    isActive: true
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 52,
                    bundleIdentifier: "com.example.notes",
                    localizedName: "Notes",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(applications.map(\.switcherListItem.title), ["Safari", "Finder", "Notes"])
        try expectEqual(
            applications.map(\.bundleIdentifier),
            ["com.example.safari", "com.example.finder", "com.example.notes"]
        )
        try expectEqual(applications.map(\.isActive), [false, true, false])
    }

    static func testProviderMapsApplicationIconsToProcessIdentifiers() throws {
        let provider = RunningApplicationProvider(
            snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots: [
                RunningApplicationSnapshot(
                    processIdentifier: 60,
                    bundleIdentifier: "com.example.one",
                    localizedName: "One",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                ),
                RunningApplicationSnapshot(
                    processIdentifier: 61,
                    bundleIdentifier: "com.example.two",
                    localizedName: "Two",
                    isRegular: true,
                    isTerminated: false,
                    isActive: false
                )
            ]),
            ownBundleIdentifier: "com.royjen.switchtab"
        )

        let applications = provider.runningApplications()
        try expectEqual(
            applications.map(\.switcherListItem.appIconProcessIdentifier),
            [60, 61]
        )
        try expectEqual(applications.map { $0.switcherListItem.id }, applications.map(\.id))
    }
}

private struct FakeRunningApplicationSnapshotProvider: RunningApplicationSnapshotProviding {
    let snapshotValues: [RunningApplicationSnapshot]

    init(snapshots: [RunningApplicationSnapshot]) {
        self.snapshotValues = snapshots
    }

    func snapshots() -> [RunningApplicationSnapshot] {
        snapshotValues
    }
}
