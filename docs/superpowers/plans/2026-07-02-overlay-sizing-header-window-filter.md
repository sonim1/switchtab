# Overlay Sizing, Header, and Window Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the window switcher panel fit its content, add a user-selectable overlay size, move window titles above thumbnails with app icons, and filter Chrome `Find in page`/non-window AX panels.

**Architecture:** Add a persisted `OverlaySizePreference` model, store it through `ApplicationSettingsStore`, route it into overlay layout computation, and make overlay metrics scale tile, thumbnail, icon, padding, and spacing. Keep AX filtering inside `AccessibilityWindowProvider` using a pure inclusion policy plus a small wiring helper tested independently from live macOS APIs.

**Tech Stack:** Swift 5, SwiftUI, AppKit, ApplicationServices Accessibility, UserDefaults, custom `WindowSwitcherTestRunner`.

---

## File Map

- Add `WindowSwitcher/Models/OverlaySizePreference.swift`
  - Define compact/default/large values and display names.

- Modify `WindowSwitcher.xcodeproj/project.pbxproj`
  - Add `OverlaySizePreference.swift` to the Models group and app target source phase.

- Modify `WindowSwitcher/Services/ApplicationSettingsStore.swift`
  - Persist selected overlay size in UserDefaults.
  - Reuse `.applicationSettingsDidChange` notifications.

- Modify `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`
  - Publish current overlay size.
  - Add `setOverlaySize(_:)`.

- Modify `WindowSwitcher/UI/Settings/ShortcutSettingsView.swift`
  - Add segmented `Overlay size` picker under General.

- Modify `WindowSwitcher/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
  - Add `SwitcherOverlayLayoutMetrics`.
  - Add `overlaySize` input to `presentationLayout`.
  - Remove `320px` minimum for one/two item layouts.

- Modify `WindowSwitcher/UI/Overlay/SwitcherOverlayController.swift`
  - Read overlay size from `ApplicationSettingsStore` before presenting.
  - Pass layout metrics to root view and grid columns.

- Modify `WindowSwitcher/UI/Overlay/SwitcherOverlayRootView.swift`
  - Accept and pass layout metrics.

- Modify `WindowSwitcher/UI/Overlay/SwitcherIconStripView.swift`
  - Move title above thumbnail.
  - Show small app icon beside title.
  - Use layout metrics for tile, thumbnail, and fallback icon sizes.

- Modify `WindowSwitcher/Services/AccessibilityWindowProvider.swift`
  - Add `AccessibilityWindowInclusionPolicy`.
  - Filter AX elements to `AXWindow` + `AXStandardWindow`.

- Modify tests:
  - `WindowSwitcherTests/Services/ApplicationSettingsStoreTests.swift`
  - `WindowSwitcherTests/Services/SwitcherOverlayPresentationTests.swift`
  - `WindowSwitcherTests/Services/AccessibilityWindowProviderTests.swift`

---

### Task 1: Persist Overlay Size Setting

**Files:**
- Add: `WindowSwitcher/Models/OverlaySizePreference.swift`
- Modify: `WindowSwitcher/Services/ApplicationSettingsStore.swift`
- Modify: `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`
- Modify: `WindowSwitcher.xcodeproj/project.pbxproj`
- Modify: `WindowSwitcherTests/Services/ApplicationSettingsStoreTests.swift`

- [x] **Step 1: Write failing store/view-model tests**

Add these calls inside `ApplicationSettingsStoreTests.run()`:

```swift
try testOverlaySizeDefaultsToStandard()
try testOverlaySizePersists()
try testViewModelUpdatesOverlaySize()
```

Add these test functions before `makeDefaults()`:

```swift
static func testOverlaySizeDefaultsToStandard() throws {
    let store = ApplicationSettingsStore(userDefaults: makeDefaults())

    try expectEqual(store.overlaySize, .standard)
}

static func testOverlaySizePersists() throws {
    let defaults = makeDefaults()
    let store = ApplicationSettingsStore(userDefaults: defaults)

    store.saveOverlaySize(.compact)

    try expectEqual(ApplicationSettingsStore(userDefaults: defaults).overlaySize, .compact)
}

