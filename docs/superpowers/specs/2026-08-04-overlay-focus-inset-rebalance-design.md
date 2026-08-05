# Overlay Focus Inset Rebalance Design

## Goal

Rebalance the space immediately around each blue selection outline without changing icon or thumbnail sizes.

## Application Switcher

- Keep the application panel's total default height unchanged.
- Keep the application icon at 96 pt.
- Reduce the visual selection container from 100 pt to 94 pt while keeping the icon at 96 pt.
- Keep the icon's 96 pt layout frame independent from the smaller, centered selection background.
- Keep the 100 pt grid-cell width so columns and caption bounds do not move.
- Reduce the tile height from 115 pt to 111 pt and move the recovered 4 pt to the panel bottom inset.
- Scale the bottom inset with the overlay size setting, matching the surrounding geometry.
- Keep the existing 8 pt panel top inset, 1 pt icon-to-caption spacing, and 14 pt caption row.

At default scale the total remains 123 pt: `8 top + 111 tile height + 4 bottom`.

## Window Switcher

- Keep the title, thumbnail, and outer panel insets unchanged.
- Increase the horizontal inset from 4 pt to 6 pt and add 6 pt above the title and below the thumbnail.
- Increase the default window tile from 168×134 pt to 172×146 pt so content is not shrunk.

## Verification

- Layout tests lock the application panel's unchanged total height and the new bottom inset.
- Layout tests lock the window tile's 6 pt directional content inset and resulting size.
- Source integration tests verify SwiftUI consumes the vertical inset and centers the smaller app selection background independently from the icon frame.
- Run the full Swift suite and unsigned Xcode build.
