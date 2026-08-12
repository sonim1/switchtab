# Switcher Mode Toggle With Remembered Selection

Date: 2026-08-11

## Problem

Application switching (Command-Tab) and current-app window switching (Command-Backtick) are two
disconnected sessions. While the application overlay is open, pressing the window shortcut falls
through to the global window hotkey, which opens a *new* session listing the windows of the
frontmost application — not the application highlighted in the overlay. Pressing Tab again restarts
the application overlay from its default selection. Neither mode remembers where the highlight was.

## Goal

While the trigger modifier stays held, the overlay becomes one session that can toggle between the
two modes and resumes each mode where it was left.

## Behavior

- **Application mode → window mode.** Pressing the window shortcut's key lists the windows of the
  **highlighted application**, not the frontmost one. Highlight starts on that application's most
  recent window, or on the window remembered from an earlier visit in this session.
  An application with no listable windows is left alone: the overlay stays in application mode.
- **Window mode → application mode.** Pressing the application shortcut's key returns to the
  application list, restores the application that was highlighted before, then advances one step:
  Tab moves to the next application, Shift-Tab to the previous one. With nothing remembered
  (the session started in window mode), selection falls back to the normal fresh-invocation index.
- **Key matching.** The alternate mode is recognised by **key code only**; the modifiers held for
  the active trigger are irrelevant, so a fallback shortcut such as Option-Control-Backtick still
  toggles while Command is held. Shift only selects the direction of the advance.
- **Availability.** The alternate key is recognised only while that mode is enabled and actually
  registered. When application switching is off or unregistered, Tab is never consumed by the
  overlay — native Command-Tab keeps working.
- **Commit and cancel are unchanged.** The session still confirms on release of the original
  trigger modifiers and cancels on Escape or an outside mouse press. Memory lives only for the
  duration of one held-modifier session and is cleared when the overlay ends.

## Design

### New model — `SwitcherModeSwitchMemory` (`SwitchTab/Models/`)

Value type holding one session's memory:

- `applicationID: String?` — the `ApplicationItem.id` last highlighted in application mode.
- `windowIDByOwnerProcessIdentifier: [Int: String]` — the last highlighted `WindowItem.id` per
  application process. Process identifier is the key because window items carry a pid while
  application items are keyed by bundle identifier.
- `resumedIndex(itemCount:rememberedIndex:advance:fallback:)` — resolves the arrival selection:
  remembered index plus a wrapped advance, or the fallback when nothing is remembered.

### Mode-switch recognition (`SwitchTab/UI/Overlay/SwitcherOverlayPresentationPolicy.swift`)

`SwitcherOverlayModeSwitchPolicy.command(keyCode:modifiers:alternateModeKeyCode:)` returns
`.switchMode(reverse:)` when the key code matches the alternate mode's key. The event tap policy
checks the *active* trigger first, so a shared key code always keeps its in-mode meaning.

`SwitcherCommand` gains `switchMode(reverse: Bool)`; `SwitcherInteractionResult` gains
`modeSwitchRequested(reverse: Bool)`. `SwitcherOverlayState` does not mutate on this command — the
composition root decides whether the switch is possible, so a refused switch leaves the session
untouched.

### Overlay controller

`present` gains `alternateModeKeyCode`, `onModeSwitch`, and `retainingSession`. With
`retainingSession` the controller swaps mode, items, selection, trigger shortcut and alternate key
in place: the panel, the event tap, the event monitors and — critically — the original
`triggerReleaseModifiers` all survive, so holding Command still commits after the switch. The tap
owner's trigger becomes mutable so no tap is torn down from inside its own callback.

### Window enumeration

`AccessibilityWindowProvider.applicationWindows(ownerProcessIdentifier:ownerName:includeScreenCaptureIdentifiers:)`
exposes the existing private per-process lookup so window mode can list another application.
`AXWindowFocuser` already activates the owning application before focusing, so confirming a window
of a non-frontmost application needs no new focus behavior.

### Composition root

`AppDelegate` keeps the session memory, records the highlight before each switch, resolves the
alternate key code from live registrations (`HotkeyService.registeredSetting` for window mode,
`ApplicationSwitchingHotkeyController.isRegistered` for application mode) and re-presents with
`retainingSession: true`. Memory resets on overlay dismissal.

## Verification

- `swift build`, `swift test` (new native `XCTestCase` suites are auto-discovered).
- Unsigned Xcode Debug build of the `SwitchTab` scheme; the four new files are registered by hand
  in `project.pbxproj`.
- Runtime checks with Accessibility permission: Command-Tab → Backtick → windows of the highlighted
  application; Tab back → next application; Shift-Tab back → previous; release commits; Escape
  cancels; application switching disabled leaves Tab native.
