# Application Switcher Interaction Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Cmd-Tab release and navigation reliable, add native-style Command-Q application termination, stabilize the compact layout, and display live application window counts.

**Architecture:** Keep `SwitcherOverlayState` as the shared interaction state machine. Extend the overlay Event Tap to deliver modifier release reliably, use the existing Accessibility window boundary to summarize and close application windows, and make scrollability and panel inset explicit layout outputs instead of implicit SwiftUI behavior.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, ApplicationServices Accessibility, CoreGraphics Event Tap, XCTest

---

### Task 1: Capture trigger release in the overlay Event Tap

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayPresentationPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationPolicyTests.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayConfirmationTests.swift`

- [ ] **Step 1: Write failing policy tests**

Add tests that require the Event Tap mask to contain both `.keyDown` and
`.flagsChanged`, require a flags-changed event with Command released to return
`handleAndPassThrough(.releaseShortcut)`, and require releasing Shift while
Command remains held to do nothing.

- [ ] **Step 2: Verify the focused tests fail**

Run: `swift test --filter SwitchTabTests/testAllSuites`

Expected: FAIL because the Event Tap exposes no flags-changed mask or
pass-through release decision.

- [ ] **Step 3: Implement the minimal Event Tap policy**

Add an explicit Event Tap mask and a `handleAndPassThrough(SwitcherCommand)`
decision. Pass `triggerReleaseModifiers` into `SwitcherOverlayEventTapOwner` and
evaluate flags-changed input with `SwitcherOverlayExternalEventPolicy` so the
command is handled while the modifier event still reaches macOS. Keep the
existing local/global monitors as fallback.

- [ ] **Step 4: Verify release tests and the full suite pass**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add SwitchTab/UI/Overlay/SwitcherOverlayPresentationPolicy.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTabTests/Services/SwitcherOverlayPresentationPolicyTests.swift SwitchTabTests/Services/SwitcherOverlayConfirmationTests.swift
git commit -m "fix: confirm switcher selection on modifier release"
```

### Task 2: Expose application window summaries through Accessibility

**Files:**
- Modify: `SwitchTab/Services/AccessibilityWindowProvider.swift`
- Modify: `SwitchTab/Models/ApplicationItem.swift`
- Test: `SwitchTabTests/Services/AccessibilityWindowProviderTests.swift`
- Test: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **Step 1: Write failing application-window tests**

Add tests requiring `AccessibilityWindowProvider.applicationWindows` to return
standard available and minimized windows for an arbitrary application PID, and
requiring an `ApplicationItem` copy with a known count to place that count in
the switcher list item without changing identity or activation metadata.

- [ ] **Step 2: Verify the tests fail for the missing APIs**

Run: `swift test --filter SwitchTabTests/testAllSuites`

Expected: compilation failure for the missing application-window and counted
item APIs.

- [ ] **Step 3: Add the minimal summary APIs**

Make the existing PID-scoped Accessibility window lookup public as
`applicationWindows(ownerProcessIdentifier:ownerName:)`, always disabling
screen-capture identifier work for application summaries. Add a focused
`ApplicationItem.withWindowCount(_:)` copy operation that sets a numeric
subtitle and preserves every other field.

- [ ] **Step 4: Verify the focused behavior and full suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add SwitchTab/Services/AccessibilityWindowProvider.swift SwitchTab/Models/ApplicationItem.swift SwitchTabTests/Services/AccessibilityWindowProviderTests.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift
git commit -m "feat: summarize application window counts"
```

### Task 3: Add native Command-Q application termination

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Modify: `SwitchTab/AppDelegate.swift`
- Modify: `SwitchTab/Services/ApplicationActivationService.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayStateTests.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayConfirmationTests.swift`
- Test: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **Step 1: Write failing native-quit tests**

Add tests requiring Command-Q to map to an application quit command only while
Command is held. Application mode returns a quit request without dismissing;
window mode ignores it. Command-W remains accepted only by window mode, and the
application tile keeps no visible close control. Add removal tests that preserve
a valid neighbouring selection and cancel only when no applications remain.
Add termination-service tests for accepted and rejected requests without
optimistically removing an application.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter SwitchTabTests/testAllSuites`

Expected: FAIL because no application quit command, interaction result, or
termination service exists.

