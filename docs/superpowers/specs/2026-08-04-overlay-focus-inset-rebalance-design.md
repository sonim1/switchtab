# Overlay Focus Inset Rebalance Design

## Goal

Rebalance the space immediately around each blue selection outline without changing icon or thumbnail sizes.

## Application Switcher

- Keep the application panel's total default height unchanged.
- Keep the application icon at 96 pt.
- Reduce the selection container from 100 pt to 98 pt, leaving a 1 pt inset around the icon.
- Move the recovered 2 pt to the panel bottom inset so the selected caption has breathing room below it.
- Keep the existing 8 pt panel top inset, 1 pt icon-to-caption spacing, and 14 pt caption row.

At default scale the total remains 123 pt: `8 top + 113 tile + 2 bottom`.

## Window Switcher

- Keep the title, thumbnail, horizontal inset, and outer panel insets unchanged.
- Add 2 pt of vertical content inset above the title and below the thumbnail inside the blue selection outline.
- Increase the default window tile height from 134 pt to 138 pt so content is not shrunk.

## Verification

- Layout tests lock the application panel's unchanged total height and the new bottom inset.
- Layout tests lock the window tile's 2 pt vertical content inset and resulting height.
- Source integration tests verify SwiftUI consumes the vertical inset.
- Run the full Swift suite and unsigned Xcode build.
