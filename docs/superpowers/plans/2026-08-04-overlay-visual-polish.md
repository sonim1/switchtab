# Overlay Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten switcher geometry, center edge captions under their application icons, and use native Liquid Glass on macOS 26 with a native macOS 14–15 fallback.

**Architecture:** Keep all geometry in `SwitcherOverlayLayoutPolicy` and expose directional panel insets so size calculation and SwiftUI rendering consume the same values. Keep OS-specific glass creation inside one `NSViewRepresentable`; session, input, and activation layers remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, `NSGlassEffectView`, `NSVisualEffectView`, Swift Package Manager, XCTest, Xcode 26.

---

## File Map

- Modify `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`: directional panel inset metrics, compact tile sizes, caption width policy, and panel size calculations.
- Modify `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`: horizontal-only window-tile padding and centered application captions.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`: directional root padding and availability-gated native glass background.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`: remove the chrome-policy flag orphaned by the unconditional native material background.
- Modify `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`: regression coverage for geometry, caption centering, and glass integration.

### Task 1: Directional Panel Insets and Compact Tiles

**Files:**
- Modify: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`

- [ ] **Step 1: Replace padding expectations with failing directional-inset tests**

Update the `run()` registration to call `testDirectionalPanelInsetsMatchApprovedLayout()` and replace the old panel-padding tests with:

```swift
static func testDirectionalPanelInsetsMatchApprovedLayout() throws {
    let windowMetrics = SwitcherOverlayLayoutMetrics.metrics(
        for: .default,
        mode: .currentAppWindowSwitching
    )
    let applicationMetrics = SwitcherOverlayLayoutMetrics.metrics(
        for: .default,
        mode: .applicationSwitching
    )

    try expectEqual(windowMetrics.panelHorizontalPadding, 10)
    try expectEqual(windowMetrics.panelTopPadding, 8)
    try expectEqual(windowMetrics.panelBottomPadding, 8)
    try expectEqual(applicationMetrics.panelHorizontalPadding, 10)
    try expectEqual(applicationMetrics.panelTopPadding, 8)
    try expectEqual(applicationMetrics.panelBottomPadding, 0)
}
```

Change the compact-layout assertions to:

```swift
try expectEqual(windowMetrics.tileSize, CGSize(width: 168, height: 134))
try expectEqual(applicationMetrics.tileSize, CGSize(width: 100, height: 115))
try expectEqual(applicationMetrics.selectionContainerSize, CGSize(width: 100, height: 100))
```

Change `expectedWidth` and `expectedHeight` to derive panel totals from directional metrics:

```swift
return CGFloat(columnCount) * metrics.tileSize.width
    + CGFloat(columnCount - 1) * metrics.gridSpacing
    + metrics.panelHorizontalPadding * 2
```

```swift
return CGFloat(rowCount) * metrics.tileSize.height
    + CGFloat(rowCount - 1) * metrics.gridSpacing
    + metrics.panelTopPadding
    + metrics.panelBottomPadding
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: compilation fails because the three directional padding properties do not exist, proving the test requires the new layout contract.

- [ ] **Step 3: Add directional metrics and exact tile sizes**

In `SwitcherOverlayLayoutMetrics`, replace `gridPadding` and `panelPadding` with:

```swift
public let panelHorizontalPadding: CGFloat
public let panelTopPadding: CGFloat
public let panelBottomPadding: CGFloat
```

Use these default-scale constants:

```swift
private static let baseWindowPanelHorizontalPadding: CGFloat = 10
private static let baseWindowPanelTopPadding: CGFloat = 8
private static let baseWindowPanelBottomPadding: CGFloat = 8
private static let baseApplicationPanelHorizontalPadding: CGFloat = 10
private static let baseApplicationPanelTopPadding: CGFloat = 8
private static let baseApplicationPanelBottomPadding: CGFloat = 0
private static let baseApplicationSelectionExtent: CGFloat = 100
```

Delete `baseWindowTileVerticalChrome`, `baseWindowGridPadding`, `baseWindowPanelPadding`, and `baseApplicationGridPadding`. Compute the window tile height without vertical padding:

```swift
let tileSize = CGSize(
    width: thumbnailWidth + (tileContentPadding * 2),
    height: thumbnailHeight + headerIconExtent + baseWindowTileContentSpacing
)
```

Populate the directional fields in each metrics initializer with `scaled(_:by:)`; preserve an exact zero application bottom inset by assigning `0` directly.

Update layout calculations:

```swift
let contentWidth = max(1, width - metrics.panelHorizontalPadding * 2)
```

```swift
CGFloat(columnCount) * metrics.tileSize.width
    + CGFloat(max(columnCount - 1, 0)) * metrics.gridSpacing
    + metrics.panelHorizontalPadding * 2
```

```swift
CGFloat(rowCount) * metrics.tileSize.height
    + CGFloat(max(rowCount - 1, 0)) * metrics.gridSpacing
    + metrics.panelTopPadding
    + metrics.panelBottomPadding
```

Subtract `panelTopPadding + panelBottomPadding` in `maximumRowsThatFit`. Use `captionMaxWidth + panelHorizontalPadding * 2` for the single-item caption-safe width.

- [ ] **Step 4: Render the same directional geometry**

In `SwitcherIconStripView.windowContent`, replace all-edge padding with:

```swift
.padding(.horizontal, layoutMetrics.tileContentPadding)
```

In `SwitcherOverlayRootView`, replace the scalar root padding with:

```swift
.padding(.horizontal, layoutMetrics.panelHorizontalPadding)
.padding(.top, layoutMetrics.panelTopPadding)
.padding(.bottom, layoutMetrics.panelBottomPadding)
```

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: all tests pass with no failures.

