# Implementation Plan: macOS SwitchTab

**Branch**: `001-macos-switchtab` | **Date**: 2026-06-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-macos-switchtab/spec.md`

## Summary

Build a native macOS-only current-app window switcher that opens from a
configurable keyboard shortcut. macOS keeps ownership of Cmd+Tab app switching;
SwitchTab focuses on switching between windows belonging to the currently active
application, showing current window previews when permissions allow. The app is
a lightweight menu bar utility with a keyboard-first icon-strip overlay,
configurable window shortcut, explicit permission guidance, and no
cross-platform scope.

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
registration messages, app settings, and lightweight window-switching usage
metrics. No database.

**Testing**: XCTest for pure logic and service boundaries; manual quickstart
validation for live macOS window focus, permissions, global shortcuts, Screen
Recording previews, and System Settings recovery.

**Target Platform**: macOS 14.0+ only.

**Project Type**: Native macOS menu bar desktop app.

**Performance Goals**: Overlay visible within 200 ms of shortcut invocation;
keyboard selection updates stay responsive for 20 apps and 50 windows; no
visible idle UI activity or user-noticeable slowdown over 10 minutes idle.

**Constraints**: Keyboard-first interaction, configurable shortcuts, graceful
handling of Accessibility and Screen Recording permission states, no continuous
polling for window/application state unless justified by measurement.
Permission recovery must not synthesize System Settings clicks, drags, or
toggle changes.

**Scale/Scope**: Single-user local desktop utility; the checked-in app covers
current-app window switching, shortcut settings, permission guidance, menu bar
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
│   ├── ApplicationIconStore.swift
│   ├── ApplicationSettingsStore.swift
│   ├── HotkeyService.swift
│   ├── PermissionService.swift
│   ├── PermissionSettingsDestination.swift
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

Components:
- `PermissionService`: Reads Accessibility and Screen Recording grant state
  with first-party macOS APIs.
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
  relaunch requirements after granting privacy permissions, window focus, and
  window previews.
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
