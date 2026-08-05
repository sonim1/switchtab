# Overlay Focus Inset Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give application captions bottom breathing room and add a small content inset inside window selection outlines.

**Architecture:** Keep the geometry contract in `SwitcherOverlayLayoutMetrics`. Add one directional tile metric for window vertical content padding, then make the layout calculation and SwiftUI rendering consume the same value.

**Tech Stack:** Swift 6, SwiftUI, CoreGraphics, XCTest, Xcode 26.

---

## File Map

- Modify `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`: rebalance application height and expose window vertical tile padding.
- Modify `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`: render the vertical window inset.
- Modify `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`: lock exact geometry and SwiftUI wiring.

### Task 1: Lock the New Geometry

**Files:**
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Write failing metric assertions**

Update the default metric expectations to require:

```swift
try expectEqual(windowMetrics.tileSize, CGSize(width: 168, height: 138))
try expectEqual(windowMetrics.tileVerticalContentPadding, 2)
try expectEqual(applicationMetrics.tileSize, CGSize(width: 98, height: 113))
try expectEqual(applicationMetrics.selectionContainerSize, CGSize(width: 98, height: 98))
try expectEqual(applicationMetrics.panelBottomPadding, 2)
```

In `testApplicationCaptionKeepsPanelHeightStable()`, assert:

```swift
try expectEqual(layout.size.height, 123)
```

In `testOverlayViewsApplyDirectionalPadding()`, require:

```swift
try expectTrue(
    tileSource.contains(".padding(.vertical, layoutMetrics.tileVerticalContentPadding)")
)
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: compilation fails because `tileVerticalContentPadding` does not exist, and the old application metrics do not satisfy the new contract.

### Task 2: Rebalance Application and Window Insets

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Implement the minimal metric change**

Add:

```swift
public let tileVerticalContentPadding: CGFloat
```

Use these default constants:

```swift
private static let baseWindowTileVerticalContentPadding: CGFloat = 2
private static let baseApplicationSelectionExtent: CGFloat = 98
private static let baseApplicationPanelBottomPadding: CGFloat = 2
```

For window mode, scale the vertical inset and include both edges in tile height:

```swift
let tileVerticalContentPadding = scaled(baseWindowTileVerticalContentPadding, by: factor)
let tileSize = CGSize(
    width: thumbnailWidth + (tileContentPadding * 2),
    height: thumbnailHeight
        + headerIconExtent
        + baseWindowTileContentSpacing
        + tileVerticalContentPadding * 2
)
```

Set application `tileVerticalContentPadding` to zero and window mode to the scaled value.

- [ ] **Step 2: Render the new window inset**

After the existing horizontal padding in `windowContent(for:)`, add:

```swift
.padding(.vertical, layoutMetrics.tileVerticalContentPadding)
```

- [ ] **Step 3: Run the focused suite and verify GREEN**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: the selected suite passes with zero failures.

- [ ] **Step 4: Commit the implementation and tests**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
rtk git commit -m "fix: rebalance switcher focus insets"
```

### Task 3: Full Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run fresh verification**

```bash
rtk swift build
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check origin/main...HEAD
```

Expected: every command exits zero, Swift reports zero failures, and Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 2: Inspect the built overlay where permissions allow**

Verify application mode retains its previous total height with visible caption-bottom space, and window mode shows a subtle equal inset above the title and below the thumbnail. Record permission-dependent limitations instead of claiming visual success.
