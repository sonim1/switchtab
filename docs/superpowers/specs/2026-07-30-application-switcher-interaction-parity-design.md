# Application Switcher Interaction Parity Design

**Date:** 2026-07-30
**Status:** Approved for implementation

## Goal

Make the application switcher behave like the current-application window
switcher for keyboard interaction while fixing the compact application's
selection layout and showing how many windows each application owns.

## Scope

The application switcher keeps its compact icon-and-name presentation. This
follow-up changes its input handling, quit behavior, window-count metadata,
selection scrolling, and panel inset calculation. The window switcher's
thumbnail presentation remains unchanged.

## Shared Keyboard Contract

Both switcher modes use the same overlay interaction state machine for common
navigation and confirmation:

- releasing the trigger modifier confirms the selected item;
- arrow keys move the selection;
- Return confirms;
- Escape cancels;
- Option-Tilde window mode keeps Command-W for closing the selected window.
- Cmd-Tab application mode uses Command-Q to request termination of the
  selected application, matching the native macOS application switcher.

Application mode does not reinterpret Command-W. Command-Q sends the selected
application its normal termination request, so the application remains
responsible for save confirmation or refusal. The overlay stays open. SwitchTab
removes the application tile only after `NSWorkspace` reports that exact
application terminated; releasing Command can then activate the remaining
selection.

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
- If the termination request is rejected, the application and overlay remain
  unchanged.
- If the application presents a save dialog or otherwise remains running, its
  tile is not removed.
- A termination notification only removes the matching application from the
  currently presented application-switcher session.

## Verification

- Event policy tests prove trigger release is handled through the Event Tap and
  passed through to macOS after confirmation.
- State and controller tests prove application mode accepts Command-Q, rejects
  window-close semantics, and removes an item only after confirmed termination.
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
- Command-Q requests termination of the selected app and the tile disappears
  only after confirmed termination; the overlay remains open.
- Command-W remains a window-mode action and is not used by application mode.
- Option-Tilde window switching retains the same keyboard behavior and
  thumbnail UI.
