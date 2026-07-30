# Application Switching and Cmd-Tab Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in application switcher that replaces macOS Cmd-Tab while SwitchTab is running, preserves native Cmd-Tab when disabled, and ships through the existing signed Sparkle/Homebrew release pipeline.

**Architecture:** Add value snapshots for running applications, a filtered NSWorkspace provider, mode-scoped MRU history, and an application activation coordinator. Reuse the existing overlay, but register fixed Cmd-Tab combinations through a dedicated EventTap-only hotkey controller so configurable window shortcuts remain Carbon-first and independent.

**Tech Stack:** Swift 6, AppKit, SwiftUI, CoreGraphics CGEventTap, UserDefaults, XCTest, Xcode, Sparkle release automation, GitHub Actions.

**Design:** `docs/superpowers/specs/2026-07-29-application-switching-cmd-tab-design.md`

---

## File Map

- Create `SwitchTab/Models/ApplicationItem.swift`: stable application identity and overlay item mapping.
- Create `SwitchTab/Services/RunningApplicationProvider.swift`: NSWorkspace snapshot adapter and pure filtering/deduplication.
- Create `SwitchTab/Services/ApplicationActivationService.swift`: process activation, success-only selection MRU, and workspace-activation MRU adapter.
- Create `SwitchTab/Services/ApplicationSwitchingHotkeyController.swift`: atomic EventTap-only Cmd-Tab registration.
- Create `SwitchTabTests/Services/ApplicationSwitchingTests.swift`: focused tests for provider, activation, hotkey, and identity behavior.
- Modify `SwitchTab/Models/SwitcherMode.swift`: add application mode.
- Modify `SwitchTab/Models/ShortcutSetting.swift`: add fixed forward/reverse Cmd-Tab settings.
- Modify `SwitchTab/Services/SwitcherRecencyStore.swift`: isolate recency by switcher mode.
- Modify `SwitchTab/Services/ApplicationSettingsStore.swift`: persist replacement toggle, default false.
- Modify `SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift`: publish and update the toggle.
- Modify `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`: keep registration messages separated by mode.
- Modify `SwitchTab/UI/Settings/ShortcutSettingsView.swift`: render the replacement toggle and status copy.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`: application thumbnail/close policies.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`: pass mode-specific close visibility.
- Modify `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`: hide close controls in application mode.
- Modify `SwitchTab/AppDelegate.swift`: collect/order/present/activate apps and manage independent hotkey lifecycle.
- Modify `SwitchTab.xcodeproj/project.pbxproj`: include each new source and test file in the correct target.
- Modify `SwitchTabTests/TestRunner.swift` and existing suites: register new tests and cover persistence/UI policies.
- Modify `README.md` and `specs/001-macos-switchtab/{spec.md,plan.md,quickstart.md,contracts/switcher-behavior.md}`: replace the obsolete window-only scope and add verification instructions.

---

### Task 1: Application Mode, Identity, and Running-App Collection

**Files:**
- Create: `SwitchTab/Models/ApplicationItem.swift`
- Create: `SwitchTab/Services/RunningApplicationProvider.swift`
- Create: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`
- Modify: `SwitchTab/Models/SwitcherMode.swift`
- Modify: `SwitchTabTests/Models/CoreModelsTests.swift`
- Modify: `SwitchTabTests/TestRunner.swift`
- Modify: `SwitchTab.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing mode and provider tests**

Add assertions that `.applicationSwitching.displayName == "Applications"`. Add a
fake `RunningApplicationSnapshotProviding` and tests proving that the provider:

