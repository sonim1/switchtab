# SwitchTab AI Context

## Product and Platform

- SwitchTab is a native macOS menu-bar utility for keyboard-first window and application switching.
- The supported platform is macOS 14 or later. The codebase uses Swift 6, with Swift 5.10 or later as the package-tools baseline.
- `Package.swift` exposes the model/service code as the `SwitchTab` library and `SwitchTabTests` test target. `SwitchTab.xcodeproj` builds the complete macOS app.
- The product is free: no ads, purchases, subscription, analytics SDK, account, or remote service is required for switching.

## Current User Experience

- Current-app window switching defaults to Command-Backtick. If macOS refuses that reserved shortcut, SwitchTab can register Option-Control-Backtick as a fallback.
- Application switching defaults to Command-Tab. Fresh installs enable both switchers; upgrades preserve an explicit legacy application-switcher choice and otherwise leave application switching off.
- Each mode can be enabled or disabled independently and assigned its own shortcut in Settings > Shortcuts. Shift reverses traversal for the active shortcut.
- Holding the shortcut modifier opens the overlay and repeated presses advance selection. Releasing the modifier confirms the selected window or application; clicking an item confirms it immediately.
- While the modifier stays held, the other mode's key hands the same session to that mode. From application mode it lists the windows of the highlighted application; from window mode it returns to the application list, resumes the application that was left, and advances one step (Shift reverses). The alternate mode is matched on key code alone and only while that mode is enabled and registered.
- Window mode shows standard, visible windows for the current application. Application mode shows eligible running applications in a compact icon strip.
- In application mode, only the selected app shows its centered name below the icon. Its blue selection outline covers the icon tile, not the caption. A window count appears only for apps with at least two standard windows.
- Arrow keys follow the overlay's visual grid. Escape cancels. Command-Q in application mode asks the selected app to quit normally; its tile remains until the process exits.
- Overlay size is user-adjustable. Window thumbnails load asynchronously and improve adaptively without moving selection.

## Architecture

- `SwitchTab/AppDelegate.swift` is the composition root. It owns stores, permission state, hotkey registration, overlay presentation, sessions, and activation handoff.
- `SwitchTab/SwitchTabApp.swift` declares the menu-bar app and replaces the default Command-comma action with SwitchTab's custom settings window.
- `SwitchTab/Models/` contains switcher modes, shortcut values/configurations, application/window items, session state, ordering, and overlay-size values.
- `SwitchTab/Services/HotkeyService.swift` handles the current-app window shortcut. `ApplicationSwitchingHotkeyController.swift` handles application shortcut interception and restores native behavior when it is inactive.
- `AccessibilityWindowProvider.swift` and `RunningApplicationProvider.swift` discover window and application candidates. Filtering policy belongs with discovery/presentation logic, not in SwiftUI views.
- `WindowFocusService.swift` focuses windows; `ApplicationActivationService.swift` activates applications without making SwitchTab the lasting frontmost app.
- `WindowThumbnailService.swift` uses ScreenCaptureKit for previews. `ApplicationIconStore.swift` loads application icons without Screen Recording permission.
- `SwitcherSession.swift`, `SwitcherPresentationSnapshot.swift`, and the overlay state/presentation types hold stable selection while asynchronous content changes.
- `SwitcherRecencyStore.swift` persists separate most-recently-used orderings for window and application modes. `SwitcherModeSwitchMemory.swift` holds one session's per-mode highlight so a mode switch resumes instead of restarting.
- `SwitchTab/UI/Overlay/`, `UI/Settings/`, `UI/MenuBar/`, `UI/Permissions/`, and `UI/About/` own presentation only; reusable behavior should remain SwiftPM-visible in Models or Services.

## Durable Invariants

