# Quickstart: macOS SwitchTab

## Prerequisites

- macOS 14.0 or later.
- Xcode with Swift 5.10 or later.
- One application with multiple open windows for current-app window validation.
- Finder, Safari, and Notes open for the application-switching acceptance
  contract.
- Accessibility permission for live current-app window focus and Cmd-Tab
  EventTap interception. Screen Recording is optional for application icons and
  names, but required for live current-app window previews.

## Build and Test

1. Open `SwitchTab.xcodeproj` in Xcode.
2. Select the `SwitchTab` scheme.
3. Run the unit tests with `Product > Test`.
4. Launch the app with `Product > Run`.

Expected:
- Unit tests pass.
- A menu bar item appears.
- No overlay appears until a configured shortcut is pressed.
- Fresh installs enable both switcher modes with Cmd+` for current-app windows
  and Cmd+Tab for application switching.

## Permission Validation

1. Launch the app without granting Accessibility permission.
2. Invoke the current-app window switcher.
3. Confirm the app explains the missing permission and gives recovery steps for
   current-app window switching.
4. Open Settings > Shortcut, confirm `Application Switching` is enabled, and
   confirm the application-specific warning explains that Accessibility is
   required for EventTap interception.
5. Press Cmd+Tab and confirm native macOS behavior remains available while the
   EventTap is unavailable.
6. Grant Accessibility permission in macOS Settings, return to SwitchTab, and
   relaunch if macOS requires it.

Expected:
- Missing permission blocks current-app window observation and window focus.
- The enabled application-switching setting remains saved but does not consume
  its configured shortcut until Accessibility is granted and SwitchTab retries
  registration on activation.
- Recovery guidance identifies both the current-app window capability and the
  application EventTap requirement.
- After permission is granted, current-app window switching behavior can proceed.

For window previews:

1. Launch the current-app window switcher without Screen Recording permission.
2. Confirm window rows still show safe fallback content.
3. Open Settings and click Allow on the Screen Recording permission row.
4. Confirm System Settings opens to the Screen & System Audio Recording privacy
   pane, then Finder becomes the final foreground app with the currently running
   SwitchTab.app selected.
5. If macOS requires adding the app, manually drag the selected SwitchTab.app
   from Finder into the matching privacy pane, then enable/grant Screen
   Recording in System Settings.
6. Relaunch the app if macOS requires it.

Expected:
- Missing Screen Recording permission blocks previews only.
- Window switching remains understandable through titles/fallbacks.
- After permission is granted, current window previews appear.
- Application icons and names remain available without Screen Recording.

## System Settings Permission Recovery Scenario

Accessibility:

1. Remove SwitchTab from `System Settings > Privacy & Security > Accessibility`
   or turn the permission off.
2. Launch SwitchTab and open Settings.
3. Click Allow on the Accessibility permission row.
4. Confirm System Settings opens to the Accessibility privacy pane, then Finder
   becomes the final foreground app with the currently running SwitchTab.app
   selected.
5. If macOS requires adding the app, manually drag the selected SwitchTab.app
   from Finder into the matching privacy pane, then enable/grant Accessibility
   in System Settings.
6. Return to SwitchTab and relaunch if macOS requires it.

Expected:
- The Allow action opens the matching pane, reveals the currently running app
  in Finder for drag-and-drop, and leaves Finder as the final foreground app.
- SwitchTab does not toggle or grant permission, alter TCC, install or copy
  itself, or automate clicks, drops, or drag-and-drop.
- Permission state refreshes to granted after the user grants access.

Screen Recording:

1. Remove SwitchTab from `System Settings > Privacy & Security > Screen &
   System Audio Recording` or turn the permission off.
2. Launch SwitchTab and open Settings.
3. Click Allow on the Screen Recording permission row.
4. Confirm System Settings opens to the Screen & System Audio Recording pane,
   then Finder becomes the final foreground app with the currently running
   SwitchTab.app selected.
5. If macOS requires adding the app, manually drag the selected SwitchTab.app
   from Finder into the matching privacy pane, then enable/grant Screen
   Recording in System Settings.
6. Grant permission and relaunch SwitchTab if macOS requests it.

Expected:
- Permission copy references Screen Recording/window previews.
- The Allow action opens the matching pane, reveals the currently running app
  in Finder for drag-and-drop, and leaves Finder as the final foreground app.
- SwitchTab does not toggle or grant permission, alter TCC, install or copy
  itself, or automate the drag.
- Missing permission continues to block previews until macOS reports access.
- If macOS requires relaunch after granting access, relaunch SwitchTab before
  treating preview validation as complete.

## Application Switching Manual Acceptance Contract

Use a QA build with Finder, Safari, and Notes open. Start with Finder active
unless a scenario says otherwise. Fresh installs enable `Application
Switching` with Cmd+Tab; existing installs preserve their previously explicit
enabled state and shortcut. When it is enabled, Accessibility must be granted
so the dedicated EventTap can intercept its forward and reverse shortcuts. Application mode
shows every application icon but reserves its fixed-height caption for the
selected application only. It uses application MRU independently from window
MRU and does not need Screen Recording. Turning the setting off or quitting
SwitchTab must restore native Cmd+Tab.

Application-mode interaction matches the current-app window switcher: repeated
Tab/Shift-Tab and arrow keys move the selection, releasing Command confirms the
highlighted app, and the selected icon has an inset outline. Only the selected
application shows its centered name below the icon. A selected application with
two or more standard windows also shows a window-count glyph/value; zero, one,
or an unknown count shows the name alone. The caption slot remains reserved on
every tile so selection and asynchronous count updates cannot change panel height.
One-, two-, and three-row grids remain stationary when fully visible; only a
grid with real row overflow scrolls to keep the selection visible. Cmd+Q asks
the selected app to terminate normally; its tile stays until
`NSWorkspace.didTerminateApplicationNotification` arrives (including when a
save dialog or rejection keeps the app alive), while the overlay remains open.
Cmd+W and visible close controls apply only to current-app window mode.

Run all eight scenarios exactly as written. For each one, write an entry in
`.build/qa/application-switching/outcomes.md` with these fields; bracketed
values are intentionally left for the live QA executor and are not a pass
claim:

```text
Precondition:
Exact action:
Expected:
Actual:
Selected/frontmost app identity:
Evidence path:
```

### 1. Native Cmd-Tab with application switching disabled

- **Precondition:** Accessibility is granted; Finder, Safari, and Notes are
  open; `Application Switching` is disabled.
- **Exact action:** With Accessibility granted and the toggle off, hold
  Command, press Tab once, capture the native macOS switcher as
  `01-native-off.png`, then release Command; no SwitchTab overlay may appear.
- **Expected:** The native macOS application switcher is visible and no
  SwitchTab application overlay appears.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the native switcher's selected
  app and the frontmost app after release]`