```swift
let snapshots = [
    RunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.apple.finder", localizedName: "Finder", isRegular: true, isTerminated: false, isActive: true),
    RunningApplicationSnapshot(processIdentifier: 11, bundleIdentifier: "com.example.helper", localizedName: "Helper", isRegular: false, isTerminated: false, isActive: false),
    RunningApplicationSnapshot(processIdentifier: 12, bundleIdentifier: "com.royjen.switchtab", localizedName: "SwitchTab", isRegular: true, isTerminated: false, isActive: false),
]
let provider = RunningApplicationProvider(snapshotProvider: FakeRunningApplicationSnapshotProvider(snapshots), ownBundleIdentifier: "com.royjen.switchtab")
try expectEqual(provider.runningApplications().map(\.id), ["com.apple.finder"])
```

Also test terminated filtering, missing-name fallback to `"Unknown Application"`,
bundle-ID deduplication, and PID fallback IDs.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test swift test`

Expected: compilation fails because `applicationSwitching`,
`RunningApplicationSnapshot`, and `RunningApplicationProvider` do not exist.

- [ ] **Step 3: Implement the application model and provider**

Add:

```swift
public struct ApplicationItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let processIdentifier: Int
    public let bundleIdentifier: String?
    public let isActive: Bool
    public let switcherListItem: SwitcherListItem
}

public struct RunningApplicationSnapshot: Equatable, Sendable {
    public let processIdentifier: Int
    public let bundleIdentifier: String?
    public let localizedName: String?
    public let isRegular: Bool
    public let isTerminated: Bool
    public let isActive: Bool
}

public protocol RunningApplicationSnapshotProviding {
    func snapshots() -> [RunningApplicationSnapshot]
}
```

Implement the NSWorkspace adapter, filter non-regular/terminated/self entries,
deduplicate stable IDs, preserve incoming order, and map application icons through
`appIconProcessIdentifier`. SwiftPM discovers the files automatically under its
existing source/test paths; add explicit file references and target membership
for the Xcode project in `project.pbxproj`.

- [ ] **Step 4: Run focused and full tests and verify GREEN**

Run: `rtk test swift test`

Expected: exit 0 with the new application switching suite included.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add SwitchTab/Models/ApplicationItem.swift SwitchTab/Models/SwitcherMode.swift SwitchTab/Services/RunningApplicationProvider.swift SwitchTabTests/Models/CoreModelsTests.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift SwitchTabTests/TestRunner.swift SwitchTab.xcodeproj/project.pbxproj
rtk git commit -m "feat: model running applications for switching"
```

---

### Task 2: Mode-Scoped MRU and Application Activation

**Files:**
- Create: `SwitchTab/Services/ApplicationActivationService.swift`
- Modify: `SwitchTab/Services/SwitcherRecencyStore.swift`
- Modify: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`
- Modify: `SwitchTabTests/Services/SwitcherRecencyStoreTests.swift`
- Modify: `SwitchTab.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing persistence and activation tests**

Add tests proving window and application stores write different keys:

```swift
let windowStore = SwitcherRecencyStore(userDefaults: defaults, mode: .currentAppWindowSwitching)
let appStore = SwitcherRecencyStore(userDefaults: defaults, mode: .applicationSwitching)
windowStore.recordSelection(id: "window-a")
appStore.recordSelection(id: "com.apple.finder")
windowStore.flush()
appStore.flush()
try expectEqual(defaults.stringArray(forKey: "SwitchTab.recency.currentAppWindowSwitching"), ["window-a"])
try expectEqual(defaults.stringArray(forKey: "SwitchTab.recency.applicationSwitching"), ["com.apple.finder"])
```

Add activation tests for `.activated` and `.unavailableTarget`, and prove
`ApplicationSelectionCoordinator` records and flushes only after activation
succeeds. Construct the coordinator through the explicit seam:

```swift
init(
    activationService: any ApplicationActivationServicing,
    recencyStore: any ApplicationSelectionRecencyRecording
)
```