@MainActor
static func testViewModelUpdatesOverlaySize() throws {
    let defaults = makeDefaults()
    let viewModel = ApplicationSettingsViewModel(
        store: ApplicationSettingsStore(userDefaults: defaults),
        launchAtLoginService: FakeLaunchAtLoginService()
    )

    viewModel.setOverlaySize(.large)

    try expectEqual(viewModel.overlaySize, .large)
    try expectEqual(ApplicationSettingsStore(userDefaults: defaults).overlaySize, .large)
}
```

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: compile failure mentioning missing `overlaySize`, `OverlaySizePreference`, or `setOverlaySize`.

- [x] **Step 3: Add `OverlaySizePreference` model and store methods**

Create `WindowSwitcher/Models/OverlaySizePreference.swift`:

```swift
public enum OverlaySizePreference: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .compact:
            "Compact"
        case .standard:
            "Default"
        case .large:
            "Large"
        }
    }
}
```

Add `OverlaySizePreference.swift` to `WindowSwitcher.xcodeproj/project.pbxproj` in both places:

- `Models` group children.
- `WindowSwitcher` target `PBXSourcesBuildPhase`.

Add this key inside `ApplicationSettingsStore`:

```swift
public static let overlaySizeKey = "ApplicationSettings.overlaySize"
```

Add these members inside `ApplicationSettingsStore`:

```swift
public var overlaySize: OverlaySizePreference {
    guard let rawValue = userDefaults.string(forKey: Self.overlaySizeKey),
          let preference = OverlaySizePreference(rawValue: rawValue) else {
        return .standard
    }

    return preference
}

public func saveOverlaySize(_ size: OverlaySizePreference) {
    userDefaults.set(size.rawValue, forKey: Self.overlaySizeKey)
    NotificationCenter.default.post(name: .applicationSettingsDidChange, object: nil)
}
```

- [x] **Step 4: Add view-model state**

In `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`, add published property:

```swift
@Published public private(set) var overlaySize: OverlaySizePreference
```

In `init`, set:

```swift
self.overlaySize = store.overlaySize
```

Add method:

```swift
public func setOverlaySize(_ size: OverlaySizePreference) {
    guard overlaySize != size else {
        return
    }

    store.saveOverlaySize(size)
    overlaySize = size
}
```

- [x] **Step 5: Run tests and verify GREEN for Task 1**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: this task's new tests pass. Later tasks may still be unimplemented.

---

### Task 2: Add Overlay Size Picker to Settings

**Files:**
- Modify: `WindowSwitcher/UI/Settings/ShortcutSettingsView.swift`

- [x] **Step 1: Add picker UI**

In `ShortcutSettingsView.body`, after the `Menubar Icon` toggle and before the first `Divider()`, add:

```swift
Picker(
    "Overlay size",
    selection: Binding(
        get: { applicationSettingsViewModel.overlaySize },
        set: { applicationSettingsViewModel.setOverlaySize($0) }
    )
) {
    ForEach(OverlaySizePreference.allCases) { size in
        Text(size.displayName).tag(size)
    }
}
.pickerStyle(.segmented)
```

- [x] **Step 2: Build to verify UI compiles**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: all current tests pass.

---

### Task 3: Scale Overlay Layout and Fix Single-Item Width

**Files:**
- Modify: `WindowSwitcher/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `WindowSwitcher/UI/Overlay/SwitcherOverlayController.swift`
- Modify: `WindowSwitcher/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `WindowSwitcher/UI/Overlay/SwitcherIconStripView.swift`
- Modify: `WindowSwitcherTests/Services/SwitcherOverlayPresentationTests.swift`

- [x] **Step 1: Write failing layout tests**

In `SwitcherOverlayPresentationTests.run()`, add:

```swift
try testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum()
try testOverlaySizePreferenceScalesLayout()
try testOverlaySizePreferenceScalesMultiRowLayout()
```

Add these tests:

```swift
static func testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum() throws {
    let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 1,
        screenSize: CGSize(width: 1440, height: 900),
        overlaySize: .standard
    )

    try expectEqual(layout.gridColumnCount, 1)
    try expectEqual(layout.size.width, 152)
    try expectEqual(layout.size.height, 148)
}