- **Evidence path:** `.build/qa/application-switching/01-native-off.png`

### 2. SwitchTab overlay with application switching enabled

- **Precondition:** Accessibility is granted; Finder, Safari, and Notes are
  open; `Application Switching` is currently disabled.
- **Exact action:** Turn the toggle on, repeat Command-Tab, and capture only the
  SwitchTab application overlay as `02-switchtab-on.png`; the native switcher
  must not appear. Repeat with enough regular apps to produce one-, two-,
  three-row, and overflowing grids at the current display size.
- **Expected:** The SwitchTab application overlay shows every application icon
  while only the selected icon has a centered name below it. A selected app
  shows the window glyph/value only for a count of two or more. The 104-point
  selection container covers the 96-point icon only, uses equal 4-point insets
  and a 26-point radius, and never covers the caption. Long selected names use
  up to 240 points and tail-truncate without clipping at a panel edge. The
  native switcher is not visible.
  Confirm that a fully visible one-, two-, or three-row grid does not move under
  selection, while a grid with actual row overflow scrolls only as needed.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the highlighted app and the
  frontmost app after the interaction]`
- **Evidence path:** `.build/qa/application-switching/02-switchtab-on.png`

### 3. Forward and reverse application MRU

- **Precondition:** Finder is active; Finder, Safari, and Notes are open;
  application switching is enabled; no unrelated app has been selected in the current
  application-switching session.
- **Exact action:** Starting with Finder active and all three apps open, hold
  Command, press Tab repeatedly, then use Shift-Tab and the arrow keys; capture
  distinct forward and reverse highlights as `03-forward.png` and
  `03-reverse.png` and match them to the displayed application names.
- **Expected:** Forward, reverse, and arrow-key movement select distinct
  displayed app names in the application MRU order, with reverse movement
  stepping back one position and arrow navigation matching the window-mode
  selection behavior.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record each highlighted app name and
  the frontmost app after any release]`
- **Evidence path:** `.build/qa/application-switching/03-forward.png`,
  `.build/qa/application-switching/03-reverse.png`

### 4. Command-release activation

- **Precondition:** Application switching is enabled; the application overlay is visible;
  a non-Finder app is highlighted.
- **Exact action:** While a non-Finder app is highlighted, trigger a workspace
  activation without releasing Command and verify the overlay remains visible;
  then release Command. Computer Use app state must report that named app
  frontmost in `04-activation-state.txt`. In a second pass, press Cmd+Q and
  record the selected tile before termination, after any save/rejection, and
  after the app's didTerminate notification.
