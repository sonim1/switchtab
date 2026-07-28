import Foundation
import SwitchTab

enum AccessibilityWindowProviderTests {
    static func run() throws {
        try testProviderReturnsOnlyActiveApplicationWindows()
        try testProviderPassesActiveApplicationNameToWindowSnapshots()
        try testProviderCanSkipScreenCaptureIdentifiersForCurrentApplication()
        try testWindowInclusionPolicyKeepsStandardWindows()
        try testWindowInclusionPolicyDropsChromeFindPanel()
        try testWindowInclusionPolicyMapsOnlyAcceptedWindows()
        try testWindowInclusionPolicyUsesResolvedWindowNumberAsStableIdentifier()
        try testWindowInclusionPolicyFallsBackToIndexIdentifierWithoutWindowNumber()
        try testProviderCarriesFocusedWindowFlagThrough()
        try testAccessibilityProviderAsksForTheFocusedWindow()
    }

    static func testProviderReturnsOnlyActiveApplicationWindows() throws {
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
                        title: "Work",
                        isMinimized: false,
                        availability: .available
                    ),
                    AccessibilityWindowSnapshot(
                        windowIdentifier: 2,
                        ownerProcessIdentifier: 7,
                        ownerName: "Safari",
                        title: "Docs",
                        isMinimized: false,
                        availability: .available
                    )
                ]
            )
        )

        let windows = provider.currentApplicationWindows()

        try expectEqual(windows.map(\.switcherListItem.subtitle), ["Notes"])
        try expectEqual(windows.map(\.switcherListItem.title), ["Work"])
    }

    static func testProviderPassesActiveApplicationNameToWindowSnapshots() throws {
        let snapshotProvider = RecordingWindowSnapshotProvider()
        let provider = AccessibilityWindowProvider(
            activeApplicationProvider: FakeActiveApplicationProvider(
                activeApplication: ActiveApplicationSnapshot(
                    processIdentifier: 42,
                    localizedName: "Notes"
                )
            ),
            windowSnapshotProvider: snapshotProvider
        )

        _ = provider.currentApplicationWindows()

        try expectEqual(snapshotProvider.requestedOwnerName, "Notes")
    }

    static func testProviderCanSkipScreenCaptureIdentifiersForCurrentApplication() throws {
        let snapshotProvider = RecordingWindowSnapshotProvider()
        let provider = AccessibilityWindowProvider(
            activeApplicationProvider: FakeActiveApplicationProvider(
                activeApplication: ActiveApplicationSnapshot(
                    processIdentifier: 42,
                    localizedName: "Notes"
                )
            ),
            windowSnapshotProvider: snapshotProvider
        )

        _ = provider.currentApplicationWindows(includeScreenCaptureIdentifiers: false)

        try expectEqual(snapshotProvider.requestedIncludeScreenCaptureIdentifiers, false)
    }

    static func testWindowInclusionPolicyKeepsStandardWindows() throws {
        try expectTrue(AccessibilityWindowInclusionPolicy.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow"
        ))
    }

    static func testWindowInclusionPolicyDropsChromeFindPanel() throws {
        try expectFalse(AccessibilityWindowInclusionPolicy.shouldInclude(
            role: "AXWindow",
            subrole: "AXUnknown"
        ))
    }

    static func testWindowInclusionPolicyMapsOnlyAcceptedWindows() throws {
        let mappings = AccessibilityWindowInclusionPolicy.acceptedWindowMappings(
            ownerProcessIdentifier: 42,
            candidates: [
                .init(originalIndex: 0, role: "AXWindow", subrole: "AXUnknown"),
                .init(originalIndex: 1, role: "AXWindow", subrole: "AXStandardWindow")
            ]
        )

        try expectEqual(mappings.map(\.originalIndex), [1])
        try expectEqual(mappings.map(\.windowIdentifier), [420_000])
    }

    static func testWindowInclusionPolicyUsesResolvedWindowNumberAsStableIdentifier() throws {
        let mappings = AccessibilityWindowInclusionPolicy.acceptedWindowMappings(
            ownerProcessIdentifier: 42,
            candidates: [
                .init(originalIndex: 0, role: "AXWindow", subrole: "AXStandardWindow", windowNumber: 555),
                .init(originalIndex: 1, role: "AXWindow", subrole: "AXStandardWindow", windowNumber: 777)
            ]
        )

        try expectEqual(mappings.map(\.windowIdentifier), [555, 777])
        try expectEqual(mappings.map(\.screenCaptureIdentifier), [UInt32(555), UInt32(777)])
    }

    static func testWindowInclusionPolicyFallsBackToIndexIdentifierWithoutWindowNumber() throws {
        let mappings = AccessibilityWindowInclusionPolicy.acceptedWindowMappings(
            ownerProcessIdentifier: 42,
            candidates: [
                .init(originalIndex: 0, role: "AXWindow", subrole: "AXStandardWindow", windowNumber: 555),
                .init(originalIndex: 1, role: "AXWindow", subrole: "AXStandardWindow", windowNumber: nil)
            ]
        )

        try expectEqual(mappings.map(\.windowIdentifier), [555, 420_001])
        try expectEqual(mappings.map(\.screenCaptureIdentifier), [UInt32(555), nil])
    }

    static func testProviderCarriesFocusedWindowFlagThrough() throws {
        let provider = AccessibilityWindowProvider(
            activeApplicationProvider: FakeActiveApplicationProvider(
                activeApplication: ActiveApplicationSnapshot(processIdentifier: 42)
            ),
            windowSnapshotProvider: FakeWindowSnapshotProvider(
                snapshots: [
                    AccessibilityWindowSnapshot(
                        windowIdentifier: 1,
                        ownerProcessIdentifier: 42,
                        ownerName: "Notes",
                        title: "Work",
                        isMinimized: false,
                        availability: .available
                    ),
                    AccessibilityWindowSnapshot(
                        windowIdentifier: 2,
                        ownerProcessIdentifier: 42,
                        ownerName: "Notes",
                        title: "Personal",
                        isMinimized: false,
                        availability: .available,
                        isFocused: true
                    )
                ]
            )
        )

        let windows = provider.currentApplicationWindows()

        try expectEqual(windows.map(\.isFocused), [false, true])
        try expectEqual(
            SwitcherWindowOrderPolicy.pinningFocusedWindowFirst(windows) { $0.isFocused }
                .map(\.switcherListItem.title),
            ["Personal", "Work"]
        )
    }

    static func testAccessibilityProviderAsksForTheFocusedWindow() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("SwitchTab/Services/AccessibilityWindowProvider.swift"),
            encoding: .utf8
        )

        try expectTrue(source.contains("kAXFocusedWindowAttribute"))
        try expectTrue(source.contains("CFEqual($0, windowElement)"))
    }
}

struct FakeActiveApplicationProvider: ActiveApplicationProviding {
    let activeApplication: ActiveApplicationSnapshot?

    func frontmostApplication() -> ActiveApplicationSnapshot? {
        activeApplication
    }
}

struct FakeWindowSnapshotProvider: AccessibilityWindowSnapshotProviding {
    let snapshots: [AccessibilityWindowSnapshot]

    func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool
    ) -> [AccessibilityWindowSnapshot] {
        snapshots
    }
}

final class RecordingWindowSnapshotProvider: AccessibilityWindowSnapshotProviding {
    private(set) var requestedOwnerName: String?
    private(set) var requestedIncludeScreenCaptureIdentifiers: Bool?

    func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool
    ) -> [AccessibilityWindowSnapshot] {
        requestedOwnerName = ownerName
        requestedIncludeScreenCaptureIdentifiers = includeScreenCaptureIdentifiers
        return []
    }
}
