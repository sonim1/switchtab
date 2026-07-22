# SwitchTab Full Code Review (2026-07-02)

A macOS menu bar window-switching app for switching between windows in the current app with Cmd+`. The project has parallel Swift 6 SPM and Xcode configurations.
The complete source is approximately 5,500 lines with 30 test suites. All tests passed with `swift run SwitchTabTestRunner`.

## Overall Assessment

The architecture is very good. Protocol-based dependency injection is applied consistently, with Registrar, Provider, Capturer, and Persisting types all abstracted behind protocols.
Policy logic is separated into pure `*Policy` types and is easy to test. The approach of excluding Sparkle from the default target and patching it in through a build script is also clean.
The findings below are ordered by priority.

---

## 🔴 Correctness Bugs (Recommended Priority Fixes)

### 1. Unstable Window Identifiers Break Recency Ordering

`AccessibilityWindowProvider.swift:93` — `windowIdentifier = pid * 10_000 + (filtered array index)`.

- `WindowItem.id` (`"pid-identifier"`) is determined by the window's position in the list. Closing one window or changing the AX order shifts the IDs of all following windows.
- `SwitcherRecencyStore` persists these IDs in UserDefaults, so relaunching the app or changing the window list can bring the wrong window to the front. Reused process IDs can also collide with windows from another app.
- Resolution: Use a stable window ID. Options include: ① promote `CGWindowID` (`screenCaptureIdentifier`) to the primary key; ② use the private `_AXUIElementGetWindow` API, which is not allowed in the App Store; or ③ at minimum, combine the app bundle ID and window title for the recency key.

### 2. Selecting a Minimized Window Does Nothing

`WindowItem.swift:37` — `canFocus = availability == .available && !isMinimized`.
`WindowFocusService` silently returns `.unavailableTarget` for a minimized window. The window appears in the overlay but selecting it has no effect, which looks like a bug to the user.
Resolution: Set `kAXMinimizedAttribute` to false to restore the window before focusing it, matching standard app-switcher behavior.

### 3. Key-Code Table Is Hardcoded for ANSI/QWERTY

`ShortcutSetting.swift:1-230` — the keyCode-to-character mapping is fixed to the US layout. The display label and actual key do not match on non-QWERTY layouts such as AZERTY, Dvorak, and European ISO layouts, although the Korean input layout is unaffected.
Use `UCKeyTranslate` with `TISCopyCurrentKeyboardLayoutInputSource` for dynamic conversion.

### 4. Metrics and Recency Are Saved Only During Normal Termination

Both `UsageMetricsStore` and `SwitcherRecencyStore` call `flush()` only from `applicationWillTerminate`.
Menu bar apps are frequently force-quit, terminated after a crash, or killed during logout, making data loss likely.
Resolution: Flush when dismissing the overlay or add a short debounce before flushing. The cost is negligible.

### 5. Thumbnail-to-Window Matching Heuristic Can Mismatch

`AccessibilityWindowProvider.swift:313-395` — AX windows and CGWindows are matched by title string, with an order-based fallback when matching fails.
If multiple windows have no title, a thumbnail from a different window can be attached. The code comments already acknowledge this limitation.
Resolving finding 1 with a stable CGWindowID removes this heuristic entirely; both findings have the same root cause.

---

## 🟡 Security and Distribution

### 6. Event-Tap Fallback Intercepts Every keyDown in the Session

`HotkeyService.swift:180-261` — if Carbon registration fails, `CGEvent.tapCreate(.cgSessionEventTap, .defaultTap)` actively filters every keyDown event.
Only registered hotkeys are consumed, and all other events pass through, so the behavior is correct. However:

- The callback userInfo uses `Unmanaged.passUnretained(self)`. If the registrar is released while the tap is active, this can cause a use-after-free. The registrar currently lives for the app's lifetime, so it is not an immediate problem, but adding `deinit { unregisterAll() }` is recommended.
- Security tools such as EDR products can flag an active event tap as a keylogger pattern. Non-hotkey events pass through immediately, so there is no material risk, but the behavior is worth documenting.

### 7. The App Store Distribution Path Is Structurally Blocked

The entitlements file is empty for “App Store-oriented builds,” while the app core controls windows in other apps through AX APIs such as `AXUIElementPerformAction` and `AXUIElementSetAttributeValue`. These APIs do not work in the App Store's required sandbox.
In practice, this app is limited to direct distribution through DMG and Sparkle. Either remove App Store support from the stated goal or decide now to retain it, because the choice changes future priorities.

### 8. Sparkle Configuration Is Sound

Requiring an EdDSA public key, enforcing an HTTPS feed, and planning to keep the private key outside the repository are all correct.
The notarization, appcast-signing, R2, and GitHub release automation was implemented on 2026-07-21. Live credential-backed validation remains outstanding.

### 9. Debug Log Grows Without Limit

`AppDelegate.swift:367-393` — `~/Library/SwitchTabDebug.log` is append-only and has no rotation.
Although the log is limited to DEBUG builds, it records running app names and process IDs. Add a size limit or move to `os_log` unified logging.
Opening and closing a `FileHandle` for every call is also wasteful.

The rest of the security surface is sound: Sparkle is the only network dependency, UserDefaults is the only storage mechanism, and no input-validation issues were found.

---

## 🟢 Refactoring and Code Quality

| Location | Finding |
|---|---|
| `HotkeyService.swift:95` | `registeredSetting(for mode:)` ignores the `mode` parameter and always returns `registeredWindowSetting`. Adding another mode would silently return the wrong value. |
| `ShortcutSetting.swift` (748 lines) | The file is too large. Move the approximately 230-line `ShortcutKeyCodeResolver` table into a separate file. |
| `AXWindowElementRegistry.shared` | This is hidden global coupling: Provider writes to it and FocusService reads from it. Passing it explicitly with the snapshot would make the data flow easier to follow. |
| `SwitcherOverlayController.swift:97` | Placement is based on `NSScreen.main`. On multiple monitors, the overlay can appear on the wrong screen when the frontmost app is elsewhere. Prefer the screen containing the frontmost window or mouse pointer. |
| `UsageMetricsStore.swift:102` | `windowUsageStorageKey(dayKey:)` ignores its parameter and returns a cached value. It works only because `dayKey(for:)` clears the cache first, creating a fragile implicit ordering dependency. |
| Test runner | The custom runner works well, but location and diff reporting are weak when a test fails. Consider migrating to swift-testing (`@Test`), which is immediately available with SPM 6.0. |

## Strengths

- Clear Model, Service, UI, and Policy layer separation. Pure policy functions provide meaningful test coverage.
- Every external dependency, including AX, ScreenCaptureKit, Carbon, UserDefaults, and NSWorkspace, is behind a protocol.
- The thumbnail pipeline includes generation-based cancellation, a decode cache, and skips `objectWillChange` when nothing changed, showing good performance awareness.
- Carbon-first registration with an event-tap fallback provides redundancy, while reserved-shortcut failures fall back to another shortcut with a user-facing message.

---

## Recommended Next Steps (Priority Order)

1. ~~**Introduce stable window identifiers**~~ ✅ Completed (2026-07-02) — added `PrivateAXWindowNumberResolver` based on `_AXUIElementGetWindow`.
   `CGWindowID` is used directly for `windowIdentifier` and `screenCaptureIdentifier`, with the previous index-based approach as a fallback.
   The title-based thumbnail matching heuristic remains only in the fallback path. This resolves bugs 1 and 5.
2. ~~**Restore minimized windows**~~ ✅ Completed — `canFocus` now includes minimized windows, and `AXWindowFocuser` clears `kAXMinimizedAttribute` before focusing. This resolves bug 2.
3. ~~**Finish release automation**~~ ✅ Completed (2026-07-21) — notarization, appcast signing, atomic R2 publication, and tag-driven GitHub releases are automated.
   Live validation still requires the Sparkle private key, Developer ID certificate, scoped Cloudflare/R2 credentials, and approval to mutate the external services.
4. ~~**Improve flush durability**~~ ✅ Completed — recency and usage data are flushed immediately when a window selection is confirmed. This resolves bug 4.
5. **Support keyboard layouts** — not started. Dynamic mapping based on `UCKeyTranslate` is required before accepting international users.
6. ~~**Place the overlay correctly on multiple monitors**~~ ✅ Completed — the overlay appears on the screen containing the pointer, with an `activeScreenFrame` policy and tests.
7. **Finalize the distribution strategy** — decide whether to abandon the App Store. The newly introduced private `_AXUIElementGetWindow` API confirms that App Store submission is not possible, in addition to the existing sandbox limitation.

## Changes Completed on 2026-07-02

- Stable window IDs in `AccessibilityWindowProvider.swift`, ensuring correct recency ordering.
- Minimized-window restoration in `WindowItem.swift` and `WindowFocusService.swift`.
- Immediate flush on selection in `AppDelegate.swift`.
- Event-tap cleanup in `EventTapHotkeyRegistrar.deinit`, preventing a use-after-free through the unretained self pointer.
- Mode-specific dictionary storage in `HotkeyService.registeredSetting(for:)`.
- A 1 MB debug-log size limit that starts a new log after the limit is exceeded.
- Multi-monitor overlay placement based on the pointer's screen.
- `ShortcutKeyCodeResolver` moved to a separate file, reducing 748 lines to 510 plus 237 lines, and registered in the Xcode project.
- Six new tests; all test suites pass. Direct-distribution script patching passes `--prepare-only` validation.
- `_AXUIElementGetWindow` symbol availability confirmed on this machine.