- [ ] **Step 6: Commit the geometry change**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
rtk git commit -m "fix: tighten switcher overlay spacing"
```

### Task 2: Center Edge Captions Without Panel Growth

**Files:**
- Modify: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`

- [ ] **Step 1: Write failing edge-caption tests**

Replace `testApplicationCaptionAlignsTowardGridInterior()` in `run()` with `testApplicationCaptionsStayCenteredWithinPanelBounds()` and implement:

```swift
static func testApplicationCaptionsStayCenteredWithinPanelBounds() throws {
    let metrics = SwitcherOverlayLayoutMetrics.metrics(
        for: .default,
        mode: .applicationSwitching
    )

    try expectEqual(
        ApplicationSwitcherCaptionLayoutPolicy.width(
            index: 0,
            columnCount: 3,
            metrics: metrics
        ),
        120
    )
    try expectEqual(
        ApplicationSwitcherCaptionLayoutPolicy.width(
            index: 1,
            columnCount: 3,
            metrics: metrics
        ),
        240
    )
    try expectEqual(
        ApplicationSwitcherCaptionLayoutPolicy.width(
            index: 2,
            columnCount: 3,
            metrics: metrics
        ),
        120
    )
}
```

Update existing width calls to pass `index`, and retain the one-column expectation of 240 pt.

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: compilation fails because `width(index:columnCount:metrics:)` does not exist.

- [ ] **Step 3: Implement centered edge-safe widths**

Replace the caption width policy with:

```swift
public static func width(
    index: Int,
    columnCount: Int,
    metrics: SwitcherOverlayLayoutMetrics
) -> CGFloat {
    guard columnCount > 1 else {
        return metrics.captionMaxWidth
    }

    let columnIndex = index % columnCount
    let isEdgeColumn = columnIndex == 0 || columnIndex == columnCount - 1
    guard isEdgeColumn else {
        return metrics.captionMaxWidth
    }

    let centeredEdgeWidth = metrics.tileSize.width
        + metrics.panelHorizontalPadding * 2
    return min(metrics.captionMaxWidth, centeredEdgeWidth)
}
```

Delete `ApplicationSwitcherCaptionAlignment` and `alignment(index:columnCount:)`.

In `SwitcherIconStripView`, pass `index` into `width`, use `.overlay(alignment: .center)`, and delete `captionAlignment` plus `swiftUIAlignment(for:)`.

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: all tests pass with no failures.

- [ ] **Step 5: Commit the caption fix**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
rtk git commit -m "fix: center application switcher captions"
```

### Task 3: Native Liquid Glass With Older-macOS Fallback

**Files:**
- Modify: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`

- [ ] **Step 1: Write a failing integration-source test**

Replace `testOverlayChromeUsesNativeBlurBackground()` in `run()` with `testOverlayChromeUsesLiquidGlassWithPopoverFallback()`:

```swift
static func testOverlayChromeUsesLiquidGlassWithPopoverFallback() throws {
    let sourceURL = projectRoot
        .appendingPathComponent("SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    try expectTrue(source.contains("#available(macOS 26.0, *)"))
    try expectTrue(source.contains("NSGlassEffectView()"))
    try expectTrue(source.contains("view.material = .popover"))
    try expectTrue(source.contains("view.blendingMode = .behindWindow"))
    try expectFalse(source.contains("view.material = .hudWindow"))
}
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: the source assertions fail because the view still uses `.hudWindow` and has no `NSGlassEffectView` branch.

- [ ] **Step 3: Implement the availability-gated background**

Replace the conditional root background with:

```swift
.background {
    SwitcherOverlayGlassBackground()
}
```

Replace `SwitcherOverlayBlurBackground` with:

```swift
private struct SwitcherOverlayGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.cornerRadius = 12
            return view
        } else {
            let view = NSVisualEffectView()
            view.material = .popover
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }
    }

    func updateNSView(_ view: NSView, context: Context) {
    }
}
```

Delete `SwitcherOverlayChromePolicy` from `SwitcherOverlayState.swift`; the background is now always native on every supported OS.

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: all tests pass with no failures.

- [ ] **Step 5: Build the full app**

Run:

```bash
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` with no compile errors from the macOS 26 availability branch.

- [ ] **Step 6: Commit the native glass change**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTab/UI/Overlay/SwitcherOverlayState.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
rtk git commit -m "fix: adopt native switcher glass"
```

### Task 4: Final Verification and Release Handoff

**Files:**
- Verify: all changed source, tests, design, and plan files

- [ ] **Step 1: Run fresh automated verification**

```bash
rtk swift build
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check origin/main...HEAD
```

Expected: all four commands exit 0; tests report zero failures; Xcode reports `** BUILD SUCCEEDED **`; diff check prints no errors.

- [ ] **Step 2: Run native UI verification**

Launch the Debug app produced by Xcode, then verify:

1. Window mode shows no vertical tile inset and has equal 8 pt top/bottom panel insets.
2. Application mode shows a 2 pt icon-selection inset and no space below the caption row.
3. First, middle, and last selected captions remain centered under their icons.
4. The panel samples the desktop/window behind it with native glass in both light and dark appearance where practical.
5. Forward/reverse traversal, release confirmation, click confirmation, and Escape cancellation still work.

Expected: all five checks pass; record any permission-dependent check that cannot run instead of claiming it.

- [ ] **Step 3: Run the ship workflow**

Invoke the `ship` skill. Follow its review, version, changelog, push, PR, and release steps without bypassing failures. Default to the repository's patch-release policy unless labels or runbooks require otherwise.
