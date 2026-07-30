# Compact Application Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render application switching as compact app icons with names below while preserving the existing window-thumbnail presentation.

**Architecture:** Select layout metrics by `SwitcherMode` in the pure layout policy. Pass the active mode into the SwiftUI tile so application and window content use separate visual arrangements without changing selection or interaction behavior.

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, XCTest-compatible custom test runner

---

### Task 1: Specify mode-specific layout behavior

**Files:**
- Modify: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Add failing layout tests**

Add tests that call `SwitcherOverlayLayoutMetrics.metrics(for:mode:)` for both
modes and assert default application geometry is `120x128`, icon size is
`96x96`, grid spacing is `8`, and grid padding is `16`. Assert existing window
metrics remain `168x158`, spacing `14`, and padding `28`.

- [ ] **Step 2: Add a failing density test**

For 16 items on a 1440-point-wide screen, compare
`presentationLayout(itemCount:screenSize:mode:)` and assert application mode
fits more columns than window mode.

- [ ] **Step 3: Add a failing view-structure contract**

Read `SwitcherIconStripView.swift` and assert it contains an
`applicationContent(for:)` path with the application title after `icon(for:)`,
while retaining `titleHeader(for:)` for the window path.

- [ ] **Step 4: Run the suite and confirm failure**

Run: `rtk swift test`

Expected: FAIL because the mode-aware metric APIs and application content path
do not exist.

### Task 2: Implement compact application metrics

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`

- [ ] **Step 1: Add mode-aware metrics**

Keep current constants in a window-metrics helper. Add an application-metrics
helper whose scale-1 values are a `120x128` tile, `108x96` visual frame,
`96x96` icon, 12-point title, 8-point grid spacing, and 16-point grid padding.
Scale every value with the existing `OverlaySizeScale`.

- [ ] **Step 2: Make presentation layout mode-aware**

Add a `mode` argument, defaulting to `.currentAppWindowSwitching`, to
`presentationLayout`. Select metrics with `metrics(for:scale, mode:mode)` so
existing window callers and tests retain their geometry.

- [ ] **Step 3: Pass the active mode from the controller**

In `currentPresentationLayout(session:screenSize:)`, pass `session.mode` to
the layout policy. Initialize cached metrics explicitly for window mode.

### Task 3: Implement the application tile content

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Modify: `SwitchTabTests/Services/WindowCloseServiceTests.swift`

- [ ] **Step 1: Pass `SwitcherMode` through the view hierarchy**

Replace the `showsThumbnails` initializer input with `mode`. Derive thumbnail
behavior from `SwitcherOverlayThumbnailPolicy.showsThumbnails(for: mode)`.

- [ ] **Step 2: Split window and application content**

Keep the existing window `VStack` with `titleHeader(for:)` and thumbnail. Add
an application `VStack` with `icon(for:)` first and a centered, one-line,
tail-truncated application title below it. Use the existing title font metric.

- [ ] **Step 3: Preserve interactions**

Leave the button, selection border, hover handling, close policy, callbacks,
and accessibility label/hint unchanged.

- [ ] **Step 4: Run the full suite**

Run: `rtk swift test`

Expected: PASS with zero failures.

### Task 4: Verify the macOS target and patch

**Files:**
- Verify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Verify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Verify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Verify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Verify: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Build the unsigned app target**

Run: `rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Check formatting and scope**

Run: `rtk git diff --check`

Expected: no output and exit status 0. Confirm only the planned UI, policy,
test, spec, and plan files changed.

- [ ] **Step 3: Commit implementation**

Run:

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift SwitchTabTests/Services/WindowCloseServiceTests.swift docs/superpowers/plans/2026-07-29-compact-application-switcher.md
rtk git commit -m "feat: compact application switcher layout"
```
