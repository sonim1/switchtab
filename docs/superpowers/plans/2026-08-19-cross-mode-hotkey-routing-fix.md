# Cross-Mode Hotkey Routing Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route a global shortcut invocation into the existing held-session mode switch when the opposite switcher overlay is already active.

**Architecture:** Add a pure routing policy beside the existing AppDelegate shortcut policies. Both public shortcut entry points use its three decisions—present, advance, or switch mode—so the result does not depend on whether the global hotkey callback or overlay event tap receives the key first.

**Tech Stack:** Swift 6, XCTest, Swift Package Manager, AppKit

---

### Task 1: Add failing invocation-routing coverage

**Files:**
- Create: `SwitchTabTests/Services/SwitcherInvocationRoutingPolicyTests.swift`
- Test: `SwitchTabTests/Services/SwitcherInvocationRoutingPolicyTests.swift`

- [ ] **Step 1: Write the failing routing-policy tests**

```swift
@testable import SwitchTab
import XCTest

final class SwitcherInvocationRoutingPolicyTests: XCTestCase {
    func testRoutesOppositeActiveModeToHeldSessionSwitch() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .applicationSwitching,
                requestedMode: .currentAppWindowSwitching
            ),
            .switchMode
        )
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .currentAppWindowSwitching,
                requestedMode: .applicationSwitching
            ),
            .switchMode
        )
    }

    func testRoutesSameActiveModeToAdvance() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: .applicationSwitching,
                requestedMode: .applicationSwitching
            ),
            .advance
        )
    }

    func testRoutesMissingOverlayToFreshPresentation() {
        XCTAssertEqual(
            SwitcherInvocationRoutingPolicy.decision(
                activeMode: nil,
                requestedMode: .currentAppWindowSwitching
            ),
            .present
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk test swift test --filter SwitcherInvocationRoutingPolicyTests
```

Expected: compilation fails because `SwitcherInvocationRoutingPolicy` does not exist.

- [ ] **Step 3: Commit the regression test**

```bash
rtk git add SwitchTabTests/Services/SwitcherInvocationRoutingPolicyTests.swift
rtk git commit -m "test: reproduce cross-mode hotkey routing bug"
```

### Task 2: Route opposite-mode invocations through the live session

**Files:**
- Modify: `SwitchTab/AppDelegate.swift:1-30`
- Modify: `SwitchTab/AppDelegate.swift:300-350`
- Modify: `SwitchTab/AppDelegate.swift:720-735`
- Test: `SwitchTabTests/Services/SwitcherInvocationRoutingPolicyTests.swift`

- [ ] **Step 1: Add the minimal routing policy**

Add beside `AppDelegateShortcutConflictPolicy`:

```swift
enum SwitcherInvocationRoutingDecision: Equatable {
    case present
    case advance
    case switchMode
}

enum SwitcherInvocationRoutingPolicy {
    static func decision(
        activeMode: SwitcherMode?,
        requestedMode: SwitcherMode
    ) -> SwitcherInvocationRoutingDecision {
        guard let activeMode else {
            return .present
        }

        return activeMode == requestedMode ? .advance : .switchMode
    }
}
```

- [ ] **Step 2: Apply the decision in both public shortcut entry points**

At the start of `showCurrentAppSwitcher(reverse:)`, after unwrapping the overlay controller:

```swift
switch SwitcherInvocationRoutingPolicy.decision(
    activeMode: overlayController.activeMode,
    requestedMode: .currentAppWindowSwitching
) {
case .advance:
    _ = overlayController.handle(reverse ? .moveUp : .moveDown)
    return
case .switchMode:
    switchOverlayMode(reverse: reverse)
    return
case .present:
    break
}
```

Apply the same switch in `showApplicationSwitcher(reverse:)` with
`requestedMode: .applicationSwitching`. Remove the replaced
`advancePresentedOverlayIfNeeded` calls and delete that now-unused helper.

- [ ] **Step 3: Run the focused test and verify GREEN**

Run:

```bash
rtk test swift test --filter SwitcherInvocationRoutingPolicyTests
```

Expected: 3 tests pass with 0 failures.

- [ ] **Step 4: Run complete library verification**

Run:

```bash
rtk swift build
rtk swift test
```

Expected: both commands exit 0 with no failures.

- [ ] **Step 5: Run the complete unsigned app build**

Run:

```bash
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Check scope and commit the fix**

Run:

```bash
rtk git diff --check
rtk git status --short
```

Expected: only `SwitchTab/AppDelegate.swift`, the routing-policy test, and this plan are changed since the design commit.

Commit:

```bash
rtk git add SwitchTab/AppDelegate.swift docs/superpowers/plans/2026-08-19-cross-mode-hotkey-routing-fix.md
rtk git commit -m "fix: route cross-mode hotkeys through live session"
```

### Task 3: Manual runtime verification

**Files:**
- Verify only: built SwitchTab application

- [ ] **Step 1: Reproduce the original input sequence**

Run the Debug app with Accessibility permission, open at least two applications
with windows, hold Command, press Tab until a non-leftmost application is
highlighted, and press Backtick without releasing Command.

Expected: the overlay changes to window mode and lists only windows owned by the
highlighted application.

- [ ] **Step 2: Verify the reverse route and session semantics**

While still holding Command, press Tab again.

Expected: the overlay returns to application mode, resumes the application that
was left, advances one step, and releasing Command confirms the final selection.
