# Quickstart: macOS Window Switcher

## Prerequisites

- macOS 14.0 or later.
- Xcode with Swift 5.10 or later.
- Several open applications for app-switching validation.
- One application with multiple open windows for current-app window validation.

## Build and Test

1. Open `WindowSwitcher.xcodeproj` in Xcode.
2. Select the `WindowSwitcher` scheme.
3. Run the unit tests with `Product > Test`.
4. Launch the app with `Product > Run`.

Expected:
- Unit tests pass.
- A menu bar item appears.
- No overlay appears until a configured shortcut is pressed.

## Permission Validation

1. Launch the app without granting Accessibility permission.
2. Invoke the app-level switcher and activate another application.
3. Invoke the current-app window switcher.
4. Confirm the app explains the missing permission and gives recovery steps for
   current-app window switching.
4. Grant Accessibility permission in macOS Settings.
5. Relaunch the app if macOS requires it.

Expected:
- App-level switching can still activate another app when macOS allows native
  AppKit activation.
- Missing permission blocks current-app window observation and window focus.
- Recovery guidance is clear.
- After permission is granted, current-app window switching behavior can proceed.

For window previews:

1. Launch the current-app window switcher without Screen Recording permission.
2. Confirm window rows still show safe fallback content.
3. Grant Screen Recording permission in macOS Settings.
4. Relaunch the app if macOS requires it.

Expected:
- Missing Screen Recording permission blocks previews only.
- Window switching remains understandable through titles/fallbacks.
- After permission is granted, current window previews appear.

## Permission Drag Overlay Scenario

Accessibility:

1. Remove SwitchTab from `System Settings > Privacy & Security > Accessibility`
   or turn the permission off.
2. Launch SwitchTab and open Settings.
3. Click Allow on the Accessibility permission row.
4. Confirm System Settings opens to the Accessibility privacy pane.
5. Confirm a helper panel appears near the permission list with a draggable
   SwitchTab row.
6. Drag the SwitchTab row into the System Settings list and enable it if macOS
   requires a toggle.
7. Return to SwitchTab.

Expected:
- Helper panel placement follows the System Settings window when it can be
  located.
- Dragging uses the actual SwitchTab app bundle.
- SwitchTab does not perform automatic clicks, drops, or toggles.
- Permission state refreshes to granted after the user grants access.

Screen Recording:

1. Remove SwitchTab from `System Settings > Privacy & Security > Screen &
   System Audio Recording` or turn the permission off.
2. Launch SwitchTab and open Settings.
3. Click Allow on the Screen Recording permission row.
4. Confirm System Settings opens to the Screen & System Audio Recording pane.
5. Drag the SwitchTab row from the helper panel into the System Settings list.
6. Grant permission and relaunch SwitchTab if macOS requests it.

Expected:
- Helper copy references Screen Recording/window previews.
- Missing permission continues to block previews until macOS reports access.
- Relaunch guidance appears when macOS requires restart for capture access.

Fallback placement:

1. Move or close System Settings immediately after clicking Allow.
2. Wait for the bounded lookup to time out.

Expected:
- Helper appears in a safe fallback position instead of hanging.
- Closing the helper leaves Settings usable and keeps manual recovery available.
- No background lookup continues after timeout or dismissal.

## App-Level Switching Scenario

1. Open at least three applications.
2. Press the configured app-level shortcut.
3. Type part of an application name.
4. Use arrow keys to choose a result.
5. Confirm the selection.
6. Reopen the app switcher and click another application row.

Expected:
- Overlay appears within 200 ms.
- Selection responds without visible lag.
- Selected application becomes active within 2 seconds of shortcut invocation.
- Clicking an application icon activates that application.
- Escape dismisses the overlay without changing focus.

## App Presentation and Selection Behavior Scenario

Icon strip presentation:

1. Open Settings from the menu bar item.
2. Confirm settings show shortcut controls and permission status.
3. Invoke the app switcher.
4. Confirm the overlay shows a horizontal app-icon strip.
5. Move selection with repeated shortcut input or arrow keys.
6. Release the trigger shortcut.

Expected:
- Icon strip uses shortcut-release confirmation by default.
- Presentation and selection-behavior controls are absent from Settings.
- Pressing Enter or clicking an app icon also confirms the selected app.
- Releasing the trigger shortcut activates the selected app.

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
   requiring real app/window targets.
2. Change the app-level shortcut and confirm the fake app-switch action receives
   the updated shortcut.
3. Change the current-app window shortcut and confirm the fake window-switch
   action receives the updated shortcut.
4. Try to save a duplicate or unusable shortcut.

Expected:
- Valid shortcuts are saved as active settings.
- Invalid shortcuts show a specific error.
- Previous valid shortcuts remain active after a failed save.

End-to-end validation:

1. Open shortcut settings from the menu bar app.
2. Change the app-level shortcut.
3. Change the current-app window shortcut.
4. Try to save a duplicate or unusable shortcut.

Expected:
- New valid shortcuts invoke their matching modes.
- Invalid shortcuts show a specific error.
- Previous valid shortcuts remain active after a failed save.

## Performance Check

1. Open roughly 20 applications and 50 windows.
2. Invoke each switcher mode.
3. Type several filter characters quickly.
4. Leave the app idle for 10 minutes.

Expected:
- Overlay appears within 200 ms.
- Filtering visibly updates within 100 ms per character.
- Idle app creates no visible UI activity and no user-noticeable slowdown.

## Validation Results

Recorded on 2026-07-01:

- Automated SwiftPM runner passed with `swift run WindowSwitcherTestRunner`.
- SwiftPM package build passed with `swift build`.
- Xcode Debug app build passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug -destination 'platform=macOS,arch=arm64' build`.
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

- Automated SwiftPM runner passed with `swift run WindowSwitcherTestRunner`.
- Xcode project syntax passed with `plutil -lint WindowSwitcher.xcodeproj/project.pbxproj`.
- Xcode Debug build passed with `xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug -destination 'platform=macOS,arch=arm64' build`.
- Xcode test target compilation passed with `xcodebuild -project
  WindowSwitcher.xcodeproj -scheme WindowSwitcher -destination
  'platform=macOS,arch=arm64' build-for-testing`.
- `xcodebuild test` compiled the targets but could not load the test bundle in
  this environment because the host app and test bundle were signed with
  different local Team IDs; SwiftPM test runner remains the automated execution
  path for this workspace.
- Service review found no continuous polling constructs in `WindowSwitcher/Services`.
- Manual app-level list/icon-strip switching, current-app window click focusing,
  shortcut settings end-to-end behavior, and macOS permission drag overlay
  scenarios still need to be run in a real logged-in macOS UI session with
  Accessibility and Screen Recording permissions available.

Recorded on 2026-06-17:

- Automated SwiftPM runner passed with `swift run WindowSwitcherTestRunner`.
- Xcode project syntax passed with `plutil -lint WindowSwitcher.xcodeproj/project.pbxproj`.
- `xcodebuild` was not run because the active developer directory is CommandLineTools, not full Xcode.
- Manual app-level switching, current-app window switching, shortcut settings, and macOS permission recovery scenarios still need to be run in a real logged-in macOS UI session with Accessibility and Screen Recording permissions available.