- Disabling either mode unregisters only that mode. Disabling application switching or quitting SwitchTab must return Command-Tab to macOS immediately.
- If application shortcut interception cannot be installed, keep the saved preference, explain the registration problem, and leave native Command-Tab untouched.
- Opening the overlay does not commit a choice. Commit happens on modifier release or direct click; cancellation must not change focus or MRU order.
- A confirmed window choice focuses that exact window. A confirmed application choice activates the selected application and hands focus away from SwitchTab.
- Window and application MRU histories remain independent. Failed or cancelled activations do not promote an item.
- A mode switch commits nothing: it keeps the panel, the event tap, and the modifiers that opened the session, so releasing them still confirms. A switch that finds no windows, no permission, or an unregistered target mode leaves the live session untouched. Resume memory lives for one held-modifier session and is cleared on dismissal.
- Selection identity is stable across thumbnail/icon updates and candidate refreshes. Presentation updates must not cause panel-height or tile-position jumps.
- In application mode, unselected tiles do not reserve caption space beyond the stable shared layout; the selected caption is centered below its icon.
- Only standard user-facing windows count toward application badges. Hide the badge for zero or one window.
- Accessibility denial must degrade safely; never consume a replacement shortcut when SwitchTab cannot complete its switching action.
- Match existing Swift concurrency isolation. Do not silence isolation failures with `@unchecked Sendable` or `nonisolated(unsafe)`.

## Permissions and Privacy

- Accessibility permission is required to enumerate/focus windows and to complete application switching. Permission state and recovery are coordinated by `PermissionService.swift` and the Permissions UI.
- Screen Recording permission is optional and used only for live window previews. Without it, switching still works with metadata/placeholders.
- Application names and icons do not require Screen Recording permission.
- Permission recovery opens the relevant System Settings destination and waits for activation/state changes; it must not busy-poll or trap the user in a modal flow.
- Do not add telemetry, upload window metadata, or broaden entitlements without an explicit product decision.

## Settings and Persistence

- `ShortcutSettingsStore.swift` persists a versioned configuration for both modes in `UserDefaults`, including enabled state, physical key code, modifiers, usability, and last valid value.
- Shortcut changes are validated for a modifier, duplicate physical keys, and registration availability. Save/register operations are transactional: a failed replacement rolls back to the last working registration.
- Defaults are Command-Backtick for current-app windows and Command-Tab for applications. Their reverse variants add Shift.
- `ApplicationSettingsStore.swift` persists launch-at-login, menu-bar visibility, overlay size, update-check preferences, and migration state.
- Registration errors are persisted per mode so Settings can explain why a saved shortcut is not active.

## Updates and Releases

- The checked-in Xcode project is Sparkle-free. `scripts/build-direct-distribution.sh` creates a separate Sparkle-enabled workspace under `.build/direct-distribution/`.
- Direct releases are signed and notarized, then published as immutable versioned DMG, checksum, manifest, and appcast assets. R2 publication uses conditional writes; GitHub Releases and Homebrew are downstream consumers.
- Pull-request CI owns version preparation. Default is a patch bump; `release:minor` or `release:major` labels select a larger bump. Documentation-only changes do not change the product version or trigger a release.
- Never commit signing, notarization, R2, Sparkle, GitHub, or Cloudflare credentials. Keep the existing split between local keychain profiles and CI's temporary keychain.
- Live procedures are authoritative in `docs/direct-distribution.md`, `docs/update-hosting.md`, `docs/release-workflow.md`, and `docs/repository-maintenance.md`.

## Verification

Run fast library verification:

```bash
swift build
swift test
```

Run the complete unsigned app build when Xcode is available:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

For documentation/release-tooling changes, run every contract and syntax check:

```bash
for test_script in scripts/tests/*-test.sh; do bash "$test_script"; done
for script in scripts/*.sh scripts/tests/*.sh; do bash -n "$script"; done
SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
```

- A successful build proves compilation, not macOS permission-dependent behavior. Runtime claims require testing the built app with Accessibility permission and, for previews, Screen Recording permission.
- Manual switching checks should cover Finder, Safari, and another multi-window app; forward/reverse traversal; release and click confirmation; Escape cancellation; both permission states; shortcut enable/disable; and restoration of native Command-Tab.
- New model/service behavior belongs in `SwitchTabTests/`. Legacy static `run()` suites must be registered in `SwitchTabTests/TestRunner.swift`; native `XCTestCase` methods are auto-discovered.

## Documentation Routing

- Read this file before repository work; it is the compact statement of current truth.
- Read only the relevant feature section of `docs/PROJECT_HISTORY.md` when a task needs prior decisions, rationale, changed requirements, superseded approaches, or release evidence.
- Use `README.md` for public product behavior and setup. Use the focused live runbooks under `docs/` for development, distribution, updates, release operations, and maintenance.
- Prefer current source, tests, and live runbooks over historical conclusions when they disagree. Exact retired plans remain recoverable from Git using the archive index in `docs/PROJECT_HISTORY.md`.
