# SwitchTab Permission Drag Helper Design

Date: 2026-07-26
Status: Approved direction; OMO implementation plan next

## Goal

Replace the current `Allow -> System Settings -> Finder with SwitchTab.app
selected` permission-recovery flow with the screenshot-style flow requested by
the user:

1. Open the matching macOS Privacy & Security pane.
2. Keep System Settings in front.
3. Show a compact SwitchTab-owned helper panel near the bottom of that window.
4. Let the user drag the running `SwitchTab.app` from the helper into the
   privacy list.

The same helper is used for missing Accessibility and Screen Recording
permissions, with permission-specific copy.

## Non-Goals

- Do not grant, toggle, or modify TCC permissions programmatically.
- Do not synthesize a mouse drag, drop, click, or keyboard event in System
  Settings.
- Do not inspect or depend on the private System Settings view hierarchy.
- Do not add a dependency, entitlement, preference, or second recovery button.
- Do not continuously poll for permission changes or System Settings windows.
- Do not alter unrelated release, distribution, shortcut, or update work already
  present in the dirty worktree.

## Chosen Approach

Use a non-activating AppKit `NSPanel` containing a SwiftUI helper view and a
small AppKit drag-source view.

This is preferred over a normal SwiftUI window because the helper must remain
visible while System Settings is active and must not pull the user away from
the drop target. It is preferred over the existing Finder reveal because it
removes the window-switching step and directly presents the app bundle beside
the destination list.

The drag payload is the real file URL returned by `Bundle.main.bundleURL`,
written as an `NSURL`/file-URL pasteboard item. The destination still decides
whether to accept it, and the user remains the only actor performing the drag
and privacy change.

## User Experience

When either missing permission row's existing `Allow` button is clicked:

1. SwitchTab opens the corresponding `PermissionSettingsDestination` URL.
2. It waits for the exact System Settings process returned by AppKit to become
   active, reusing the existing race-safe activation boundary.
3. It performs a short, bounded lookup for an on-screen, normal-layer window
   owned by that process.
4. It shows one helper panel, positioned inside the lower portion of the System
   Settings window and clamped to the owning display's visible frame.
5. The helper says
   `Drag SwitchTab into the list above if it is not listed, then enable <permission>.`
   and renders one app tile with the current app icon and display name.
6. Dragging the tile begins a standard external file drag with copy semantics.
7. The helper remains visible after a cancelled or completed drag so macOS can
   display any required Quit & Reopen prompt without SwitchTab guessing whether
   the drop succeeded.

The close button dismisses only the helper. System Settings remains open. A
second `Allow` click reuses the existing panel and updates its permission copy
instead of creating another window.

No permission polling is added. Existing app-activation refresh behavior remains
the source of truth when the user returns to SwitchTab. The helper dismisses
when SwitchTab becomes active again, System Settings terminates or stops being
frontmost, the permissions view disappears, or the user closes the helper.

## Architecture

### Permission recovery coordinator

Refactor the existing Finder-oriented implementation in
`PermissionSettingsDestination.swift` so the coordinator owns only the
race-safe System Settings open/activation sequence and delegates presentation
to a small injected protocol.

The coordinator captures `Bundle.main.bundleURL` once per invocation, opens the
requested destination, waits only for bounded activation/placement work, and
asks the presenter to show a `PermissionRecoveryPresentation` value. Finder
selection and activation are removed from the normal flow.

### System Settings window locator

Use `CGWindowListCopyWindowInfo` with the process identifier returned by the
System Settings open operation. Consider only on-screen, normal-layer windows
with usable bounds and select the largest candidate. Do not rely on localized
window titles or Accessibility inspection.

Lookup is bounded to at most ten attempts separated by 100 milliseconds because
System Settings may publish its window shortly after activation. It stops as
soon as a candidate is found, the one-second budget expires, the session is
superseded, or the task is cancelled. The delay boundary is injected for tests
and never blocks the main thread.

If no candidate is found, the helper still appears at the bottom-center of the
active screen. Failure to locate the exact frame must not send the user back to
Finder or block manual recovery.

### Layout policy

Keep coordinate conversion and placement calculation pure and testable. Quartz
window bounds use an upper-left origin relative to the primary display, while
AppKit window frames use a lower-left origin. The conversion uses the current
primary display height from `NSScreen.screens.first`, preserves negative X/Y
coordinates, and does not apply a backing-scale conversion because the window
bounds are already expressed in points.

Placement inputs are the converted optional System Settings window frame,
visible screen frames, a preferred panel size of 560 by 144 points, a 24-point
bottom inset, and a 24-point horizontal safety margin. The output is centered
horizontally over the target window, shrunk only when necessary, and clamped to
the visible frame of the display with the largest intersection. Without a
target frame, it uses the source SwitchTab settings window's display captured at
click time, then the primary display as the final fallback.

