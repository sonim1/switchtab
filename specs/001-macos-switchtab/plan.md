# Implementation Plan: macOS SwitchTab

**Branch**: `001-macos-switchtab` | **Date**: 2026-06-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-macos-switchtab/spec.md`

## Summary

Build a native macOS-only current-app window switcher that opens from a
configurable keyboard shortcut, plus an opt-in application switcher that can
replace Cmd+Tab while SwitchTab is running. Replacement defaults off, so native
macOS Cmd+Tab remains the default. The application mode uses a dedicated
Accessibility-backed EventTap, an application-only MRU, and the existing
keyboard-first icon-strip overlay; the current-app window mode keeps its
preview and permission behavior unchanged.

Permission recovery is user-driven. When the user clicks Allow for
Accessibility or Screen Recording, SwitchTab opens the matching macOS Settings
privacy pane and explains the blocked capability. The grant remains fully under
the user's control: the app never clicks, toggles, grants privacy access, or
modifies macOS TCC state.

## Technical Context

**Language/Version**: Swift 5.10+ using SwiftUI and AppKit interoperability

**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices Accessibility,
ScreenCaptureKit, CoreGraphics window-list APIs, XCTest. The checked-in app
target has no third-party runtime dependency; the direct-distribution build
script injects a pinned Sparkle package revision only into its generated
workspace.

**Storage**: UserDefaults for the window shortcut setting, shortcut
registration messages, app settings, separate window/application MRU histories,
and lightweight switching usage metrics. No database.

**Testing**: XCTest for pure logic and service boundaries; manual quickstart
validation for live macOS window/application focus, opt-in Cmd+Tab replacement,
permissions, global shortcuts, Screen Recording previews, and System Settings
recovery. The eight Finder/Safari/Notes application scenarios are recorded in
`.build/qa/application-switching/outcomes.md`.

**Target Platform**: macOS 14.0+ only.

**Project Type**: Native macOS menu bar desktop app.

**Performance Goals**: Overlay visible within 200 ms of shortcut invocation;
keyboard selection updates stay responsive for 20 apps and 50 windows; no
visible idle UI activity or user-noticeable slowdown over 10 minutes idle.

**Constraints**: Keyboard-first interaction, configurable window shortcut,
default-off application replacement, graceful handling of Accessibility and
Screen Recording permission states, and no continuous polling for
window/application state unless justified by measurement. Application
replacement uses a separate Accessibility EventTap and does not share the
window shortcut registrar. Permission recovery must not synthesize System
Settings clicks, drags, or toggle changes. Screen Recording is not required for
application icons or names.

**Scale/Scope**: Single-user local desktop utility; the checked-in app covers
current-app window switching, opt-in application switching, independent
window/application shortcut and MRU state, permission guidance, menu bar
visibility, overlay sizing, update hooks, and local usage metrics.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **macOS-Only Product Scope**: PASS. Target is macOS 14.0+ only. No Windows,
  Linux, iOS, or web support.
- **Code Quality and Simplicity**: PASS. Plan uses one native app target,
  first-party frameworks, UserDefaults, and small service boundaries.
- **Testable Behavior**: PASS. Pure logic gets XCTest coverage. OS-bound focus,
  permission, shortcut, and preview behavior gets documented manual validation.
- **Consistent macOS UX**: PASS. App is a menu bar utility with keyboard-first
  overlay, macOS-style shortcut settings, click-to-confirm targets,
  release-to-confirm behavior, and permission recovery text.
- **Performance by Default**: PASS. Plan defines invocation, selection, idle,
  and scale targets from the spec.

Post-design re-check: PASS. Research, data model, contracts, and quickstart keep
the same boundaries and add no constitution violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-macos-switchtab/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── switcher-behavior.md
└── tasks.md
```

### Source Code (repository root)

```text
SwitchTab.xcodeproj/
SwitchTab/
├── SwitchTabApp.swift
├── AppDelegate.swift
├── Models/
│   ├── ApplicationItem.swift
│   ├── OverlaySizePreference.swift
│   ├── PermissionState.swift
│   ├── ShortcutKeyCodeResolver.swift
│   ├── ShortcutSetting.swift
│   ├── SwitcherMode.swift
│   ├── SwitcherReadableText.swift
│   ├── SwitcherSession.swift
│   └── WindowItem.swift
├── Services/
│   ├── AccessibilityWindowProvider.swift
│   ├── ApplicationActivationService.swift
│   ├── ApplicationSwitchingHotkeyController.swift
│   ├── ApplicationIconStore.swift
│   ├── ApplicationSettingsStore.swift
│   ├── HotkeyService.swift
│   ├── PermissionService.swift
│   ├── PermissionSettingsDestination.swift
│   ├── RunningApplicationProvider.swift
│   ├── ShortcutModifierResolver.swift
│   ├── ShortcutValidationService.swift
│   ├── ShortcutSettingsStore.swift
│   ├── SparkleUpdateController.swift
│   ├── SwitcherPresentationSnapshot.swift
│   ├── SwitcherRecencyStore.swift
│   ├── UpdateController.swift
│   ├── UsageMetricsStore.swift
│   ├── WindowThumbnailService.swift
│   └── WindowFocusService.swift
├── UI/
│   ├── About/
│   ├── MenuBar/
│   ├── Overlay/
│   ├── Permissions/
│   │   └── PermissionStatusView.swift
│   └── Settings/
└── Resources/

SwitchTabTests/
├── Models/
├── Services/
├── Support/
└── TestRunner.swift
```