static func testOverlaySizePreferenceScalesLayout() throws {
    let compact = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 1,
        screenSize: CGSize(width: 1440, height: 900),
        overlaySize: .compact
    )
    let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 1,
        screenSize: CGSize(width: 1440, height: 900),
        overlaySize: .standard
    )
    let large = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 1,
        screenSize: CGSize(width: 1440, height: 900),
        overlaySize: .large
    )

    try expectEqual(compact.size.width, 132)
    try expectEqual(compact.size.height, 132)
    try expectEqual(standard.size.width, 152)
    try expectEqual(standard.size.height, 148)
    try expectEqual(large.size.width, 180)
    try expectEqual(large.size.height, 176)
}

static func testOverlaySizePreferenceScalesMultiRowLayout() throws {
    let compact = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 9,
        screenSize: CGSize(width: 1000, height: 700),
        overlaySize: .compact
    )
    let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 9,
        screenSize: CGSize(width: 1000, height: 700),
        overlaySize: .standard
    )
    let large = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 9,
        screenSize: CGSize(width: 1000, height: 700),
        overlaySize: .large
    )

    try expectTrue(compact.size.width < standard.size.width)
    try expectTrue(standard.size.width < large.size.width)
    try expectTrue(compact.size.height < standard.size.height)
    try expectTrue(standard.size.height < large.size.height)
    try expectEqual(standard.gridColumnCount, 5)
}
```

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: compile failure because `presentationLayout(... overlaySize:)` does not exist.

- [x] **Step 3: Add layout metrics**

In `SwitcherOverlayLayoutPolicy.swift`, add:

```swift
public struct SwitcherOverlayLayoutMetrics: Equatable {
    public let tileSize: CGSize
    public let thumbnailSize: CGSize
    public let fallbackIconSize: CGSize
    public let headerIconSize: CGSize
    public let gridSpacing: CGFloat
    public let gridPadding: CGFloat

    public static func metrics(for overlaySize: OverlaySizePreference) -> SwitcherOverlayLayoutMetrics {
        switch overlaySize {
        case .compact:
            SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 112, height: 112),
                thumbnailSize: CGSize(width: 104, height: 72),
                fallbackIconSize: CGSize(width: 76, height: 76),
                headerIconSize: CGSize(width: 14, height: 14),
                gridSpacing: 10,
                gridPadding: 20
            )
        case .standard:
            SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 128, height: 124),
                thumbnailSize: CGSize(width: 120, height: 84),
                fallbackIconSize: CGSize(width: 88, height: 88),
                headerIconSize: CGSize(width: 16, height: 16),
                gridSpacing: 12,
                gridPadding: 24
            )
        case .large:
            SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 152, height: 148),
                thumbnailSize: CGSize(width: 144, height: 100),
                fallbackIconSize: CGSize(width: 104, height: 104),
                headerIconSize: CGSize(width: 18, height: 18),
                gridSpacing: 14,
                gridPadding: 28
            )
        }
    }
}
```

Update `SwitcherOverlayPresentationLayout`:

```swift
public struct SwitcherOverlayPresentationLayout: Equatable {
    public let size: CGSize
    public let gridColumnCount: Int
    public let metrics: SwitcherOverlayLayoutMetrics
}
```

- [x] **Step 4: Update layout policy calculations**

Change `presentationLayout` signature:

```swift
public static func presentationLayout(
    itemCount: Int,
    screenSize: CGSize,
    overlaySize: OverlaySizePreference = .standard
) -> SwitcherOverlayPresentationLayout {
    let metrics = SwitcherOverlayLayoutMetrics.metrics(for: overlaySize)
    guard itemCount > 2 else {
        return SwitcherOverlayPresentationLayout(
            size: smallItemLayoutSize(screenSize: screenSize, metrics: metrics),
            gridColumnCount: itemCount == 2 ? 2 : 1,
            metrics: metrics
        )
    }

    let gridLayout = iconGridLayout(itemCount: itemCount, screenSize: screenSize, metrics: metrics)
    return SwitcherOverlayPresentationLayout(
        size: presentationSize(gridLayout: gridLayout, screenSize: screenSize, metrics: metrics),
        gridColumnCount: gridLayout.columnCount,
        metrics: metrics
    )
}
```

Replace hard-coded tile/spacing/padding calculations with `metrics`:

```swift
private static func presentationSize(
    gridLayout: SwitcherIconGridLayout,
    screenSize: CGSize,
    metrics: SwitcherOverlayLayoutMetrics
) -> CGSize {
    let availableWidth = max(180, screenSize.width - screenHorizontalMargin)
    let contentWidth = iconGridContentWidth(columnCount: gridLayout.columnCount, metrics: metrics)
    let contentHeight = iconGridContentHeight(rowCount: gridLayout.visibleRowCount, metrics: metrics)
    let width = min(contentWidth, availableWidth)

    return CGSize(width: width.rounded(.up), height: contentHeight.rounded(.up))
}

