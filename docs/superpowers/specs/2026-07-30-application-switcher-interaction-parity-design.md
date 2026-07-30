# Application Switcher Interaction Parity Design

**Date:** 2026-07-30
**Status:** Approved for implementation

## Goal

Make the application switcher behave like the current-application window
switcher for keyboard interaction while fixing the compact application's
selection layout and showing how many windows each application owns.

## Scope

The application switcher keeps its compact icon-and-name presentation. This
follow-up changes its input handling, close behavior, window-count metadata,
selection scrolling, and panel inset calculation. The window switcher's
thumbnail presentation remains unchanged.

## Shared Keyboard Contract

Both switcher modes use the same overlay interaction state machine:

- releasing the trigger modifier confirms the selected item;
- arrow keys move the selection;
- Return confirms;
- Escape cancels;
- Command-W closes the selected target's window and keeps the overlay open.

Application mode interprets Command-W as closing the selected application's
most recently focused standard window. It never quits the application. After
Accessibility reports that the window was destroyed, the item's window count
is refreshed in place. An application with no remaining windows stays in the
application list with a count of zero.

Modifier release is observed by the same session Event Tap that owns overlay
key events. Existing AppKit event monitors remain as a fallback, but correctness
does not depend on a global `NSEvent` modifier notification arriving.

## Window Count

When the application switcher opens, SwitchTab queries standard windows for
each running regular application through the existing Accessibility boundary.
Each application tile displays a small secondary window glyph and numeric count
beside the application name. If Accessibility cannot provide a snapshot, the
tile omits the count rather than displaying misleading data.

The count query excludes closed and non-standard Accessibility elements. It
includes minimized standard windows. The application switcher already requires
Accessibility permission, so this introduces no new permission request.

## Stable Layout

The layout policy records whether the content exceeds its visible row capacity.
Keyboard selection scrolls only when rows actually overflow. A one-, two-, or
three-row application grid therefore remains fixed when Tab or arrow keys move
the selection.

Mode-specific panel padding becomes part of the layout metrics. Application
mode uses the compact inset already represented by its total grid padding;
window mode retains its existing inset. Panel size and rendered inset therefore
agree at every overlay scale, leaving the full selected outline visible.

## Error Handling

- If modifier-release capture is unavailable, the existing AppKit monitor
  continues to provide the fallback confirmation path.
- If the selected application has no closeable window, Command-W is a no-op and
  the overlay remains open.
- If a close request is rejected or a save dialog prevents destruction, the
  application and count remain unchanged.
- A destruction callback from an older presentation cannot mutate a newer
  overlay session.

## Verification

- Event policy tests prove trigger release is handled through the Event Tap and
  passed through to macOS after confirmation.
- State and controller tests prove application mode accepts Command-W and
  refreshes the selected item without dismissing.
- Accessibility-backed service tests cover standard/minimized window counts and
  focused-window selection.
- Layout tests prove non-overflowing grids do not request scrolling and that
  tile outlines fit at minimum, default, and maximum scales.
- Source presentation tests prove the compact window-count label is rendered
  only in application mode.
- The full Swift test suite, Xcode Debug build, and live Cmd-Tab acceptance path
  must pass before release.

## Success Criteria

- Releasing Command after Cmd-Tab activates the highlighted application.
- Repeated Tab or arrow input does not shift a fully visible application grid.
- The selected blue outline is visible on all four sides at every size scale.
- Each application shows its current standard-window count when available.
- Command-W closes one selected-app window without quitting the app or
  dismissing the overlay.
- Option-Tilde window switching retains the same keyboard behavior and
  thumbnail UI.