**Structure Decision**: Use a single native macOS app target plus one test
target. Keep platform APIs behind service boundaries so shortcut validation,
permission-state mapping, activation, selection rules, thumbnail loading, and
usage metrics can be tested without live OS windows.

## Permission Recovery Design

Trigger:
- Missing Accessibility or Screen Recording permission row exposes an Allow
  action.
- Allow opens the relevant System Settings privacy destination.
- If permission is already granted, the row shows an enabled state and no
  recovery action.
- Enabling `Replace macOS Cmd-Tab` while Accessibility is missing keeps the
  setting saved but leaves the application EventTap unregistered; native
  Cmd+Tab is not consumed.

Components:
- `PermissionService`: Reads Accessibility and Screen Recording grant state
  with first-party macOS APIs. Accessibility gates current-app window
  observation/focus and application EventTap interception; Screen Recording
  gates only current-app window previews.
- `PermissionState`: Maps grant state to blocked capability copy and Settings
  recovery steps.
- `PermissionSettingsDestination`: Owns the System Settings URLs for the
  Accessibility and Screen Recording privacy panes.
- `PermissionStatusView`: Renders the permission rows and routes Allow clicks to
  the destination-opening callback.
- `ShortcutSettingsView`: Opens System Settings with `NSWorkspace` and refreshes
  permission state when SwitchTab becomes active again.

Flow:
1. User clicks Allow for Accessibility or Screen Recording.
2. `ShortcutSettingsView` opens the matching macOS Settings privacy pane.
3. User grants permission manually in System Settings.
4. SwitchTab refreshes permission state when it becomes active again.

Verification:
- Unit tests cover permission copy, destination mapping, granted/missing row
  states, and Settings action labels.
- Manual validation covers real Accessibility and Screen Recording panes,
  relaunch requirements after granting privacy permissions, native Cmd+Tab
  fallback/recovery, application focus, window focus, and window previews.
- Application icons and names are validated without Screen Recording; only the
  current-app window preview path depends on that permission.
- No System Settings automation, synthetic input, TCC DB mutation, timer, or
  polling loop is part of permission recovery.

## Complexity Tracking

No constitution violations.

## Implementation Verification Notes

- Automated verification in this workspace uses `swift test`
  for fast service and model coverage.
- Xcode Debug app builds are verified with `xcodebuild -project
  SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug
  -destination 'platform=macOS,arch=arm64' build`.
- Direct-distribution workspace generation is verified with
  `SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh
  --prepare-only`.
- Service review found no continuous polling constructs in `SwitchTab/Services`
  (`Timer`, `poll`, `DispatchSource`, `sleep`, or `scheduledTimer`). The
  remaining `while` loops in `AccessibilityWindowProvider` are finite in-memory
  matching loops, not idle polling.

## Application-Switching Manual Verification Contract

The canonical Finder/Safari/Notes acceptance sequence is documented in
[quickstart.md](quickstart.md#application-switching-manual-acceptance-contract).
It covers native fallback with replacement off, SwitchTab overlay behavior with
replacement on, forward/reverse selection, Command-release activation,
disablement, Accessibility fallback and recovery, relaunch persistence, and
quit restoration. The exact evidence files are:

| Scenario | Evidence |
| --- | --- |
| 01 native behavior with replacement off | `01-native-off.png` |
| 02 SwitchTab overlay with replacement on | `02-switchtab-on.png` |
| 03 forward and reverse highlights | `03-forward.png`, `03-reverse.png` |
| 04 Command-release activation state | `04-activation-state.txt` |
| 05 native behavior after disabling | `05-disabled-native.png` |
| 06 Accessibility fallback and recovery | `06-permission-fallback.png`, `06-permission-recovered.png` |
| 07 relaunch persistence | `07-relaunch-persistence.png` |
| 08 native behavior after quitting | `08-quit-native.png` |

For each scenario, QA records `precondition`, `exact action`, `expected`,
`actual`, `selected/frontmost app identity`, and `evidence path` in
`.build/qa/application-switching/outcomes.md`. This plan records the contract,
not a claim that the live macOS scenarios have already passed.