- **Expected:** Workspace activation while the trigger modifier is held does
  not cancel the overlay. Releasing Command confirms the highlighted
  application through coordinated `activate(from:options:)` using the actual
  frontmost app and `.activateAllWindows`; that application becomes frontmost, and no window
  thumbnail or close action is required. Clicking an application uses the same
  confirmation and activation path. Cmd+Q requests normal termination; the tile remains for a save
  dialog or rejected request and is removed only after didTerminate while the
  overlay stays open for remaining apps. Cmd+W and visible close controls have
  no effect in application mode.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the highlighted name and the
  Computer Use frontmost identity]`
- **Evidence path:** `.build/qa/application-switching/04-activation-state.txt`

### 5. Native Cmd-Tab after disabling application switching

- **Precondition:** Accessibility is granted; application switching is enabled and
  SwitchTab is running; the current-app window shortcut is configured.
- **Exact action:** Return to Settings, turn the toggle off, immediately repeat
  Command-Tab, and capture the native switcher as `05-disabled-native.png`.
  Then press the configured current-app window shortcut and capture the
  SwitchTab window overlay as `05-window-shortcut-still-active.png`; the window
  shortcut must remain registered and operational.
- **Expected:** The application EventTap is torn down and native Cmd+Tab
  appears. The configured current-app window shortcut then opens the SwitchTab
  window overlay for the active application, preserving the existing window
  switching and preview-permission behavior.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the native switcher's selected
  app/frontmost app after release, then the window overlay's owning app and
  selected window]`
- **Evidence path:** `.build/qa/application-switching/05-disabled-native.png`,
  `.build/qa/application-switching/05-window-shortcut-still-active.png`

### 6. Accessibility fallback and recovery

- **Precondition:** Finder, Safari, and Notes are open; SwitchTab is running;
  Accessibility can be changed in System Settings.
- **Exact action:** In System Settings > Privacy & Security > Accessibility, turn
  SwitchTab access off. Enable application switching, return to SwitchTab, and verify
  native Cmd-Tab plus the application-specific recovery copy in
  `06-permission-fallback.png`. Turn access back on, return to SwitchTab to
  trigger retry, and capture the working overlay and cleared warning as
  `06-permission-recovered.png`.
- **Expected:** While access is off, native Cmd+Tab remains available and the
  application-specific warning is shown; after access is restored and retry
  runs, the SwitchTab overlay works and the warning clears.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record identities in fallback and
  recovered states]`
- **Evidence path:** `.build/qa/application-switching/06-permission-fallback.png`,
  `.build/qa/application-switching/06-permission-recovered.png`

### 7. Application-switching persistence across relaunch

- **Precondition:** Application switching is enabled; Finder, Safari, and Notes are open;
  Accessibility is granted.
- **Exact action:** Leave application switching enabled, quit and relaunch the QA build,
  verify the toggle is still on and Command-Tab opens SwitchTab, and save
  `07-relaunch-persistence.png`.
- **Expected:** The toggle remains on after relaunch and Cmd+Tab opens the
  SwitchTab application overlay.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the highlighted and frontmost
  app identities]`
- **Evidence path:** `.build/qa/application-switching/07-relaunch-persistence.png`

### 8. Native Cmd-Tab after quitting SwitchTab

- **Precondition:** Application switching is enabled and SwitchTab is running with
  Finder, Safari, and Notes open.
- **Exact action:** Quit SwitchTab through its menu, press Command-Tab, and
  capture restored native behavior as `08-quit-native.png`.
- **Expected:** SwitchTab's process-owned EventTap is gone and native macOS
  Cmd+Tab behavior is restored.
- **Actual:** `[record during manual QA]`
- **Selected/frontmost app identity:** `[record the native switcher's selected
  app and the frontmost app after release]`
- **Evidence path:** `.build/qa/application-switching/08-quit-native.png`

Do not mark an outcome as passed from the expected text alone. The actual result,
selected/frontmost identity, and evidence path must be captured for every
scenario before a live macOS QA sign-off.

## Overlay Presentation and Selection Behavior Scenario

1. Open Settings from the menu bar item.
2. Confirm settings show shortcut controls and permission status.
3. Invoke the current-app window switcher while the frontmost app has multiple
   windows.
4. Confirm the overlay shows a horizontal icon strip.
5. Move selection with repeated shortcut input or arrow keys.
6. Release the trigger shortcut.

Expected:
- Icon strip uses shortcut-release confirmation by default.
- Selection-behavior controls remain absent from Settings; independent
  `Current App Windows` and `Application Switching` status, toggle, shortcut,
  and reset controls are present under Shortcuts.
