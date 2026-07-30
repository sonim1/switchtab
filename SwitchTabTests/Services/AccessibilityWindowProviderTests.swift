import ApplicationServices
@testable import SwitchTab

enum AccessibilityWindowProviderTests {
    static func run() throws {
        try testProviderReturnsOnlyActiveApplicationWindows()
        try testProviderPassesActiveApplicationNameToWindowSnapshots()
        try testProviderCanSkipScreenCaptureIdentifiersForCurrentApplication()
        try testProviderReturnsApplicationWindowsForArbitraryProcessWithoutCaptureIdentifiers()
        try testWindowInclusionPolicyKeepsStandardWindows()
        try testWindowInclusionPolicyDropsChromeFindPanel()
        try testWindowInclusionPolicyMapsOnlyAcceptedWindows()
        try testWindowInclusionPolicyUsesResolvedWindowNumberAsStableIdentifier()
        try testWindowInclusionPolicyFallsBackToIndexIdentifierWithoutWindowNumber()
        try testProviderCarriesFocusedWindowFlagThrough()
        try testAXSnapshotProviderReadsAndMarksTheFocusedWindow()
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

    static func testProviderReturnsApplicationWindowsForArbitraryProcessWithoutCaptureIdentifiers() throws {
        let snapshotProvider = RecordingWindowSnapshotProvider(snapshots: [
            AccessibilityWindowSnapshot(
                windowIdentifier: 1,
                ownerProcessIdentifier: 84,
                ownerName: "Safari",
                title: "Available",
                isMinimized: false,
                availability: .available
            ),
            AccessibilityWindowSnapshot(
                windowIdentifier: 2,
                ownerProcessIdentifier: 84,
                ownerName: "Safari",
                title: "Minimized",
                isMinimized: true,
                availability: .minimized
            ),
            AccessibilityWindowSnapshot(
                windowIdentifier: 3,
                ownerProcessIdentifier: 84,
                ownerName: "Safari",
                title: "Closed",
                isMinimized: false,
                availability: .closed
            ),
            AccessibilityWindowSnapshot(
                windowIdentifier: 4,
                ownerProcessIdentifier: 42,
                ownerName: "Notes",
                title: "Other Application",
                isMinimized: false,
                availability: .available
            )
        ])
        let provider = AccessibilityWindowProvider(
            activeApplicationProvider: FakeActiveApplicationProvider(activeApplication: nil),
            windowSnapshotProvider: snapshotProvider
        )

        let windows = provider.applicationWindows(
            ownerProcessIdentifier: 84,
            ownerName: "Safari"
        )

        try expectEqual(snapshotProvider.requestedOwnerProcessIdentifier, 84)
        try expectEqual(snapshotProvider.requestedOwnerName, "Safari")
        try expectEqual(snapshotProvider.requestedIncludeScreenCaptureIdentifiers, false)
        try expectEqual(windows.map(\.windowIdentifier), [1, 2])
        try expectEqual(windows.map(\.isMinimized), [false, true])
        try expectEqual(windows.map(\.canFocus), [true, true])
        try expectEqual(windows.map(\.screenCaptureIdentifier), [nil, nil])
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

    static func testAXSnapshotProviderReadsAndMarksTheFocusedWindow() throws {
        let firstWindow = AXUIElementCreateApplication(101)
        let secondWindow = AXUIElementCreateApplication(102)
        let attributes = RecordingAXWindowAttributeReader(
            windowElements: [firstWindow, secondWindow],
            focusedWindowElement: secondWindow
        )
        let provider = AXWindowSnapshotProvider(
            windowNumberResolver: FixedAXWindowNumberResolver(
                elements: [firstWindow, secondWindow],
                identifiers: [11, 22]
            ),
            attributeReader: attributes
        )
        let snapshots = provider.windows(
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            includeScreenCaptureIdentifiers: false
        )

        try expectEqual(attributes.focusedWindowReadCount, 1)
        try expectEqual(snapshots.map(\.windowIdentifier), [11, 22])
        try expectEqual(snapshots.map(\.isFocused), [false, true])
    }
}

private final class RecordingAXWindowAttributeReader: AXWindowAttributeReading {
    let windowElements: [AXUIElement]
    let focusedWindowElement: AXUIElement?
    private(set) var focusedWindowReadCount = 0

    init(windowElements: [AXUIElement], focusedWindowElement: AXUIElement?) {
        self.windowElements = windowElements
        self.focusedWindowElement = focusedWindowElement
    }

    func windowElements(of _: AXUIElement) -> [AXUIElement]? {
        windowElements
    }

    func focusedWindowElement(of _: AXUIElement) -> AXUIElement? {
        focusedWindowReadCount += 1
        return focusedWindowElement
    }

    func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        let attributeName = attribute as String
        if attributeName == kAXRoleAttribute as String {
            return kAXWindowRole as String
        }
        if attributeName == kAXSubroleAttribute as String {
            return kAXStandardWindowSubrole as String
        }
        if attributeName == kAXTitleAttribute as String {
            return CFEqual(element, windowElements[0]) ? "First" : "Second"
        }
        return nil
    }

    func boolAttribute(_: AXUIElement, _: CFString) -> Bool {
        false
    }
}

private struct FixedAXWindowNumberResolver: AXWindowNumberResolving {
    let elements: [AXUIElement]
    let identifiers: [UInt32]

    func windowNumber(for element: AXUIElement) -> UInt32? {
        guard let index = elements.firstIndex(where: { CFEqual($0, element) }) else {
            return nil
        }
        return identifiers[index]
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
    let snapshots: [AccessibilityWindowSnapshot]
    private(set) var requestedOwnerProcessIdentifier: Int?
    private(set) var requestedOwnerName: String?
    private(set) var requestedIncludeScreenCaptureIdentifiers: Bool?

    init(snapshots: [AccessibilityWindowSnapshot] = []) {
        self.snapshots = snapshots
    }

    func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool
    ) -> [AccessibilityWindowSnapshot] {
        requestedOwnerProcessIdentifier = ownerProcessIdentifier
        requestedOwnerName = ownerName
        requestedIncludeScreenCaptureIdentifiers = includeScreenCaptureIdentifiers
        return snapshots
    }
}
