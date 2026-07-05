# Contract: Switcher Behavior

## App-Level Switching

Trigger:
- User presses the configured app-level shortcut.

Preconditions:
- The app is running.
- The configured shortcut is usable.

Visible result:
- Overlay appears within 200 ms.
- Overlay shows a horizontal strip of app icons and readable selected-app
  context.
- Keyboard focus is inside the overlay.

Keyboard behavior:
- Repeated shortcut input or arrow keys move selection across the strip.
- Releasing the trigger shortcut confirms the highlighted application.
- Enter also confirms the highlighted application.
- Escape cancels without changing focus.

Pointer behavior:
- Clicking an application icon confirms that application through the same path
  as keyboard confirmation.

Completion:
- Selected application becomes active.
- Activation brings the selected application to the foreground when macOS
  allows it.
- Overlay closes.
- If the target closes before confirmation, the overlay refreshes or shows a
  recoverable unavailable-target message.

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
- User can edit app-level and current-app window shortcuts independently.
- Settings show shortcut controls and permission status.
- Presentation and selection-behavior controls are absent from Settings.
- Saving validates uniqueness and usability.
- Invalid or unusable shortcuts display a specific error.
- A rejected shortcut never replaces the last valid shortcut.

## Permission Guidance

Accessibility missing:
- App explains that window observation and window focus require Accessibility access.
- App shows recovery steps for macOS Settings.
- Current-app window switching actions remain blocked until access is granted.
- App-level switching through AppKit activation remains available when macOS
  allows it.

Screen Recording missing:
- App explains that window previews require Screen Recording access.
- App still shows window titles when available.
- App shows recovery steps for macOS Settings.

## Permission Drag Overlay

Trigger:
- User clicks Allow from a missing Accessibility or Screen Recording permission
  row in Settings.

Preconditions:
- The app is running as SwitchTab.
- The selected permission is missing.
- The current app bundle URL is available.

Visible result:
- The matching macOS Settings privacy pane opens.
- A floating helper panel appears near the visible System Settings permission
  list when the Settings window can be located.
- If the Settings window cannot be located within the bounded lookup window, the
  helper appears in a safe fallback position on the active screen.
- The helper shows permission-specific instruction text and a draggable
  SwitchTab app row.

Drag behavior:
- Drag begins only from the user's pointer gesture on the SwitchTab row.
- The drag pasteboard contains the SwitchTab app bundle file URL.
- The advertised operation is copy.
- The user drops the row into System Settings manually.
- The app does not synthesize clicks, drag movement, drops, or permission
  toggles.

Dismissal and refresh:
- Closing the helper dismisses the active permission assist session.
- Returning to SwitchTab refreshes permission state.
- If the permission becomes granted, the Settings permission row updates and the
  helper is dismissed.
- If macOS requires relaunch after granting Screen Recording, the app tells the
  user to relaunch instead of assuming previews are immediately available.

Failure behavior:
- If System Settings cannot open, SwitchTab keeps the missing-permission row
  visible with manual recovery instructions.
- If the user drags the row but does not grant permission, SwitchTab remains in
  the missing-permission state.
- The helper never blocks the rest of Settings or traps keyboard focus.
