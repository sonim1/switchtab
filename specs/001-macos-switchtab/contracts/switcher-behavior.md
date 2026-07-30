# Contract: Switcher Behavior

Current repository scope (2026-07-29): this contract covers the checked-in
current-app window switcher and the opt-in application switcher. The
`Replace macOS Cmd-Tab` setting defaults off; native Cmd+Tab remains available
while it is disabled, when Accessibility prevents EventTap registration, and
after SwitchTab exits.

## Current-App Window Switching

Trigger:
- User presses the configured current-app window shortcut.

Preconditions:
- An application other than the switcher is active.
- Accessibility permission is granted for window enumeration/focus behavior.
- Screen Recording permission is granted for live window previews; otherwise a
  fallback row is shown with recovery guidance.

Visible result:
- Overlay appears within 200 ms.
- Overlay lists only windows owned by the active application at invocation time.
- Each row shows a current visual preview when permission allows and a readable
  title when available.

Keyboard behavior:
- Repeated shortcut input or arrow keys move selection.
- Releasing the trigger shortcut focuses the highlighted window.
- Enter also focuses the highlighted window.
- Escape cancels without changing focus.

Pointer behavior:
- Clicking a window row, icon, or preview confirms that window through the same
  path as keyboard confirmation.

Completion:
- Selected window becomes focused.
- Overlay closes.
- If the target becomes unavailable, the overlay keeps the user in a safe state
  and does not crash.

## Opt-In Application Switching

Trigger:
- User enables `Replace macOS Cmd-Tab` in Settings > Shortcut and presses
  Cmd+Tab (forward) or Cmd+Shift+Tab (reverse) while SwitchTab is running.

Preconditions:
- The replacement toggle is on.
- Accessibility permission is granted so the dedicated suppressing EventTap can
  intercept the fixed Cmd+Tab shortcuts.
- Finder, Safari, Notes, or other regular running applications are available;
  SwitchTab itself, terminated processes, and non-regular activation-policy
  processes are excluded.

Visible result:
- The existing overlay appears in application mode with application icons and
  names only.
- Each application tile contains one application icon, the application name,
  and, when known, an optional window-count glyph/value.
- The selected tile has an inset selection outline.
- Fully visible one-, two-, and three-row grids stay stationary. Selection
  scrolling starts only when the logical grid actually overflows the visible
  rows.
- Window thumbnails and close controls are not shown.
- Application order uses a mode-scoped application MRU, independent from window
  MRU. The active application is pinned first so the initial forward selection
  advances to the next application.
- Screen Recording permission is not required for application icons or names.

Keyboard behavior:
- Repeated Cmd+Tab advances application selection.
- Repeated Cmd+Shift+Tab reverses application selection.
- Tab/Shift-Tab and arrow-key movement follow the same selection navigation as
  the current-app window switcher.
- Releasing Command confirms the highlighted application.
- Cmd+Q requests normal application termination. It is not a force-quit path.
- Escape cancels without changing the frontmost application or writing MRU.

Completion:
- The selected process is activated with all of its windows.
- Successful activation records the stable application identifier in application
  MRU; an unavailable process does not write history.
- Overlay closes after confirmation.

Lifecycle and fallback:
- A Cmd+Q request does not optimistically remove its tile. The tile is removed
  only after `NSWorkspace.didTerminateApplicationNotification`; save dialogs or
  a rejected termination leave it in place. The overlay remains open for the
  remaining applications so the user can continue cycling.
- Cmd+W and visible close controls are window-mode behavior only; application
  mode does not close a window for either input.
- Workspace activation while the trigger modifier is still held does not cancel
  the overlay. After the trigger modifier is released, normal confirmation and
  activation semantics apply.
- Disabling the toggle unregisters only the application EventTap and dismisses
  an active application overlay; the configurable current-app window shortcut
  remains registered.
- A failed or partial EventTap registration is rolled back without consuming
  Cmd+Tab and exposes application-specific Accessibility recovery copy.
- Quitting or crashing removes the process-owned EventTap, restoring native
  macOS Cmd+Tab behavior.

## Shortcut Settings

Trigger:
- User opens settings from the menu bar item or app UI.