- [ ] **Step 3: Implement native application quit semantics**

Add a Command-Q switcher command and application-only quit-request result.
Retain Command-W and the visible close control only for window mode. Add a
minimal `ApplicationTerminationService` around `NSRunningApplication.terminate`
that reports whether the request was accepted but never treats acceptance as
confirmed termination.

In `AppDelegate.showApplicationSwitcher`, populate counts before presenting.
Provide `onQuit` that requests normal termination for the selected application
and leaves the overlay unchanged. Observe `NSWorkspace` application-termination
notifications once at the app-delegate boundary; when an application actually
terminates, remove its matching tile from a currently presented application
session. External termination uses the same removal path.

- [ ] **Step 4: Verify quit behavior and the full suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add SwitchTab/AppDelegate.swift SwitchTab/Services/ApplicationActivationService.swift SwitchTab/UI/Overlay/SwitcherOverlayState.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTabTests/Services/SwitcherOverlayStateTests.swift SwitchTabTests/Services/SwitcherOverlayConfirmationTests.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift
git commit -m "feat: quit selected applications from switcher"
```

### Task 4: Prevent selection scrolling when every row is visible

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Write failing overflow tests**

Add layout assertions that one-to-three visible rows return
`requiresSelectionScrolling == false` and a fourth row returns `true`. Add a
source contract assertion that `scrollToSelected` is guarded by this value.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter SwitchTabTests/testAllSuites`

Expected: compilation failure because presentation layout has no overflow flag.

- [ ] **Step 3: Implement explicit scrollability**

Add `requiresSelectionScrolling` to `SwitcherOverlayPresentationLayout`, derive
it from total rows versus visible rows, pass it through controller and root view,
and return early from `scrollToSelected` when all rows fit.

- [ ] **Step 4: Verify stable-layout tests and the full suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
git commit -m "fix: keep fully visible switcher grids stationary"
```

### Task 5: Align panel inset and render the compact count label

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **Step 1: Write failing inset and presentation tests**

For minimum, default, and maximum scales in both modes, assert that total grid
padding is at least twice the rendered panel inset. Add a source contract test
requiring application title content to render the optional numeric subtitle
beside a window glyph while the window header remains unchanged.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter SwitchTabTests/testAllSuites`

Expected: FAIL because application grid padding and fixed root padding disagree
and application subtitles are not rendered.

- [ ] **Step 3: Implement mode-specific panel inset and count label**

Carry `panelPadding` in `SwitcherOverlayLayoutMetrics`, scale it with application
metrics, and use it in the root view. Keep the existing default window inset.
Render an optional secondary `rectangle.on.rectangle` glyph and numeric subtitle
in the application name row without adding a second vertical line.

- [ ] **Step 4: Verify presentation tests and full suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
git commit -m "fix: preserve compact switcher selection bounds"
```

### Task 6: Verify live behavior and prepare release

**Files:**
- Modify: `specs/001-macos-switchtab/quickstart.md`
- Modify: `specs/001-macos-switchtab/contracts/switcher-behavior.md`

- [ ] **Step 1: Update the manual acceptance contract**

Record Cmd-Tab modifier release, forward/reverse navigation, Command-Q quit,
window-count refresh, stationary fully visible grids, full outline visibility,
and unchanged Option-Tilde thumbnail behavior.

- [ ] **Step 2: Run automated verification**

Run: `swift test`

Expected: all tests pass with zero failures.

Run: `xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run live macOS verification**

Build and launch the Debug app, enable Cmd-Tab replacement, and verify with at
least Finder, Safari, and Notes: release activates the highlighted app; Tab and
arrow navigation remain stationary; Command-Q requests normal app termination
and removes the tile only after confirmed termination; Command-W remains a
window-mode action; all outline edges remain visible; Option-Tilde still shows
and operates window thumbnails.

- [ ] **Step 4: Commit acceptance documentation**

```bash
git add specs/001-macos-switchtab/quickstart.md specs/001-macos-switchtab/contracts/switcher-behavior.md
git commit -m "docs: add application switcher parity acceptance"
```

- [ ] **Step 5: Execute the release workflow**

Run the repository `/ship` workflow from the feature branch. It must perform a
fresh review, version bump, changelog update, push, PR creation and merge, tag,
signed/notarized release build, appcast publication, and post-release update
feed verification.
