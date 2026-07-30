# Application Switching and Cmd-Tab Replacement Design

**Date:** 2026-07-29
**Status:** Approved

## Goal

Add an application-switching mode that can optionally replace the native macOS
Cmd-Tab switcher. The feature is off by default. When disabled, SwitchTab must
not register, observe, or consume Cmd-Tab.

## User Experience

- Settings > Shortcut shows a `Replace macOS Cmd-Tab` toggle below the existing
  current-app window shortcut.
- The toggle defaults to off and persists through `ApplicationSettingsStore`.
- Enabling it assigns Cmd-Tab to forward application switching and
  Cmd-Shift-Tab to reverse application switching.
- Holding Command opens the existing SwitchTab overlay. Repeated Tab presses
  move the selection, Shift reverses direction, and releasing Command activates
  the highlighted application.
- Application mode shows application icons and names without window thumbnails
  or close controls.
- If Accessibility permission is missing, enabling the toggle remains saved but
  the event tap cannot replace Cmd-Tab. The existing permission UI remains the
  recovery path, and SwitchTab retries registration when it becomes active.
- Disabling the toggle tears down only the application-switching event tap. The
  configurable current-app window shortcut remains registered.

## Architecture

### Application model and collection

`ApplicationItem` is a Sendable value containing a stable switcher ID, process
identifier, name, active state, and its `SwitcherListItem`. The stable ID uses
the bundle identifier when present and a process-scoped fallback otherwise. The
PID fallback is intentionally session-scoped: a persisted bundleless entry may
not match after that process relaunches and simply falls back to provider order.

`RunningApplicationProvider` reads `NSWorkspace.shared.runningApplications` and
filters out terminated processes, non-regular activation-policy processes, and
SwitchTab itself. It returns active applications first only through the shared
ordering policy; source order is not treated as recency.

### MRU ordering

`SwitcherRecencyStore` becomes mode-scoped. Existing window history keeps its
current UserDefaults key. Application history uses a separate key so window and
application selections cannot reorder each other.

The application provider output is ordered by the application MRU store and the
currently active application is pinned to the first position. This makes the
initial forward selection land on the previously active application at index 1.
Successful SwitchTab selections and workspace activation notifications record
the stable application ID. History is flushed after successful selection and at
termination.

### Activation

`ApplicationActivationService` resolves the current `NSRunningApplication` by
process identifier and calls `activate(options: .activateAllWindows)`. It returns
a typed result so tests can prove success and unavailable-target behavior.
Application activation does not require the Accessibility permission used for
individual window focus.

### Overlay reuse

`AppDelegate.showApplicationSwitcher(reverse:)` mirrors the current window flow:

1. Advance an already-presented application session when appropriate.
2. Collect running applications.
3. Apply application MRU ordering and pin the active application first.
4. Build a `SwitcherPresentationSnapshot`.
5. Present the existing overlay with `.applicationSwitching`.
6. Activate and record the selected application on confirmation.

The existing thumbnail policy remains window-only. A new close-action policy
prevents Cmd-W and close buttons from being exposed in application mode.

### Reserved shortcut registration

The existing Carbon-first registrar remains unchanged for configurable window
shortcuts. Application replacement uses a separate `HotkeyService` backed
directly by `EventTapHotkeyRegistrar`, ensuring the reserved Cmd-Tab combinations
are handled by a suppressing CGEventTap rather than Carbon registration.

The forward and reverse application shortcuts are fixed `ShortcutSetting`
values. Registration is attempted only while replacement is enabled. Matching
key-down events are consumed by returning `nil`; unrelated events pass through.
The overlay's existing modifier-release monitor confirms selection when Command
is released.

## Persistence and Notifications

`ApplicationSettingsStore.replacesCommandTab` uses a new Boolean UserDefaults
key and defaults to false. Saving a changed value posts
`.applicationSettingsDidChange`. `ApplicationSettingsViewModel` publishes the
value and writes through the store.

`AppDelegate` observes application-setting changes and registers or unregisters
the dedicated application hotkey service immediately. It also retries enabled
registration after app activation, which covers returning from System Settings
after granting Accessibility permission.

## Failure Handling

- No applications: dismiss an existing overlay and do nothing.
- Selected process terminated: activation returns unavailable; no MRU write.
- Event tap creation fails: native Cmd-Tab remains available because no event is
  consumed. A mode-specific registration message is persisted and shown in
  settings.
- Toggle disabled while overlay is visible: unregister the app event tap and
  dismiss an active application-switching overlay.
- SwitchTab exits or crashes: macOS automatically restores native Cmd-Tab because
  the process-owned event tap disappears.

## Tests

Automated XCTest coverage will prove:

- mode names and fixed Cmd-Tab shortcut values;
- running-app filtering, stable IDs, active-app pinning, and list-item mapping;
- application activation success/failure and MRU writes only after success;
- separate window/application MRU persistence keys;
- replacement toggle default, persistence, notification, and view-model state;
- event-tap-only forward/reverse registration policy and disabled teardown;
- overlay thumbnail/close policy for application mode;
- AppDelegate-independent coordination of application collection, presentation,
  selection, and activation where OS boundaries are injected.

Full verification also runs `swift test`, an Xcode Debug build, direct-release
workspace preparation, manual direct-build checks, and signed public-artifact
checks for native Cmd-Tab fallback, forward/reverse cycling, Command-release
activation, toggle teardown, and permission recovery.

## Documentation and Release

README shortcut and permission guidance will describe the opt-in replacement and
default-off behavior. The release uses the repository's existing PR versioning,
CI, signing, notarization, Sparkle appcast, GitHub Release, and Homebrew Cask
automation. No new distribution path is introduced.

## Out of Scope

- Reproducing undocumented Dock ordering state beyond SwitchTab's own MRU.
- Native switcher commands such as Cmd-Q or Cmd-H while the overlay is open.
- Per-application exclusions or a configurable application-mode shortcut.
- Replacing Cmd-Tab on the login screen, lock screen, or after SwitchTab exits.
