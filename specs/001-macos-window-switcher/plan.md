# Implementation Plan: macOS Window Switcher

**Branch**: `001-macos-window-switcher` | **Date**: 2026-06-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-macos-window-switcher/spec.md`

## Summary

Build a native macOS-only current-app window switcher that opens from a
configurable keyboard shortcut. macOS keeps ownership of Cmd+Tab app switching;
SwitchTab focuses on switching between windows belonging to the currently active
application, showing current window previews when permissions allow. The app is
a lightweight menu bar utility with a keyboard-first icon-strip overlay,
configurable window shortcut, explicit permission guidance, and no
cross-platform scope.

Permission recovery adds a precision-positioned drag overlay for Accessibility
and Screen Recording. When the user clicks Allow, SwitchTab opens the matching
macOS Settings privacy pane, locates the visible System Settings window, and
shows a floating panel near the target list with a draggable SwitchTab app row.
The grant still remains fully user-driven: the app provides the file drag source
and positioning help, but never clicks, toggles, or grants privacy access itself.

## Technical Context

**Language/Version**: Swift 5.10+ using SwiftUI and AppKit interoperability

**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices Accessibility,
ScreenCaptureKit, CoreGraphics window-list APIs, XCTest. No third-party runtime
dependency for the initial implementation.

**Storage**: UserDefaults for the window shortcut setting, permission guidance
state, app settings, and lightweight window-switching usage metrics. No database.

**Testing**: XCTest for pure logic and service boundaries; manual quickstart
validation for live macOS window focus, permissions, global shortcuts, and
System Settings drag-drop permission recovery.

**Target Platform**: macOS 14.0+ only.

**Project Type**: Native macOS menu bar desktop app.

**Performance Goals**: Overlay visible within 200 ms of shortcut invocation;
keyboard selection updates stay responsive for 20 apps and 50 windows; no
visible idle UI activity or user-noticeable slowdown over 10 minutes idle.

**Constraints**: Keyboard-first interaction, configurable shortcuts, graceful
handling of Accessibility and Screen Recording permission states, no continuous
polling for window/application state unless justified by measurement. Permission
recovery may use bounded window lookup after an explicit user action, but must
not synthesize System Settings clicks, drags, or toggle changes.

**Scale/Scope**: Single-user local desktop utility; first release covers app
current-app window switching, shortcut settings, permission guidance, and local
usage metrics only.

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
specs/001-macos-window-switcher/
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
WindowSwitcher.xcodeproj/
WindowSwitcher/
├── WindowSwitcherApp.swift
├── AppDelegate.swift
├── Models/
│   ├── ApplicationItem.swift
│   ├── PermissionState.swift
│   ├── ShortcutSetting.swift
│   ├── SwitcherSession.swift
│   ├── SwitcherMode.swift
│   └── WindowItem.swift
├── Services/
│   ├── AccessibilityWindowProvider.swift
│   ├── AppSwitchingService.swift
│   ├── HotkeyService.swift
│   ├── PermissionService.swift
│   ├── PermissionAssistPositioningPolicy.swift
│   ├── ShortcutValidationService.swift
│   ├── ShortcutSettingsStore.swift
│   ├── SystemSettingsWindowLocator.swift
│   ├── SwitcherPresentationSnapshot.swift
│   ├── UsageMetricsStore.swift
│   ├── WindowThumbnailService.swift
│   └── WindowFocusService.swift
├── UI/
│   ├── MenuBar/
│   ├── Overlay/
│   ├── Permissions/
│   │   ├── PermissionAssistPanelController.swift
│   │   └── PermissionDragSourceView.swift
│   └── Settings/
└── Resources/

WindowSwitcherTests/
├── Models/
├── Services/
└── Support/
```

**Structure Decision**: Use a single native macOS app target plus one test
target. Keep platform APIs behind service boundaries so shortcut validation,
permission-state mapping, activation, selection rules, thumbnail loading, and
usage metrics can be tested without live OS windows.

## Permission Drag Overlay Design

Trigger:
- Missing Accessibility or Screen Recording permission row exposes an Allow
  action.
- Allow opens the relevant System Settings privacy destination and starts one
  `PermissionAssistSession`.
- If permission is already granted when the row is clicked, no overlay appears.

Components:
- `PermissionAssistSession`: Permission type, target settings destination,
  instruction copy, app bundle URL, start time, and dismissal state.
- `SystemSettingsWindowLocator`: Uses `CGWindowListCopyWindowInfo` to find the
  largest visible System Settings window after the user opens a privacy pane.
  It accepts System Settings/System Preferences naming differences and returns
  window bounds only, not private UI hierarchy.
- `PermissionAssistPositioningPolicy`: Pure function that takes Settings window
  bounds, visible screen frame, and panel size, then returns a clamped global
  panel origin. Preferred placement is centered horizontally over the lower
  content area, just below the permission list.
- `PermissionAssistPanelController`: Owns a borderless/floating `NSPanel`,
  arrow, instruction label, close/back affordance, and draggable app row.
- `PermissionDragSourceView`: AppKit drag source that starts an
  `NSDraggingSession` with `Bundle.main.bundleURL` as a file URL pasteboard
  writer and advertises a copy operation.

Flow:
1. User clicks Allow for Accessibility or Screen Recording.
2. `PermissionService` opens the matching macOS Settings pane.
3. Locator performs bounded lookup for up to 3 seconds with short intervals.
4. Positioning policy places the helper panel relative to the found Settings
   window, or falls back to the active screen center if no reliable window is
   found.
5. User drags the SwitchTab row into the System Settings app list.
6. App refreshes permission state when it becomes active again, when the panel
   closes, and when the user returns to Settings.

Verification:
- Unit tests cover permission-type copy, locator filtering with fake window
  dictionaries, positioning/clamping, and session lifecycle.
- Manual validation covers real Accessibility and Screen Recording panes,
  fallback placement, drag behavior, and relaunch requirements after granting
  privacy permissions.
- No timer or polling loop remains active after the bounded lookup finishes.

## Complexity Tracking

No constitution violations.

## Implementation Verification Notes

- Automated verification in this workspace uses `swift run WindowSwitcherTestRunner`
  for fast service and model coverage.
- Xcode Debug app builds are verified with `xcodebuild -project
  WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug
  -destination 'platform=macOS,arch=arm64' build`.
- Service review found no continuous polling constructs in `WindowSwitcher/Services`
  (`Timer`, `poll`, `while`, `repeat`, `DispatchSource`, `sleep`, or
  `scheduledTimer`).
