# Application Switcher Focus and Compact Layout Design

**Date:** 2026-07-31
**Status:** Approved for implementation

## Goal

Make the optional Cmd-Tab replacement activate the selected application's
windows reliably from both Command release and mouse confirmation. Tighten the
application overlay so only the selected app shows metadata, without changing
panel height as selection moves.

## Scope

This change affects application-switching mode only. Current-application window
switching keeps its existing title headers, thumbnails, close controls,
keyboard behavior, and layout metrics.

## Application Tile Presentation

- Every running regular application keeps its large application icon.
- Unselected applications show only their icon.
- The selected application shows its title directly below and horizontally
  centered on its own icon.
- Every tile reserves one minimal, fixed-height caption line. Hiding an
  unselected title changes visibility only; it never changes tile or panel
  geometry.
- The caption uses a single line with approximately 1 point of separation from
  the icon selection area and no independent vertical padding.
- A known standard-window count greater than one adds the existing window glyph
  and number beside the selected title.
- Counts of zero or one, and unavailable counts, show the title alone.
- A long selected title may extend beyond the icon width without affecting grid
  layout. It remains a single line and truncates only when the available panel
  boundary cannot contain it.

## Geometry and Visual Treatment

At scale 1, application icons remain 96 points. The icon selection container is
104 by 104 points, providing equal 4-point padding around the icon. Application
grid spacing becomes 4 points. The caption line is approximately 14 points
high. All values continue to follow the existing continuous overlay-size scale.

The selected fill and blue outline cover only the icon selection container;
they never extend behind the caption. The app icon uses its native visual
corner treatment. The selection container uses a 26-point radius around the
96-point icon, matching the icon's approximately 22-point radius plus its
4-point inset so the two curves remain visually concentric.

The panel retains SwitchTab's native dark blur material and compact inset. The
attached native Cmd-Tab reference informs icon scale, dense horizontal rhythm,
selected-title placement, and panel balance. It does not replace SwitchTab's
approved blue selection treatment, and application-owned notification badges
remain distinct from SwitchTab's window-count metadata.

## Selection and Metadata Flow

`SwitcherOverlayState` remains the source of the selected index. Application
tiles derive three independent presentation decisions from the current session:

1. whether the icon selection container is highlighted;
2. whether the title is visible;
3. whether a window-count glyph and number are visible.

Asynchronous Accessibility window counts may change selected caption content,
but they do not trigger a new layout size. Hover, Tab, Shift-Tab, and arrow-key
selection all use the same rules.

## Application Activation

Both Command release and mouse click already converge on the overlay's
confirmation callback. The fix stays in their shared application activation
boundary rather than adding input-specific behavior.

The current implementation asks the target `NSRunningApplication` to activate
with `.activateAllWindows`, but it does not first transfer activation context
from SwitchTab. Modern AppKit cooperative activation requires the active app to
yield to the target before the target requests activation.

The confirmation sequence is:

1. Dismiss the overlay and remove its Event Tap and monitors.
2. Resolve the non-terminated target by process identifier.
3. Call `NSApp.yieldActivation(to: target)`.
4. Call `target.activate(options: .activateAllWindows)`.
5. Record application MRU only when the activation request succeeds.

This keeps the existing application identity model and makes AppKit bring the
target application's main/key windows forward. It avoids the deprecated
`activateIgnoringOtherApps` option and does not add polling or synthetic mouse
or keyboard input.

## Error Handling

- A missing or terminated target returns `unavailableTarget` and does not write
  application MRU.
- A rejected activation request returns `unavailableTarget` and does not write
  application MRU.
- An unavailable window count leaves the selected title visible without count
  metadata.
- A stale asynchronous count update remains guarded by presentation identity.
- Application activation failure does not affect current-app window switching.

## Verification

Automated tests will cover:

- titles visible only for the selected application;
- window count hidden for zero, one, and unknown, and visible for two or more;
- fixed application tile and panel height across selection changes and async
  count updates;
- 96-point icon, equal 4-point icon padding, 4-point grid spacing, and the
  icon-only 26-point-radius selection container;
- the activation driver sequence `yield -> activate(.activateAllWindows)`;
- both Command-release and mouse-confirm paths reaching the same activation
  coordinator;
- MRU writes only after a successful activation request;
- unchanged current-app window-mode geometry and behavior.

Live macOS acceptance will use at least Finder, Safari, and TextEdit. It will
verify forward and reverse Cmd-Tab selection, Command release, direct mouse
selection, hidden/minimized targets where available, selected/frontmost app
identity, compact visual geometry, window-count visibility, and unchanged
current-app window switching.

## Release

Implementation starts from the latest `origin/main` in an isolated worktree so
the user's existing dirty-worktree changes remain untouched. After automated
and live verification, the repository release workflow will create the next
patch version, update release metadata, publish the branch and pull request,
and complete the configured release checks.
