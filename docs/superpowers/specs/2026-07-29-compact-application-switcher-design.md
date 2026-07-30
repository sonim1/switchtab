# Compact Application Switcher Design

**Date:** 2026-07-29
**Status:** Approved for implementation

## Goal

Make application switching visually compact and closer to the native macOS
app switcher while leaving current-app window thumbnails unchanged.

## Scope

This change affects only `SwitcherMode.applicationSwitching`.
`SwitcherMode.currentAppWindowSwitching` keeps its current title header,
thumbnail size, close control, spacing, and padding.

## Application Tile

Each application tile shows:

1. One large application icon.
2. The application name centered below the icon.

The duplicate small icon and title header above the large icon are removed.
Names stay on one line and truncate at the tail. Existing selection, hover,
click, keyboard, and accessibility behavior remains unchanged.

At the default scale, the application presentation uses approximately:

- 96-point application icons
- 120-by-128-point tiles
- 8-point spacing between tiles
- 16 points of total grid padding

All values continue to follow the existing overlay size scale.

## Layout Architecture

`SwitcherOverlayLayoutPolicy.presentationLayout` receives the active
`SwitcherMode` and chooses mode-specific metrics. Window metrics retain their
existing constants. Application metrics use the compact geometry above.

`SwitcherOverlayRootView` passes the active session mode to
`SwitcherIconStripView`. The tile view selects one of two content layouts:

- window mode: title header followed by thumbnail
- application mode: application icon followed by centered name

The selection background and border continue to wrap the whole tile.

## Verification

- Unit tests prove application metrics are smaller and denser than window
  metrics at the same scale.
- Layout tests prove more application columns fit at a representative screen
  width.
- Source contract tests prove application content uses the icon-first layout
  while the window title-header path remains present.
- The full Swift test suite and unsigned Xcode Debug build must pass.

## Success Criteria

- Application tiles show no duplicated icon.
- Application names appear below their icons.
- More applications fit in the same overlay width.
- Window thumbnails remain visually and behaviorally unchanged.
