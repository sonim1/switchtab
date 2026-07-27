# Switcher Selection Visual Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the switcher panel's visible selection follow every accepted keyboard navigation command and ship the fix as `v1.0.6`.

**Architecture:** Keep `SwitcherOverlayState` as the command/session source of truth. Add one stable, main-actor `ObservableObject` presentation model that publishes state to SwiftUI; the controller updates it after state changes, while root-view replacement remains limited to presentation/layout setup.

**Tech Stack:** Swift 6, SwiftUI, Combine, AppKit, XCTest, GitHub Actions, Sparkle

---

## File Structure

- Create `SwitchTab/UI/Overlay/SwitcherOverlayPresentationModel.swift`: observable bridge from controller state to SwiftUI.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`: own and synchronize the stable presentation model.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`: observe the presentation model instead of storing a value snapshot.
- Modify `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`: strengthen the selected tile's fill and border.
- Create `SwitchTabTests/Services/SwitcherOverlayPresentationModelTests.swift`: verify selection updates are published.
- Modify `SwitchTabTests/TestRunner.swift`: register the new regression suite.

### Task 1: Add the failing presentation-state regression test

**Files:**
- Create: `SwitchTabTests/Services/SwitcherOverlayPresentationModelTests.swift`
- Modify: `SwitchTabTests/TestRunner.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Combine
import SwitchTab

enum SwitcherOverlayPresentationModelTests {
    @MainActor
    static func run() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)
            ]
        )
        let model = SwitcherOverlayPresentationModel(state: state)
        var observedIndices: [Int] = []
        let cancellable = model.$state.dropFirst().sink { publishedState in
            if let selectedIndex = publishedState.session?.selectedIndex {
                observedIndices.append(selectedIndex)
            }
        }

        _ = state.handle(.moveDown)
        model.update(state)

        withExtendedLifetime(cancellable) {}
        try expectEqual(model.state.session?.selectedIndex, 1)
        try expectEqual(observedIndices, [1])
    }
}
```

Add `try SwitcherOverlayPresentationModelTests.run()` immediately after `SwitcherOverlayStateTests.run()` in `SwitchTabTests/TestRunner.swift`.

- [ ] **Step 2: Run the test suite to verify it fails**

Run: `rtk swift test`

Expected: compilation fails because `SwitcherOverlayPresentationModel` does not exist.

- [ ] **Step 3: Commit the red test**

```bash
rtk git add SwitchTabTests/Services/SwitcherOverlayPresentationModelTests.swift SwitchTabTests/TestRunner.swift
rtk git commit -m "test: cover switcher selection presentation updates"
```

### Task 2: Publish state through a stable presentation model

**Files:**
- Create: `SwitchTab/UI/Overlay/SwitcherOverlayPresentationModel.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`

- [ ] **Step 1: Add the minimal observable model**

```swift
import Combine

@MainActor
public final class SwitcherOverlayPresentationModel: ObservableObject {
    @Published public private(set) var state: SwitcherOverlayState

    public init(state: SwitcherOverlayState = SwitcherOverlayState()) {
        self.state = state
    }

    public func update(_ state: SwitcherOverlayState) {
        self.state = state
    }
}
```

- [ ] **Step 2: Make the root view observe the model**

Replace its stored `SwitcherOverlayState` with:

```swift
@ObservedObject private var presentationModel: SwitcherOverlayPresentationModel
```

Update the initializer to accept `presentationModel`, assign it, and read the active session through `presentationModel.state.session`.

- [ ] **Step 3: Synchronize the model from the controller**

Add:

```swift
private let presentationModel = SwitcherOverlayPresentationModel()
```

For `.updated`, call `presentationModel.update(state)` instead of rebuilding the root view. At the start of `render()`, call `presentationModel.update(state)`, then construct `SwitcherOverlayRootView(presentationModel: presentationModel, ...)`. At the start of `endPresentation()`, update the model once more so dismiss/confirm state is also synchronized.

- [ ] **Step 4: Run the focused regression suite**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: PASS, including `observedIndices == [1]`.

- [ ] **Step 5: Commit the behavior fix**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayPresentationModel.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift
rtk git commit -m "fix: keep switcher selection presentation in sync"
```

### Task 3: Strengthen and verify the selected-item treatment

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`

- [ ] **Step 1: Update the selected tile styling**

Keep the rounded shape and change the selection decoration to:

```swift
.background(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
.clipShape(RoundedRectangle(cornerRadius: 7))
.overlay {
    RoundedRectangle(cornerRadius: 7)
        .stroke(
            isSelected ? Color.accentColor.opacity(0.95) : Color.clear,
            lineWidth: 2
        )
}
```

- [ ] **Step 2: Run formatting and build checks**

Run: `rtk git diff --check`

Expected: no output.

Run: `rtk swift test`

Expected: all tests pass.

- [ ] **Step 3: Commit the visual adjustment**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherIconStripView.swift
rtk git commit -m "fix: clarify switcher selected item"
```

### Task 4: Verify, publish, and release

**Files:**
- Verify all branch changes; no additional production files expected.

- [ ] **Step 1: Run full local verification**

Run: `rtk swift test`

Expected: all Swift tests pass.

Run the repository's unsigned macOS build command from its release documentation.

Expected: build succeeds without signing or notarization.

- [ ] **Step 2: Review branch scope**

Run: `rtk git status --short --branch`

Expected: clean branch, ahead of `origin/main` only by this design, tests, and fix.

Run: `rtk git diff origin/main...HEAD --check`

Expected: no output.

- [ ] **Step 3: Push and open a normal patch PR**

Push `codex/fix-selection-visual-sync`, open a PR describing the stale selection symptom and verification, and do not add a major/minor release label.

Expected: automatic versioning proposes `1.0.6`; all PR checks pass.

- [ ] **Step 4: Merge and monitor the release pipeline**

Merge the passing PR into `main`. Monitor the automatic tag/release jobs until `v1.0.6` is published.

Expected: notarized GitHub Release assets, R2 Sparkle appcast/artifacts, and the Homebrew cask update all complete successfully.

- [ ] **Step 5: Verify public release metadata**

Verify the GitHub release tag is `v1.0.6`, the appcast points at build `7`, and Homebrew reports version `1.0.6` after its update PR lands.
