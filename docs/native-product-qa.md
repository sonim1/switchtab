# Native product QA

These fixtures exercise real AppKit/SwiftUI surfaces without creating user documents. They are excluded from the shipping app and SwiftPM products. The app build, actual native input and view-state simulation prove different things; record which one a result uses.

## Build and inspect view states

```bash
rtk proxy scripts/run-native-view-fixture.sh
```

Use the fixture menu for both denied permissions, either denied permission, granted permissions, About and light/dark appearance. The full production Settings view uses an isolated preferences suite and a fake login service. The update section is absent because the fixture does not inject Sparkle.

Do not change host permissions through this fixture: its Allow buttons retain the production System Settings/Finder recovery action. Rendering a denied state does not revoke TCC. About's support/acknowledgment callbacks are inert in the fixture; use the real app to verify those entries.

Check full inline recovery paths, independent Allow buttons, readable Enabled/error text, slider Increment/Decrement, toggle round trips, original restored values and keyboard/AX access. The fixture owner cancels recording when its Settings window closes.

Use `--build-only` to compile without opening a window. Unknown or extra options exit 64 before a build or launch.

## Build owned switching windows

```bash
rtk proxy scripts/run-native-window-fixture.sh
rtk proxy osascript -e 'tell application "System Events" to get unix id of first application process whose name is "SwitchTabSecurityQA"'
```

The fixture creates three disposable standard windows named SwitchTab Security QA A/B/C, a text field, a local Command-K probe and a Carbon Control-Option-F12 oracle. A successfully registered oracle plus an actual increment from external input verifies the input path. Pressing Verify probe handler checks only the handler and is not evidence of global delivery.

Run a signed SwitchTab candidate with the same existing identity/path when testing established permissions. Preserve the installed bundle and relevant preferences first. Record source commit, binary hash, signature, permissions and original shortcuts. An unsigned app build is compilation evidence, not a replacement for this runtime check.

## Bounded global scenarios

The driver uses AppleScript/System Events and requires an already-authorized native-input environment. It does not grant permissions. Supply the live owned fixture PID obtained above; validate it rather than guessing a PID. Both shortcuts must be enabled with Cmd-Backtick and Cmd-Tab for these scenarios. Close SwitchTab Settings/About before running overlay scenarios so their windows are not confused with the overlay.

```bash
rtk proxy osascript SwitchTabQA/native-flow-qa.applescript "$SWITCHTAB_QA_PID" window-nav-cancel
rtk proxy osascript SwitchTabQA/native-flow-qa.applescript "$SWITCHTAB_QA_PID" app-nav-cancel
rtk proxy osascript SwitchTabQA/native-flow-qa.applescript "$SWITCHTAB_QA_PID" mode-handoff
rtk proxy osascript SwitchTabQA/native-flow-qa.applescript "$SWITCHTAB_QA_PID" window-return
```

The driver checks the process name before changing input. It captures actual AX values and model IDs, sends bounded key sequences, restores modifiers on success/failure and checks the owned main window for cancellation. It must not be pointed at a user's app. For a minimized scenario, first minimize one owned fixture window with a native UI action, then run `minimized-return` and verify AXMinimized=false and the exact restored main window.

Run `app-click-owned-view` while the view fixture is open to verify exact cross-app activation. `close-owned-window` sends Cmd-W only after confirming the selected ID belongs to the owned PID. Confirm just that target disappears. Run `quit-owned-app` last: it checks the selected app ID against the owned process bundle ID and requests normal termination. Confirm the PID is gone and its tile is removed. Relaunch the fixture to repeat after destructive scenarios.

Inspect screenshots separately for visual selection, thumbnails, captions and clipping. Text dumps are not screenshots. CUA can coalesce static text; use original native attributes before diagnosing a flattened hierarchy. Rebind after hiding/closing the selected window. Ensure a menu action has actually opened its window before issuing the next action.

## Window lifecycle and Practice

1. Start recording, close Settings, test both global shortcuts, reopen and verify no Recording state. Test Escape, cross-row ownership, rejection and successful registration/reset.
2. Open Settings and About together. Close each first in separate runs. The remaining window must retain regular policy; only the last close returns accessory. Repeat show requests and Practice hiding.
3. Activate an owned window before opening How to Use. Begin Practice, switch an exact owned window, let verification finish and reopen the guide. Verify completion; repeat with Escape and verify cancellation.
4. Confirm healthy permissions on the real app, all four simulated combinations in the fixture, update dialog open/close and General scrolling.

Record actual source/build and after-state for every row. Failed acquisition, expired held-input helpers and in-process AX limitations are tool failures or inconclusive observations, not product bugs. Correct and repeat before claiming a pass.

## Cleanup and limits

Release Command/Shift/Control/Option, close only owned fixtures and verify no helper process remains. Restore the exact public app bundle and the values changed by the test. Restore only owned preference changes; never import an entire old domain over concurrent user changes. Address the direct preferences path explicitly when macOS defaults tooling redirects a bundle identifier to an App Store container.

Do not claim VoiceOver speech, TCC revocation/relaunch, actual login registration, saved-document quit refusal, other OS versions or multiple displays from these fixtures. Record those as separate verification work. Baseline and final logs belong in an ignored local evidence directory; the audit report contains sanitized conclusions.