Add an exact ordering fixture with source applications `[Finder(active), Safari,
Notes]` and MRU `[Notes, Safari]`. Assert the result is `[Finder, Notes, Safari]`,
forward starts on Notes at index 1, and reverse starts on Safari at the final
index.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test swift test`

Expected: compilation fails because mode-scoped initialization and application
activation types are missing.

- [ ] **Step 3: Implement mode-scoped recency and activation**

Change `SwitcherRecencyStore` to accept a mode with the existing window mode as
the source-compatible default. Store one cache/dirty flag per instance and map
the two modes to fixed storage keys. Add:

```swift
public enum ApplicationActivationResult: Equatable, Sendable {
    case activated
    case unavailableTarget
}

public protocol ApplicationActivating {
    func activate(processIdentifier: Int) -> Bool
}

public protocol ApplicationActivationServicing {
    func activate(_ application: ApplicationItem) -> ApplicationActivationResult
}

public protocol ApplicationSelectionRecencyRecording {
    func recordSelection(id: String)
    func flush()
}

public struct ApplicationActivationService: ApplicationActivationServicing {
    public init()
    public init(activator: any ApplicationActivating)
    public func activate(_ application: ApplicationItem) -> ApplicationActivationResult
}

public struct ApplicationSelectionCoordinator {
    public func confirm(_ application: ApplicationItem) -> ApplicationActivationResult
}
```

The system activator resolves the PID at confirmation time and calls
`NSRunningApplication.activate(options: .activateAllWindows)`. Do not check
Accessibility permission. Record and flush MRU only for `.activated`.
`ApplicationActivationService.swift` also owns the small
`WorkspaceActivationRecencyObserver` adapter used in Task 5, so notification
filtering can be tested without constructing `AppDelegate`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test swift test`

Expected: exit 0; existing window-recency tests remain unchanged through the
default mode.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add SwitchTab/Services/ApplicationActivationService.swift SwitchTab/Services/SwitcherRecencyStore.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift SwitchTabTests/Services/SwitcherRecencyStoreTests.swift SwitchTab.xcodeproj/project.pbxproj
rtk git commit -m "feat: track application recency and activation"
```

---

### Task 3: Default-Off Replacement Setting and UI

**Files:**
- Modify: `SwitchTab/Services/ApplicationSettingsStore.swift`
- Modify: `SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift`
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsView.swift`
- Modify: `SwitchTabTests/Services/ApplicationSettingsStoreTests.swift`

- [ ] **Step 1: Write failing setting and view-model tests**

Add tests proving:

```swift
try expectFalse(ApplicationSettingsStore(userDefaults: defaults).replacesCommandTab)
store.saveReplacesCommandTab(true)
try expectTrue(ApplicationSettingsStore(userDefaults: defaults).replacesCommandTab)
```