private static func iconGridLayout(
    itemCount: Int,
    screenSize: CGSize,
    metrics: SwitcherOverlayLayoutMetrics
) -> SwitcherIconGridLayout {
    guard itemCount > 1 else {
        return SwitcherIconGridLayout(columnCount: 1, visibleRowCount: 1)
    }

    if itemCount == 2 {
        return SwitcherIconGridLayout(columnCount: 2, visibleRowCount: 1)
    }

    let availableWidth = max(iconGridContentWidth(columnCount: 1, metrics: metrics), screenSize.width - screenHorizontalMargin)
    let maxColumns = max(1, iconGridColumnCount(forOverlayWidth: availableWidth, metrics: metrics))
    let rowsAtMaxWidth = ceilDivision(itemCount, by: maxColumns)
    let visibleRowCount = min(maximumVisibleIconGridRows, max(1, rowsAtMaxWidth))
    let balancedColumns = ceilDivision(itemCount, by: visibleRowCount)
    let columnCount = min(maxColumns, max(1, balancedColumns))

    return SwitcherIconGridLayout(columnCount: columnCount, visibleRowCount: visibleRowCount)
}

private static func iconGridColumnCount(
    forOverlayWidth width: CGFloat,
    metrics: SwitcherOverlayLayoutMetrics
) -> Int {
    let contentWidth = max(1, width - metrics.gridPadding)
    return max(1, Int(((contentWidth + metrics.gridSpacing) / (metrics.tileSize.width + metrics.gridSpacing)).rounded(.down)))
}

private static func iconGridContentWidth(
    columnCount: Int,
    metrics: SwitcherOverlayLayoutMetrics
) -> CGFloat {
    CGFloat(columnCount) * metrics.tileSize.width
        + CGFloat(max(columnCount - 1, 0)) * metrics.gridSpacing
        + metrics.gridPadding
}

private static func iconGridContentHeight(
    rowCount: Int,
    metrics: SwitcherOverlayLayoutMetrics
) -> CGFloat {
    CGFloat(rowCount) * metrics.tileSize.height
        + CGFloat(max(rowCount - 1, 0)) * metrics.gridSpacing
        + metrics.gridPadding
}