Behavior:
- User can edit the current-app window shortcut.
- Settings show shortcut controls, the `Replace macOS Cmd-Tab` opt-in toggle,
  and permission status.
- The application replacement toggle defaults off and persists separately from
  the current-app window shortcut.
- General app preferences such as overlay size may be present.
- Saving validates usability.
- Invalid or unusable shortcuts display a specific error.
- A rejected shortcut never replaces the last valid shortcut.
- Disabling application replacement leaves the current-app window shortcut
  registered.

## Permission Guidance

Accessibility missing:
- App explains that window observation and window focus require Accessibility access.
- App explains that application Cmd-Tab replacement also requires Accessibility
  for its EventTap.
- App shows recovery steps for macOS Settings.
- Current-app window switching actions remain blocked until access is granted.
- If replacement is enabled, the setting remains saved but native Cmd+Tab is not
  consumed until EventTap registration succeeds.

Screen Recording missing:
- App explains that window previews require Screen Recording access.
- App still shows window titles when available.
- Application icons and names remain available because application switching
  does not require Screen Recording.
- App shows recovery steps for macOS Settings.

## Permission Settings Recovery

Trigger:
- User clicks Allow from a missing Accessibility or Screen Recording permission
  row in Settings.

Preconditions:
- The app is running as SwitchTab.
- The selected permission is missing.
- The current app bundle URL is available.

Visible result:
- The matching macOS Settings privacy pane opens.
- The Settings permission row keeps showing the blocked capability and manual
  recovery guidance until macOS reports the grant.

Grant behavior:
- The user grants permission manually in System Settings.
- The app does not synthesize clicks, drops, toggles, drags, or TCC changes.

Refresh:
- Returning to SwitchTab refreshes permission state.
- If the permission becomes granted, the Settings permission row updates and the
  blocked-capability copy is replaced by the enabled state.
- If macOS requires relaunch after granting Screen Recording, validation should
  include a relaunch before treating previews as available.

Failure behavior:
- If System Settings cannot open, SwitchTab keeps the missing-permission row
  visible with manual recovery instructions.
- If the user opens Settings but does not grant permission, SwitchTab remains in
  the missing-permission state.

## Finder/Safari/Notes Manual Acceptance Contract

The exact step-by-step actions are in
[quickstart.md](../quickstart.md#application-switching-manual-acceptance-contract).
Run them against a QA build and record one outcome entry per scenario in
`.build/qa/application-switching/outcomes.md`. Each entry MUST include
`precondition`, `exact action`, `expected`, `actual`,
`selected/frontmost app identity`, and `evidence path`; the contract does not
claim these live scenarios have passed.

| Scenario | Required action/result | Evidence path |
| --- | --- | --- |
| 01 | Accessibility granted, replacement off; hold Command and press Tab once; native switcher only | `01-native-off.png` |
| 02 | Enable replacement; repeat Command-Tab; SwitchTab application overlay only | `02-switchtab-on.png` |
| 03 | Finder active; cycle forward with Tab and reverse with Shift-Tab; match distinct highlights to names | `03-forward.png`, `03-reverse.png` |
| 04 | Release Command with a non-Finder app highlighted; verify Computer Use frontmost state | `04-activation-state.txt` |
| 05 | Disable replacement, press Command-Tab for native behavior, then invoke the configured current-app window shortcut and verify its SwitchTab window overlay still appears | `05-disabled-native.png`, `05-window-shortcut-still-active.png` |
| 06 | Revoke Accessibility, enable replacement, verify native fallback/recovery copy, restore access, retry, verify working overlay/cleared warning | `06-permission-fallback.png`, `06-permission-recovered.png` |
| 07 | Leave replacement enabled; quit/relaunch QA build; toggle persists and Cmd+Tab opens SwitchTab | `07-relaunch-persistence.png` |
| 08 | Quit SwitchTab through its menu; press Command-Tab; native behavior restored | `08-quit-native.png` |

For Scenario 05, the `actual` and `selected/frontmost app identity` fields must
cover both the native application switcher and the subsequent current-app
window overlay; the supplementary window-overlay capture is required in
addition to the canonical `05-disabled-native.png` artifact.
