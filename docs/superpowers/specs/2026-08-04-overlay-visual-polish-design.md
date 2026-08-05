# Overlay Visual Polish Design

**Date:** 2026-08-04
**Status:** Approved

## Goal

Polish both switcher overlays without changing switching behavior:

- reduce excess application-icon and window-tile padding;
- make the window panel's top and bottom insets equal;
- use native Liquid Glass on macOS 26 with a native fallback on supported older macOS releases;
- center the selected application caption under its icon, including the first and last columns.

## Constraints

- Keep the deployment target at macOS 14.
- Preserve existing window thumbnails, application icons, selection behavior, accessibility, and overlay scaling.
- Do not add custom background opacity as a substitute for native materials.
- Keep panel geometry stable while selection moves.
- Limit changes to overlay presentation and its tests.

## Layout Design

Replace the single shared padding value with directional panel metrics so rendered insets and calculated panel size use the same values.

At the default scale:

| Metric | Window switcher | Application switcher |
|---|---:|---:|
| Panel horizontal inset | 10 pt per side | 10 pt per side |
| Panel top inset | 8 pt | 8 pt |
| Panel bottom inset | 8 pt | 0 pt |
| Tile vertical content inset | 0 pt | N/A |
| App icon selection inset | N/A | 2 pt per side |

Window tiles retain their 4 pt horizontal content inset. Their height becomes the exact sum of the title row, content spacing, and thumbnail height; no extra vertical padding remains. Grid spacing remains unchanged.

Application icons remain 96 pt at default scale. The selection container becomes 100 pt, the caption row remains 14 pt, and the icon-to-caption spacing remains 1 pt. The panel's bottom edge ends at the caption row with no additional inset.

All values continue to scale through `OverlaySizeScale` using the existing rounding behavior.

## Caption Design

The current edge-caption policy deliberately aligns first-column captions toward the right and last-column captions toward the left. That prevents clipping but makes those captions visibly detach from their icons.

The replacement policy always centers the caption frame on the selected icon:

- interior columns retain the existing maximum caption width of 240 pt;
- edge columns cap the caption width to the centered space available between the icon center and panel edge;
- long edge captions truncate symmetrically instead of shifting away from the icon;
- single-column layouts retain a caption-safe panel width;
- panel size never changes when selection changes.

At default scale, a 100 pt application tile with 10 pt horizontal panel inset permits a centered 120 pt edge caption.

## Glass Design

The overlay remains a clear, nonactivating panel with behind-window sampling.

- On macOS 26 or later, use `NSGlassEffectView` with the panel's existing corner radius and default system tint.
- On macOS 14 and 15, use `NSVisualEffectView` with `.popover`, `.behindWindow`, and `.active`.
- Do not set custom tint or opacity.
- Keep the existing SwiftUI clipping and subtle border so both rendering paths share the same silhouette.

The availability branch lives inside one AppKit-backed SwiftUI background view. No switching/session code depends on OS version.

## Error and Accessibility Behavior

The material selection is local and deterministic, so it has no runtime failure path. Native material views inherit system appearance and accessibility settings, including Reduce Transparency and increased contrast. Existing text styles and accessibility labels remain unchanged.

## Verification

Use test-driven development:

1. Add failing layout tests for directional panel insets, exact window tile height, 100 pt application selection extent, zero application bottom inset, and centered edge-caption widths.
2. Add a failing chrome-policy/source test proving the macOS 26 glass path and `.popover` fallback exist without custom opacity.
3. Implement the minimum production changes needed to pass.
4. Run `swift build`, `swift test`, and the complete unsigned Xcode app build.
5. Launch the Debug app and inspect both overlays for:
   - equal window panel top/bottom insets;
   - no window-tile vertical padding;
   - 2 pt application selection inset and zero caption-bottom inset;
   - centered first, middle, and last application captions;
   - native glass sampling in light and dark appearance where practical.

## Non-Goals

- No switching, activation, keyboard, hover, close, MRU, or permissions changes.
- No custom glass renderer, blur radius, opacity control, tint setting, or appearance preference.
- No unrelated overlay refactor.
