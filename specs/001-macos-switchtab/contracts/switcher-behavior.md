# Contract: Switcher Behavior

Current repository scope (2026-07-12): this contract covers the checked-in
current-app window switcher. App-level switching is not implemented in the
current app target.

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

## Shortcut Settings

Trigger:
- User opens settings from the menu bar item or app UI.

Behavior:
- User can edit the current-app window shortcut.
- Settings show shortcut controls and permission status.
- Switcher mode and selection-behavior controls are absent from Settings.
- General app preferences such as overlay size may be present.
- Saving validates usability.
- Invalid or unusable shortcuts display a specific error.
- A rejected shortcut never replaces the last valid shortcut.

## Permission Guidance

Accessibility missing:
- App explains that window observation and window focus require Accessibility access.
- App shows recovery steps for macOS Settings.
- Current-app window switching actions remain blocked until access is granted.

Screen Recording missing:
- App explains that window previews require Screen Recording access.
- App still shows window titles when available.
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