The policy makes no hard-coded assumption about display origin, scale,
language, Dock position, or sidebar width.

### Helper panel

`PermissionRecoveryPanelController` retains a single borderless,
non-activating `NSPanel` backed by `NSHostingView`. The panel:

- does not become the foreground application;
- remains visible while SwitchTab is inactive;
- has a transparent window background and a native material/card treatment;
- uses `.floating` level and `orderFrontRegardless()` without attempting to
  attach itself as a cross-process child window;
- joins the active Space but does not introduce global always-on-top behavior
  after the recovery session ends;
- is explicitly dismissed and releases any in-flight work.

The controller is retained by the existing permissions settings panel and is
injected into the recovery coordinator through a presentation protocol. This
keeps window lifetime explicit and makes coordinator tests independent of a
real AppKit window.

Only one recovery session may exist. Each `Allow` click increments a generation
identifier, cancels the prior lookup, and updates or presents the same panel.
Callbacks from an older generation are ignored so a late timeout or activation
event cannot dismiss or reposition a newer session. Showing, closing, and
starting a drag must leave the exact System Settings process as
`NSWorkspace.frontmostApplication`.

### Drag source

Use an `NSViewRepresentable` backed by a focused `NSView` subclass. Once the
mouse moves far enough to constitute a drag, it starts
`beginDraggingSession(with:event:source:)` with one `NSDraggingItem` whose
pasteboard writer is the running app bundle URL. The source advertises `.copy`.

The drag image is the same app icon/name tile shown in the helper. A click with
no drag has no side effect. The implementation does not use file promises,
aliases, the inner executable path, or a hard-coded `/Applications` location.

## Error and Edge-Case Handling

- If the deep link opens System Settings but not the exact pane, show the helper
  with permission-specific manual navigation text available in the existing
  permission model.
- If AppKit reports that System Settings failed to open, place the helper on the
  active screen only if System Settings is already running; otherwise leave the
  existing Settings UI usable and record the failure in debug logging.
- If SwitchTab is not running from an existing file URL whose extension is
  `.app`, do not construct a fake drag payload or show a draggable tile. Record
  the failure in debug logging and leave the existing permission instructions
  usable.
- Moving or re-signing the application can change macOS privacy identity. The
  helper always exposes the currently running bundle and does not copy or
  install it.
- A successful drop may require macOS to quit and reopen SwitchTab. The helper
  does not suppress or replace that system prompt.
- The permission API cannot distinguish an app that is absent from the list
  from one that is listed but disabled. Copy therefore tells the user to drag
  SwitchTab if it is absent, then enable it and follow any macOS relaunch prompt.
- Keep the existing Swift language/build settings. A Swift language-mode
  migration is outside this feature.

## Testing

Automated tests will cover:

- selection of the exact System Settings process and rejection of wrong-PID
  activation events;
- bounded locator success, timeout, and cancellation;
- deterministic layout on normal, small, offset, and multi-display frames;
- presentation values and permission-specific copy for both permission rows;
- one captured app bundle URL per recovery invocation;
- drag-source configuration using the app bundle file URL and `.copy`
  operation;
- single-panel reuse, explicit dismissal, and cleanup when the settings view
  disappears;
- generation-safe replacement after rapid repeated `Allow` clicks and rejection
  of late callbacks from a superseded session;
- preservation of System Settings as the frontmost application while the panel
  appears, closes, and starts a drag;
- removal of Finder reveal/activation side effects and preservation of existing
  permission detection/destination mapping.

Verification gates are:

1. Fresh `swift build` and `swift test` using isolated scratch paths.
2. Unsigned arm64 Xcode Debug build of the `SwitchTab` scheme.
3. Diff/path guards proving all pre-existing dirty files remain byte-for-byte
   unchanged.
4. Native macOS QA for both Accessibility and Screen Recording: open each pane,
   confirm the panel remains visible above System Settings and does not become
   the frontmost app, drag the exact SwitchTab tile over the list until the
   destination advertises acceptance, then cancel before dropping. Capture
   visual and process-identity evidence without changing TCC state.

## Documentation Impact

Update the feature quickstart and permission recovery design notes to describe
the helper panel instead of Finder becoming the final foreground app. Preserve
the explicit contract that all privacy changes remain user-driven. Update the
authoritative spec, plan, research, quickstart, blocker notes, and help copy in
one change so no Finder-specific acceptance requirement remains.

## References

- Apple AppKit drag and drop:
  <https://developer.apple.com/documentation/appkit/drag-and-drop>
- `NSView.beginDraggingSession`:
  <https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)>
- File URL pasteboard type:
  <https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/fileurl>
- Core Graphics screen-capture permission check:
  <https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()>