private static func smallItemLayoutSize(
    screenSize: CGSize,
    metrics: SwitcherOverlayLayoutMetrics
) -> CGSize {
    let availableWidth = max(180, screenSize.width - screenHorizontalMargin)
    let columns = 1
    let width = min(iconGridContentWidth(columnCount: columns, metrics: metrics), availableWidth)
    let height = iconGridContentHeight(rowCount: 1, metrics: metrics)
    return CGSize(width: width.rounded(.up), height: height.rounded(.up))
}
```

- [x] **Step 5: Route metrics through controller/root/icon view**

In `SwitcherOverlayController`, add property:

```swift
private let applicationSettingsStore: ApplicationSettingsStore
private var presentationLayoutMetrics = SwitcherOverlayLayoutMetrics.metrics(for: .standard)
```

Change initializer:

```swift
init(
    thumbnailStore: WindowThumbnailStore,
    applicationIconStore: ApplicationIconStore? = nil,
    applicationSettingsStore: ApplicationSettingsStore = ApplicationSettingsStore()
) {
    self.thumbnailStore = thumbnailStore
    self.applicationIconStore = applicationIconStore ?? ApplicationIconStore()
    self.applicationSettingsStore = applicationSettingsStore
}
```

After computing `presentationLayout`, set:

```swift
presentationLayoutMetrics = presentationLayout.metrics
presentationGridColumns = SwitcherIconStripView.gridColumns(
    columnCount: presentationLayout.gridColumnCount,
    metrics: presentationLayout.metrics
)
```

Change `currentPresentationLayout`:

```swift
SwitcherOverlayLayoutPolicy.presentationLayout(
    itemCount: session.items.count,
    screenSize: screenSize ?? SwitcherOverlayLayoutPolicy.defaultSize,
    overlaySize: applicationSettingsStore.overlaySize
)
```

Pass `layoutMetrics: presentationLayoutMetrics` to `SwitcherOverlayRootView`.

- [x] **Step 6: Update root and icon views to accept metrics**

Add `layoutMetrics: SwitcherOverlayLayoutMetrics` to `SwitcherOverlayRootView` stored properties and initializer, then pass it into `SwitcherIconStripView`.

In `SwitcherIconStripView`, replace static grid column with:

```swift
static func gridColumns(
    columnCount: Int,
    metrics: SwitcherOverlayLayoutMetrics
) -> [GridItem] {
    guard columnCount > 0 else {
        return []
    }

    return Array(
        repeating: GridItem(.fixed(metrics.tileSize.width), spacing: metrics.gridSpacing),
        count: columnCount
    )
}
```

Add stored property:

```swift
private let layoutMetrics: SwitcherOverlayLayoutMetrics
```

Use `layoutMetrics.tileSize` instead of `SwitcherOverlayLayoutPolicy.iconGridTileSize`.
Use `layoutMetrics.gridSpacing` for `LazyVGrid` row spacing so layout calculation and rendered grid spacing share one source of truth:

```swift
LazyVGrid(columns: gridColumns, spacing: layoutMetrics.gridSpacing) {
    ...
}
```

- [x] **Step 7: Run tests and verify GREEN for layout**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: layout tests pass. Existing expected widths for 4, 5, 9, and 25 items should remain unchanged for `.standard`.

---

### Task 4: Move Title Above Thumbnail and Show App Icon

**Files:**
- Modify: `WindowSwitcher/UI/Overlay/SwitcherIconStripView.swift`

- [x] **Step 1: Replace button content layout**

Replace the `VStack` inside `iconButton` with:

```swift
VStack(alignment: .leading, spacing: 6) {
    titleHeader(for: item)
    icon(for: item)
}
.padding(4)
.frame(width: layoutMetrics.tileSize.width, height: layoutMetrics.tileSize.height)
.background(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
.clipShape(RoundedRectangle(cornerRadius: 7))
```

- [x] **Step 2: Add title header**

Add:

```swift
private func titleHeader(for item: SwitcherListItem) -> some View {
    HStack(spacing: 5) {
        if let processIdentifier = item.appIconProcessIdentifier,
           let icon = applicationIconStore.icon(for: processIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(
                    width: layoutMetrics.headerIconSize.width,
                    height: layoutMetrics.headerIconSize.height
                )
        } else {
            Image(systemName: item.symbolName ?? "macwindow")
                .font(.system(size: layoutMetrics.headerIconSize.height))
                .frame(
                    width: layoutMetrics.headerIconSize.width,
                    height: layoutMetrics.headerIconSize.height
                )
        }

        Text(item.title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
    }
    .frame(width: layoutMetrics.thumbnailSize.width, alignment: .leading)
}
```

- [x] **Step 3: Update thumbnail/fallback sizes**

Change `WindowThumbnailIconView` to accept `layoutMetrics`. Use:

```swift
.frame(width: layoutMetrics.thumbnailSize.width, height: layoutMetrics.thumbnailSize.height)
```

for thumbnail images, and:

```swift
.frame(width: layoutMetrics.fallbackIconSize.width, height: layoutMetrics.fallbackIconSize.height)
.frame(width: layoutMetrics.thumbnailSize.width, height: layoutMetrics.thumbnailSize.height)
```

for fallback app icons and SF Symbols.

- [x] **Step 4: Build to verify SwiftUI compiles**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: tests pass.

---

### Task 5: Filter Chrome Find/Non-Standard AX Windows

**Files:**
- Modify: `WindowSwitcher/Services/AccessibilityWindowProvider.swift`
- Modify: `WindowSwitcherTests/Services/AccessibilityWindowProviderTests.swift`

- [x] **Step 1: Write failing policy tests**

In `AccessibilityWindowProviderTests.run()`, add:

```swift
try testWindowInclusionPolicyKeepsStandardWindows()
try testWindowInclusionPolicyDropsChromeFindPanel()
try testWindowInclusionPolicyMapsOnlyAcceptedWindows()
```

Add:

```swift
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
```

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: compile failure because `AccessibilityWindowInclusionPolicy` is missing.

- [x] **Step 3: Add inclusion policy**

In `AccessibilityWindowProvider.swift`, add the inclusion policy plus a tiny pure mapping helper used by the production loop:

```swift
public struct AccessibilityWindowInclusionCandidate: Equatable {
    public let originalIndex: Int
    public let role: String?
    public let subrole: String?

    public init(originalIndex: Int, role: String?, subrole: String?) {
        self.originalIndex = originalIndex
        self.role = role
        self.subrole = subrole
    }
}

public struct AccessibilityWindowInclusionMapping: Equatable {
    public let originalIndex: Int
    public let windowIdentifier: Int

    public init(originalIndex: Int, windowIdentifier: Int) {
        self.originalIndex = originalIndex
        self.windowIdentifier = windowIdentifier
    }
}

public enum AccessibilityWindowInclusionPolicy {
    public static func shouldInclude(role: String?, subrole: String?) -> Bool {
        role == (kAXWindowRole as String)
            && subrole == (kAXStandardWindowSubrole as String)
    }

    public static func acceptedWindowMappings(
        ownerProcessIdentifier: Int,
        candidates: [AccessibilityWindowInclusionCandidate]
    ) -> [AccessibilityWindowInclusionMapping] {
        var mappings: [AccessibilityWindowInclusionMapping] = []
        mappings.reserveCapacity(candidates.count)

        for candidate in candidates where shouldInclude(role: candidate.role, subrole: candidate.subrole) {
            mappings.append(AccessibilityWindowInclusionMapping(
                originalIndex: candidate.originalIndex,
                windowIdentifier: ownerProcessIdentifier * 10_000 + mappings.count
            ))
        }

        return mappings
    }
}
```

- [x] **Step 4: Apply policy in AX snapshot collection**

Inside `AXWindowSnapshotProvider.windows(...)`, read role/subrole into candidates, then iterate `AccessibilityWindowInclusionPolicy.acceptedWindowMappings(...)`. This keeps snapshot creation and `activeWindowElements` registry insertion tied to the same accepted-window mapping.

```swift
let candidates = windowElements.indices.map { index in
    AccessibilityWindowInclusionCandidate(
        originalIndex: index,
        role: stringAttribute(windowElements[index], kAXRoleAttribute as CFString),
        subrole: stringAttribute(windowElements[index], kAXSubroleAttribute as CFString)
    )
}

let mappings = AccessibilityWindowInclusionPolicy.acceptedWindowMappings(
    ownerProcessIdentifier: ownerProcessIdentifier,
    candidates: candidates
)
```

Keep:

```swift
activeWindowElements[windowIdentifier] = windowElement
```

inside the mapping loop, using `windowElements[mapping.originalIndex]` and `mapping.windowIdentifier`.

- [x] **Step 5: Run tests and verify GREEN**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: all tests pass.

---

### Task 6: Final Build and Manual Verification

**Files:**
- No new source changes unless verification finds a bug.

- [x] **Step 1: Run full test runner**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: exit code `0`, output includes `All tests passed`.

- [x] **Step 2: Build Debug app**

Run:

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build
```

Expected: exit code `0`, output ends with `** BUILD SUCCEEDED **`.

- [x] **Step 3: Relaunch app**

Run:

```bash
rtk pkill -x SwitchTab
rtk open /Users/kendrick/Library/Developer/Xcode/DerivedData/WindowSwitcher-frebkfflvyhvsigdhdrulkxzudqc/Build/Products/Debug/SwitchTab.app
```

Expected: app starts from menu bar. If macOS asks for Accessibility or Screen Recording again, grant the exact DerivedData app.

- [ ] **Step 4: Manual UI checks**

Run these checks manually:

1. With one Codex/Chrome/Safari window active, press `Cmd+\``.
2. Confirm panel width hugs one tile instead of using a long empty 320px+ panel.
3. Confirm title row appears above thumbnail as `app icon + title`.
4. Open Settings > General > Overlay size.
5. Switch `Compact`, `Default`, `Large`, then press `Cmd+\`` after each change.
6. Confirm Default visually matches current baseline except for the single-item width fix and title position.
7. In Chrome, press `Cmd+F`.
8. Press `Cmd+\``.
9. Confirm `Find in page...` is not listed.

- [ ] **Step 5: Inspect live AX if Chrome still leaks panels**

Run:

```bash
rtk swift - <<'SWIFT'
import AppKit
import ApplicationServices

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value as? String
}

guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
    print("Chrome not running")
    exit(0)
}

let appElement = AXUIElementCreateApplication(chrome.processIdentifier)
var value: CFTypeRef?
let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
print("result=\(result.rawValue)")
for (index, window) in ((value as? [AXUIElement]) ?? []).enumerated() {
    print("#\(index) role=\(stringAttribute(window, kAXRoleAttribute as CFString) ?? "nil") subrole=\(stringAttribute(window, kAXSubroleAttribute as CFString) ?? "nil") title=\(stringAttribute(window, kAXTitleAttribute as CFString) ?? "nil")")
}
SWIFT
```

Expected: leaked panels have non-`AXStandardWindow` subroles. If a leaked panel is `AXStandardWindow`, add a second policy test using that exact role/subrole/title evidence before changing production code.

---

## Self-Review

- Spec coverage: covers compact width, size setting, title header, and Chrome Find/undefined window filtering.
- Placeholder scan: no deferred-work markers or fill-later steps.
- Type consistency: `OverlaySizePreference`, `SwitcherOverlayLayoutMetrics`, and `AccessibilityWindowInclusionPolicy` names are consistent across tasks.
- Scope control: no unrelated refactor; settings UI remains in existing `ShortcutSettingsView`; overlay remains existing grid architecture.

## Execution Notes

This workspace currently has no `.git` directory, so skip commit steps. If a git repository is initialized later, commit after each task with focused staged files.

## ENG REVIEW UPDATES

### Step 0: Scope Challenge

Scope accepted as-is. The plan touches more than 8 files and introduces more than 2 new types, but the scope is coherent: settings persistence, overlay layout, title/header rendering, and AX filtering all serve the same user-visible workflow.

### What Already Exists

- `SwitcherOverlayLayoutPolicy` already owns panel sizing and grid column selection. The plan reuses it instead of adding a parallel layout system.
- `SwitcherIconStripView` already renders list items and thumbnails. The plan updates the existing tile structure instead of creating a second overlay component.
- `ApplicationIconStore` already caches app icons by process identifier. The title header should reuse it rather than loading icons independently.
- `ApplicationSettingsStore` already persists app-level settings and posts `.applicationSettingsDidChange`. The overlay size setting should reuse that notification path.
- `AXWindowSnapshotProvider` already centralizes live AX window collection and registry replacement. The Chrome Find filter belongs there.

### NOT in Scope

- Replacing AX window identifiers with `CGWindowID` as the primary stable identifier. Useful later for recency stability, but not required to remove Chrome Find panels or focus accepted windows.
- Adding a SwiftUI inspection framework. Current test stack uses pure service/model tests plus manual UI verification.
- Reworking overlay visual design beyond the requested size, title-header, and thumbnail layout changes.
- Supporting non-standard AX panels as switchable targets. This plan intentionally keeps only `AXStandardWindow` for the current-app window switcher.

### Review Findings Applied

1. Architecture: `LazyVGrid` row spacing must use `layoutMetrics.gridSpacing`, not `SwitcherOverlayLayoutPolicy.iconGridSpacing`.
2. Code Quality: move `OverlaySizePreference` to `WindowSwitcher/Models/OverlaySizePreference.swift`.
3. Code Quality: add the new model file to `WindowSwitcher.xcodeproj/project.pbxproj` so Xcode app builds include it.
4. Tests: add a pure accepted-window mapping test so AX filter wiring is covered without live macOS AX elements.
5. Tests: add multi-row Compact/Default/Large layout coverage so size scaling is not only tested for one item.

### Coverage Diagram

```text
CODE PATHS                                             USER FLOWS
[+] Overlay size setting                               [+] Settings > Overlay size
  |-- [STRONG TESTED] default + persistence              |-- [MANUAL] segmented picker visible
  |-- [STRONG TESTED] view model setter                  `-- [MANUAL] Compact/Default/Large affects next overlay
  `-- [STRONG TESTED] controller reads store on present

[+] Overlay layout metrics                              [+] Cmd+` one-window overlay
  |-- [STRONG TESTED] single item width hugs tile         |-- [STRONG TESTED] width no longer uses 320px minimum
  |-- [STRONG TESTED] multi-row size scaling              `-- [MANUAL] visual title/header placement
  `-- [STRONG TESTED] standard keeps existing grid widths

[+] Tile title/header rendering                         [+] Multi-window overlay
  |-- [TESTED] app icon store cache reused                |-- [MANUAL] title appears above thumbnail
  `-- [MANUAL] fallback SF Symbol remains visible         `-- [MANUAL] long titles truncate cleanly

[+] AX window filtering                                 [+] Chrome Cmd+F then Cmd+`
  |-- [STRONG TESTED] AXStandardWindow accepted           |-- [STRONG TESTED] AXUnknown Find panel dropped by policy
  |-- [STRONG TESTED] accepted mapping drives identifiers `-- [MANUAL] live Chrome Find panel absent
  `-- [MANUAL] live AX dump if a panel still leaks
```

### Failure Modes

- Invalid stored overlay size raw value: handled by defaulting to `.standard`; covered by default/persistence tests.
- Layout calculation and SwiftUI spacing drift apart: addressed by routing `layoutMetrics.gridSpacing` into `LazyVGrid`; covered by multi-row layout tests.
- Chrome Find panel enters snapshot but not policy test: addressed by accepted-window mapping test and production loop using the helper.
- Xcode app build misses new model file: addressed by adding `project.pbxproj` membership and final `xcodebuild` verification.
- Live Chrome exposes a leaked panel as `AXStandardWindow`: not fully knowable from unit tests; manual AX dump step remains as fallback evidence collection.

### Performance Review

No blocking performance issues found. App icon lookup uses `ApplicationIconStore` cache, overlay layout remains pure O(window count), and AX role/subrole reads add two attribute calls per candidate window, bounded by the current app's AX window list.

### Parallelization

Sequential implementation is preferred. Settings, layout, overlay rendering, and provider filtering all touch shared app model/test targets and the same final verification path. Parallel worktrees would increase merge conflicts more than they save time here.

### Implementation Tasks

- [x] **T1 (P2, human: ~20min / CC: ~5min)** - Overlay layout - Route rendered grid row spacing through `layoutMetrics.gridSpacing`.
  - Surfaced by: Architecture Review - calculated layout and rendered grid used different spacing sources.
  - Files: `WindowSwitcher/UI/Overlay/SwitcherIconStripView.swift`, `WindowSwitcher/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`, `WindowSwitcherTests/Services/SwitcherOverlayPresentationTests.swift`
  - Verify: `rtk test swift run WindowSwitcherTestRunner`

- [x] **T2 (P2, human: ~25min / CC: ~8min)** - Settings model - Move `OverlaySizePreference` into `WindowSwitcher/Models` and add Xcode project membership.
  - Surfaced by: Code Quality Review - shared UI/layout setting type should not live in a service file.
  - Files: `WindowSwitcher/Models/OverlaySizePreference.swift`, `WindowSwitcher.xcodeproj/project.pbxproj`, `WindowSwitcher/Services/ApplicationSettingsStore.swift`
  - Verify: `rtk test swift run WindowSwitcherTestRunner` and `rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build`

- [x] **T3 (P2, human: ~35min / CC: ~10min)** - AX filtering - Add accepted-window mapping helper and tests.
  - Surfaced by: Test Review - policy-only tests would not catch snapshot/registry wiring mistakes.
  - Files: `WindowSwitcher/Services/AccessibilityWindowProvider.swift`, `WindowSwitcherTests/Services/AccessibilityWindowProviderTests.swift`
  - Verify: `rtk test swift run WindowSwitcherTestRunner`

- [x] **T4 (P2, human: ~20min / CC: ~5min)** - Layout tests - Add multi-row Compact/Default/Large coverage.
  - Surfaced by: Test Review - single-item size test does not cover multi-row layout path.
  - Files: `WindowSwitcherTests/Services/SwitcherOverlayPresentationTests.swift`
  - Verify: `rtk test swift run WindowSwitcherTestRunner`

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | - | Not run |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | - | Not run |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 2 | CLEAR | 5 issues, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | - | Not run |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | - | Not run |

- **UNRESOLVED:** 0
- **VERDICT:** ENG CLEARED - ready to implement.