- General app preferences such as overlay size may be present.
- Pressing Enter or clicking a visible window target also confirms the selected
  window.
- Releasing the trigger shortcut focuses the selected window.

## Current-App Window Switching Scenario

1. Open one application with at least three windows.
2. Make that application active.
3. Press the configured current-app window shortcut.
4. Use repeated shortcut input or arrow keys to choose a window.
5. Confirm the selection by releasing the trigger shortcut, pressing Enter, or
   clicking the visible target.

Expected:
- Overlay lists only windows from the active application.
- Rows show current window previews when permission allows.
- Selected window becomes focused within 2 seconds of shortcut invocation.
- Clicking a window row, icon, or preview focuses that window.

## Window Edge Case Scenario

1. Put one test window on another display, Space, or full-screen workspace when
   available.
2. Minimize or hide one test target.
3. Close one listed target while the switcher is visible.
4. Invoke the current-app window switcher and select each remaining available
   target.

Expected:
- The overlay stays usable when a target moves, closes, hides, or minimizes.
- Unavailable targets are refreshed away or shown as unavailable without a crash.
- Selecting an available target never focuses an unrelated application.

## Shortcut Settings Scenario

Independent settings validation:

1. Use fake mode actions or a test build that records shortcut dispatch without
   requiring real window targets.
2. Change the current-app window shortcut and confirm the fake window-switch
   action receives the updated shortcut.
3. Try to save an unusable shortcut.

Expected:
- Valid shortcuts are saved as active settings.
- Invalid shortcuts show a specific error.
- Previous valid shortcuts remain active after a failed save.

End-to-end validation:

1. Open shortcut settings from the menu bar app.
2. Change the current-app window shortcut.
3. Try to save an unusable shortcut.

Expected:
- New valid shortcuts invoke their matching modes.
- Invalid shortcuts show a specific error.
- Previous valid shortcuts remain active after a failed save.

## Performance Check

1. Open roughly 20 applications and 50 windows.
2. Invoke the current-app window switcher.
3. Move selection repeatedly with the shortcut and arrow keys.
4. Leave the app idle for 10 minutes.

Expected:
- Overlay appears within 200 ms.
- Selection visibly updates within 100 ms per movement.
- Idle app creates no visible UI activity and no user-noticeable slowdown.

## Historical Validation Notes (Not Application-Switching QA Sign-off)

The entries below are retained baseline records for the existing current-app
window workflow. They do not certify the eight application-switching scenarios
above; those scenarios require fresh live macOS evidence in
`.build/qa/application-switching/outcomes.md`.

Recorded on 2026-07-01:

- Automated SwiftPM runner passed with `swift run SwitchTabTestRunner`.
- SwiftPM package build passed with `swift build`.
- Xcode Debug app build passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' build`.
- The Debug app launched from DerivedData and appeared as the `SwitchTab`
  process.
- Live current-app window switching validation is blocked until Accessibility
  and Screen Recording are granted. Invoking `Cmd+\`` from Safari opened
  SwitchTab Settings with both permission rows marked missing, which is the
  expected blocked-permission path.
- Real launch demo capture is still blocked. Do not treat README or landing
  hero copy as shippable until permissions are granted and the current-app
  window switching, window edge case, and performance scenarios pass in a real
  logged-in macOS UI session.

Recorded on 2026-06-18:

- Automated SwiftPM runner passed with `swift run SwitchTabTestRunner`.
- Xcode project syntax passed with `plutil -lint SwitchTab.xcodeproj/project.pbxproj`.
- Xcode Debug build passed with `xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' build`.
- Xcode test target compilation passed with `xcodebuild -project
  SwitchTab.xcodeproj -scheme SwitchTab -destination
  'platform=macOS,arch=arm64' build-for-testing`.
- `xcodebuild test` compiled the targets but could not load the test bundle in
  this environment because the host app and test bundle were signed with
  different local Team IDs; SwiftPM test runner remains the automated execution
  path for this workspace.
- Service review found no continuous polling constructs in `SwitchTab/Services`.
- Manual current-app window click focusing, shortcut settings end-to-end
  behavior, and macOS permission recovery scenarios still need to be run in a
  real logged-in macOS UI session with Accessibility and Screen Recording
  permissions available.

Recorded on 2026-06-17:

- Automated SwiftPM runner passed with `swift run SwitchTabTestRunner`.
- Xcode project syntax passed with `plutil -lint SwitchTab.xcodeproj/project.pbxproj`.
- `xcodebuild` was not run because the active developer directory is CommandLineTools, not full Xcode.
- Manual current-app window switching, shortcut settings, and macOS permission
  recovery scenarios still need to be run in a real logged-in macOS UI session
  with Accessibility and Screen Recording permissions available.