Verify a changed value posts `.applicationSettingsDidChange`, a no-op does not,
and `ApplicationSettingsViewModel.setReplacesCommandTab(true)` updates both its
published state and storage.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test swift test`

Expected: compilation fails because the setting and view-model API do not exist.

- [ ] **Step 3: Implement persistence and UI**

Add `ApplicationSettingsStore.replacesCommandTab` storage under the fixed
`ApplicationSettings.replacesCommandTab` key with an explicit false default.
Publish `replacesCommandTab` in the application settings view model.
Pass that view model into `ShortcutSettingsPanel` and render:

```swift
SettingsRow(
    symbolName: "command",
    title: "Replace macOS Cmd-Tab",
    detail: "Use SwitchTab to switch applications while it is running."
) {
    Toggle("Replace macOS Cmd-Tab", isOn: Binding(
        get: { applicationSettingsViewModel.replacesCommandTab },
        set: { applicationSettingsViewModel.setReplacesCommandTab($0) }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
}
```

Keep the configurable current-app window shortcut unchanged.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test swift test`

Expected: exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add SwitchTab/Services/ApplicationSettingsStore.swift SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift SwitchTab/UI/Settings/ShortcutSettingsView.swift SwitchTabTests/Services/ApplicationSettingsStoreTests.swift
rtk git commit -m "feat: add opt-in Cmd-Tab replacement setting"
```

---

### Task 4: Atomic EventTap-Only Cmd-Tab Registration

**Files:**
- Create: `SwitchTab/Services/ApplicationSwitchingHotkeyController.swift`
- Modify: `SwitchTab/Models/ShortcutSetting.swift`
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsView.swift`
- Modify: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`
- Modify: `SwitchTabTests/Services/ShortcutSettingsStoreTests.swift`
- Modify: `SwitchTab.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing shortcut and controller tests**

Assert the fixed values are key code 48 with `["command"]` and
`["command", "shift"]`. With an in-memory registrar, prove enabling registers
both exact settings and invokes distinct handlers. Prove disabling unregisters
them. With a registrar that rejects the reverse setting, prove the controller
unregisters the successful forward registration and exposes a mode-specific
failure message instead of leaving a partial Cmd-Tab interception active.

Add view-model tests proving `registrationMessage()` returns only the current-app
window warning and `applicationSwitchingRegistrationMessage()` returns only the
application warning. Exercise the failed EventTap registration path through the
persisted registration-message store and assert the application warning text is
still available after the controller rolls back its partial registration.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test swift test`

Expected: compilation fails because fixed application shortcuts and the
controller are missing.

- [ ] **Step 3: Implement fixed shortcuts and controller**

Add `defaultApplicationSwitching` and its reverse variant to
`ShortcutSetting`. Implement `ApplicationSwitchingHotkeyController` with a
default initializer that creates exactly:

```swift
HotkeyService(registrar: EventTapHotkeyRegistrar())
```

Its update method must unregister before every transition, skip all registration
when disabled, register forward then reverse when enabled, and roll back both if
either fails. Snapshot registration messages before rollback. The controller
owns a separate `HotkeyService`; it must never unregister or replace the
configurable window service. Update
`ShortcutSettingsViewModel.RegistrationMessageText` to maintain separate window
and application strings. Under the Cmd-Tab toggle, render the application-only
failure and recovery copy: `Cmd-Tab replacement needs Accessibility permission.
Grant access in Permissions, then return to SwitchTab.` The window shortcut
warning remains unchanged.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `rtk test swift test`

Expected: exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add SwitchTab/Models/ShortcutSetting.swift SwitchTab/Services/ApplicationSwitchingHotkeyController.swift SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift SwitchTab/UI/Settings/ShortcutSettingsView.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift SwitchTabTests/Services/ShortcutSettingsStoreTests.swift SwitchTab.xcodeproj/project.pbxproj
rtk git commit -m "feat: intercept Cmd-Tab through a dedicated event tap"
```

---

### Task 5: Overlay Policy and AppDelegate Integration

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Modify: `SwitchTab/AppDelegate.swift`
- Modify: `SwitchTabTests/Services/SwitcherOverlayStateTests.swift`
- Modify: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **Step 1: Write failing overlay and ordering tests**

Add tests proving application mode does not show thumbnails, does not allow
close actions, and ignores `.closeSelected`. Assert
`SwitcherOverlayEventMonitorPolicy.globalMask` includes `.flagsChanged` and that
an external Command release confirms the current application selection. Reuse
the exact `[Finder(active), Safari, Notes]` / `[Notes, Safari]` fixture from Task
2 and assert forward selects Notes while reverse selects Safari.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk test swift test`

Expected: the new close-policy assertions fail because close actions are still
window-agnostic.

- [ ] **Step 3: Implement overlay policy**

Add `SwitcherOverlayClosePolicy.allowsClose(for:)`, guard `.closeSelected` in
state, pass `showsCloseControl` through the root/strip/tile, and render/pad for
the close button only in `.currentAppWindowSwitching`.

- [ ] **Step 4: Wire the application flow in AppDelegate**

Add separate provider, activator, recency, and hotkey properties. Implement
`showApplicationSwitcher(reverse:)` using the existing presentation snapshot and
overlay. On confirmation, activate and record the selected application.

Observe `.applicationSettingsDidChange` through `NotificationCenter.default`
and `NSWorkspace.didActivateApplicationNotification` through
`NSWorkspace.shared.notificationCenter`. Convert the workspace notification's
`NSRunningApplication` into the same stable ID used by
`RunningApplicationProvider`. Ignore SwitchTab itself, terminated processes,
and non-regular activation-policy processes; record and flush every external
regular-app activation. Cover this policy through an injected/pure notification
adapter test. Registration rules:

- launch: register window shortcuts, then application shortcuts only if enabled;
- shortcut recording: suspend/re-register the window service without touching
  the application service;
- SwitchTab activation: retry both independent registrations;
- replacement disabled: unregister the app service and dismiss only an active
  application overlay;
- termination: unregister both services and flush both recency stores.

Merge window and application registration messages before storing them and post
`.shortcutRegistrationDidChange` only when the persisted set changes.

- [ ] **Step 5: Run tests, Xcode syntax check, and Debug build**

Run:

```bash
rtk test swift test
rtk proxy plutil -lint SwitchTab.xcodeproj/project.pbxproj
rtk test xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add SwitchTab/AppDelegate.swift SwitchTab/UI/Overlay/SwitcherOverlayState.swift SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTabTests/Services/SwitcherOverlayStateTests.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift
rtk git commit -m "feat: present and activate applications with Cmd-Tab"
```

---

### Task 6: Product Documentation and Manual Verification Contract

**Files:**
- Modify: `README.md`
- Modify: `specs/001-macos-switchtab/spec.md`
- Modify: `specs/001-macos-switchtab/plan.md`
- Modify: `specs/001-macos-switchtab/quickstart.md`
- Modify: `specs/001-macos-switchtab/contracts/switcher-behavior.md`

- [ ] **Step 1: Update scope and behavior documentation**

Replace statements that Cmd-Tab is always untouched or application mode is out
of scope. Document that replacement is opt-in/default-off, needs Accessibility
for the event tap, uses its own MRU, restores native behavior when disabled or
SwitchTab exits, and does not need Screen Recording for application icons.

- [ ] **Step 2: Add manual acceptance scenarios**

Add these exact Finder/Safari/Notes checks, each with the named evidence file:

1. With Accessibility granted and the toggle off, hold Command, press Tab once,
   capture the native macOS switcher as `01-native-off.png`, then release
   Command; no SwitchTab overlay may appear.
2. Turn the toggle on, repeat Command-Tab, and capture only the SwitchTab
   application overlay as `02-switchtab-on.png`; the native switcher must not
   appear.
3. Starting with Finder active and all three apps open, hold Command, press Tab
   repeatedly, then use Shift-Tab; capture distinct forward and reverse
   highlights as `03-forward.png` and `03-reverse.png` and match them to the
   displayed application names.
4. While a non-Finder app is highlighted, release Command; Computer Use app
   state must report that named app frontmost in `04-activation-state.txt`.
5. Return to Settings, turn the toggle off, immediately repeat Command-Tab, and
   capture the native switcher as `05-disabled-native.png`; the window shortcut
   must remain registered.
6. In System Settings > Privacy & Security > Accessibility, turn SwitchTab access
   off. Enable replacement, return to SwitchTab, and verify native Cmd-Tab plus
   the application-specific recovery copy in `06-permission-fallback.png`. Turn
   access back on, return to SwitchTab to trigger retry, and capture the working
   overlay and cleared warning as `06-permission-recovered.png`.
7. Leave replacement enabled, quit and relaunch the QA build, verify the toggle
   is still on and Command-Tab opens SwitchTab, and save
   `07-relaunch-persistence.png`.
8. Quit SwitchTab through its menu, press Command-Tab, and capture restored
   native behavior as `08-quit-native.png`.

For every scenario, include precondition, exact action, expected result, actual
result, selected/frontmost app identity, and evidence path in
`.build/qa/application-switching/outcomes.md`.

- [ ] **Step 3: Verify docs and tests**

Run:

```bash
rtk grep -n "out of.*scope|leaves macOS Cmd.Tab.*untouched" README.md specs/001-macos-switchtab
rtk test swift test
rtk git diff --check
```

Expected: the obsolete-scope grep reports zero matches; tests and diff check exit
0.

- [ ] **Step 4: Commit**

Run:

```bash
rtk git add README.md specs/001-macos-switchtab/spec.md specs/001-macos-switchtab/plan.md specs/001-macos-switchtab/quickstart.md specs/001-macos-switchtab/contracts/switcher-behavior.md
rtk git commit -m "docs: document opt-in application switching"
```

---

### Task 7: Full Verification and Live macOS QA

**Files:**
- Verify only unless a regression test and minimal fix are required.

- [ ] **Step 1: Run the complete automated suite**

Run:

```bash
rtk test swift test
rtk test xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' build
rtk proxy env SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
rtk test bash scripts/tests/release-tooling-test.sh
rtk test bash scripts/tests/release-local-test.sh
rtk test bash scripts/tests/generate-appcast-test.sh
rtk test bash scripts/tests/generate-release-manifest-test.sh
rtk test bash scripts/tests/setup-update-hosting-test.sh
rtk test bash scripts/tests/publish-update-test.sh
rtk test bash scripts/tests/publish-release-test.sh
rtk test bash scripts/tests/dispatch-homebrew-update-test.sh
rtk test bash scripts/tests/release-workflow-test.sh
rtk test bash scripts/tests/prepare-pr-version-test.sh
rtk test bash scripts/tests/plan-release-test.sh
rtk test bash scripts/tests/ci-workflow-test.sh
rtk test bash scripts/tests/automatic-release-workflow-test.sh
rtk git diff --check
```

Expected: every command exits 0.

- [ ] **Step 2: Build and launch a local signed/direct-distribution app**

Load the existing main-worktree release environment only inside a non-echoing
subshell and build the local direct-distribution Release app:

```bash
rtk proxy bash -lc 'set -a; source /Users/kendrick/projects/switchtab/.env.release.local; set +a; exec scripts/build-direct-distribution.sh'
```

`SPARKLE_PUBLIC_ED_KEY` must be present, but do not print it. This local QA build
does not use `--release`; public Developer ID signing/notarization is verified
from the release workflow in Task 8. Launch
`.build/direct-distribution/DerivedData/Build/Products/Release/SwitchTab.app`
through Computer Use, confirm its bundle version/build, and save launch evidence
under `.build/qa/application-switching/`. Quit it through its menu after QA; do
not replace or delete the user's installed `/Applications/SwitchTab.app`.

- [ ] **Step 3: Execute the manual scenarios with Computer Use**

Use Computer Use for every GUI interaction. Record before/action/after
screenshots and app-state output for all eight Finder/Safari/Notes scenarios
from Task 6. Confirm the native switcher is present when replacement is off and
absent when replacement is on. Confirm the selected app changes on Command
release, reverse order is correct, failure copy appears when EventTap
registration is unavailable, and the app remains responsive through at least 20
rapid forward/reverse cycles. Put artifacts and a short outcome log in
`.build/qa/application-switching/`, then quit the QA build and confirm native
Cmd-Tab is restored.

- [ ] **Step 4: Add a regression test before fixing any discovered bug**

For every failure, write a test that fails for the observed reason, run it to
confirm RED, make the smallest fix, and re-run the focused and full suites.

- [ ] **Step 5: Request spec-compliance and code-quality reviews**

Review the full `origin/main...HEAD` diff against the approved design and this
plan. Resolve every critical/important finding, then rerun Step 1 if code changes.

---

### Task 8: PR, Minor Release, and Distribution Verification

**Files:**
- Release metadata is generated by the existing GitHub workflows.

- [ ] **Step 1: Run the project ship gates**

Fetch and merge `origin/main` without force or destructive reset, rerun every
Task 7 command, audit plan completion and coverage, perform the pre-landing
review, push `codex/application-switching`, and create a PR. Record its number as
`<PR>`.

- [ ] **Step 2: Select the repository-native minor release path**

Add the `release:minor` label to the PR. Do not hand-edit the project version;
CI must run `scripts/prepare-pr-version.sh` and commit the calculated version.
Do not hardcode the result: after CI updates the branch, read
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from
`SwitchTab.xcodeproj/project.pbxproj` and use those as `<VERSION>` and `<BUILD>`.

```bash
rtk gh pr edit <PR> --add-label release:minor
rtk gh pr checks <PR> --watch
rtk gh pr view <PR> --json headRefOid,mergeStateStatus,statusCheckRollup
```

- [ ] **Step 3: Wait for required CI and merge**

Require the version job and every verify job to pass on the final `headRefOid`.
If CI adds a version commit, pull it, rerun the local Task 7 suite at that exact
head, and repeat review. Merge through the repository's normal squash path, then
record the merged `origin/main` SHA as `<MAIN_SHA>`:

```bash
rtk gh pr merge <PR> --squash
rtk git fetch origin main --tags
rtk git rev-parse origin/main
```

- [ ] **Step 4: Verify the automatic public release**

Wait for both workflows and require success:

```bash
rtk gh run list --workflow automatic-release.yml --branch main --limit 5
rtk gh run watch <AUTOMATIC_RUN_ID> --exit-status
rtk gh run list --workflow release.yml --branch main --limit 5
rtk gh run watch <RELEASE_RUN_ID> --exit-status
```

Fetch tags and prove annotated tag `v<VERSION>` resolves to `<MAIN_SHA>` with
`rtk git cat-file -t refs/tags/v<VERSION>` and
`rtk git rev-parse 'refs/tags/v<VERSION>^{commit}'`. Inspect the GitHub Release
with `rtk gh release view v<VERSION> --json url,assets,tagName,targetCommitish`.
Download its DMG and checksum into a path created by `rtk proxy mktemp -d`, run
`rtk proxy shasum -a 256 -c <CHECKSUM_FILE>`, and require `OK`. Fetch the
published appcast with `rtk proxy curl -fsSL <APPCAST_URL>` and verify its
version, build, enclosure URL, signature, and checksum match the Release.

Before replacing the installed Cask, quit SwitchTab through Computer Use and
retain the previous public app only in
`.build/qa/application-switching/updater/previous/SwitchTab.app`. Run
`rtk proxy brew update`, `rtk proxy brew info --cask sonim1/tap/switchtab`, and
`rtk proxy brew reinstall --cask sonim1/tap/switchtab`; require the Cask version
and SHA-256 to match `<VERSION>` and the verified DMG. Confirm the resulting
`/Applications/SwitchTab.app` bundle's
`CFBundleShortVersionString`, `CFBundleVersion`, and code-signing/notarization
assessment match the released artifact.

- [ ] **Step 5: Verify the shipped updater path**

Download the immediately previous public DMG with
`rtk gh release download v<PREVIOUS_VERSION> --pattern '*.dmg' --dir
.build/qa/application-switching/updater/`, mount it with `rtk proxy hdiutil
attach`, and copy its app into the exact previous-app path above with `rtk proxy
ditto`; detach the explicit mounted volume with `rtk proxy hdiutil detach`.
Launch that isolated previous app with Computer Use, choose menu-bar `Check for
Updates...`, install the new version, and relaunch. Verify `<VERSION>` / `<BUILD>` from the installed
bundle, code signature and notarization, default-off state for the new toggle,
successful opt-in Cmd-Tab behavior, and native fallback after disabling/quitting.
Save screenshots/logs under `.build/qa/application-switching/release/`. Record
the PR URL, final CI head SHA, merged main SHA, workflow run URLs, release URL,
tag provenance, DMG checksum, appcast version/build, Homebrew Cask version/SHA,
and updater result in the completion report. Any failed check blocks completion
and release sign-off.
