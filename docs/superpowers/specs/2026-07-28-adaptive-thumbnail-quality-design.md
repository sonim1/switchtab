# Adaptive Thumbnail Quality and Close Selection Stability Design

## Problem

SwitchTab currently captures every window preview inside a fixed `180×112` pixel box. The size slider can render a thumbnail as large as `240×165` points, so macOS must enlarge a relatively small image. The mismatch is more visible on Retina displays and can make window contents difficult to identify.

There is also a close-selection race. While holding Command, a user can cycle with backtick and close the selected window with `W`. The Accessibility destruction notification arrives asynchronously. After the item is removed and the grid is re-laid out, the selected index can point at a visually stale SwiftUI tile and the scroll view is not instructed to reveal the corrected selection. A stationary pointer can also end up above a different reflowed tile and trigger hover selection without new mouse movement. Subsequent backtick presses can appear to skip windows or have no selection.

The About window currently formats the public version and internal build number as `Version 1.0.8 (9)`. The unlabeled number is unclear to users.

## Success Criteria

- Capture resolution follows the selected overlay size instead of remaining fixed.
- The existing small, default, and large slider positions all look visibly clearer, with the largest improvement at larger sizes.
- Thumbnail presentation remains asynchronous and does not delay opening or navigating the overlay.
- Capture dimensions remain bounded for unusually wide or tall windows.
- Closing the selected middle window selects the next remaining window at the same position.
- Closing the final selected window selects the previous remaining window.
- Moving selection while close confirmation is pending preserves the currently selected window by identity.
- Grid reflow under a stationary pointer cannot steal the corrected keyboard selection.
- Repeated close and backtick commands never leave the overlay without a valid visible selection or skip a remaining window.
- The About window displays the public version and labeled build number on separate lines.
- Window ordering, hover, fallback icons, permissions, and size settings remain unchanged.

## Design

Use a fixed balanced quality factor of `1.5` pixels per rendered thumbnail point. `AppDelegate` will derive the current thumbnail point size from `SwitcherOverlayLayoutMetrics` and pass the quality-adjusted viewport size into `WindowThumbnailLoader` for that presentation.

`ScreenCaptureKitWindowThumbnailCapturer` will calculate an aspect-fill capture size for the source window. This matches SwiftUI's existing `scaledToFill` rendering: the captured image must cover both requested viewport dimensions before SwiftUI crops it. The current aspect-fit calculation can undersupply one dimension and cause an additional upscale.

The calculated image will never exceed the source window's native size and will keep its longest edge at or below 480 pixels. The long-edge limit bounds ScreenCaptureKit work, PNG encoding, memory, and cache size for unusual aspect ratios. Typical 16:9 windows will request approximately:

- minimum slider size: about `207×116` pixels;
- default size: about `294×165` pixels;
- maximum slider size: about `441×248` pixels.

The loader remains single-pass and asynchronous. The store continues to cache one PNG and one decoded `NSImage` per window. There is no progressive reload, new setting, quality selector, or cache variant.

For close-selection stability, keep `SwitcherSession` as the authority for neighbor selection and continue removing confirmed windows by stable window ID. Render the grid with each item's stable ID as the `ForEach` identity instead of its transient array index. After a confirmed removal, disable hover selection and reset its movement origin to the current pointer location, then update layout and advance the existing keyboard scroll token so the corrected selection is visible. Hover becomes active again only after real pointer movement exceeds the existing threshold. If selection moved while destruction confirmation was pending, the session's identity-preserving index adjustment remains authoritative.

For About, expose separate version and build strings from `AboutSwitchTabContent`. Render `Version 1.0.9` as the primary line and `Build Number 10` as a smaller secondary line. The real values continue to come from `CFBundleShortVersionString` and `CFBundleVersion`; the example numbers represent the expected next patch release.

## Data Flow

1. Read the persisted overlay scale when presenting the switcher.
2. Derive `SwitcherOverlayLayoutMetrics.thumbnailSize`.
3. Multiply both viewport dimensions by `1.5` and pass the result to the loader.
4. Derive an aspect-fill ScreenCaptureKit configuration from the source window aspect ratio.
5. Clamp to native source dimensions and the 480-pixel long-edge limit.
6. Capture, encode, cache, and render through the existing asynchronous path.

Close confirmation flows separately:

1. `Cmd+W` requests native close for the selected stable window ID.
2. Navigation may continue while the native close is pending.
3. The Accessibility destruction callback removes only that stable ID.
4. `SwitcherSession` preserves the selected window identity or chooses the nearest surviving neighbor.
5. The controller resets the hover movement gate so layout movement cannot masquerade as pointer movement.
6. The presentation model advances its scroll token, re-renders stable-ID tiles, and scrolls the corrected selection into view.

Capture failures retain the current behavior: skip the unavailable thumbnail and show the existing application-icon or window-symbol fallback. Cancellation and presentation-generation handling remain unchanged.

## Alternatives Considered

- **Fixed larger capture size:** smallest code change, but wastes work for small thumbnails and remains insufficient or excessive as the slider changes.
- **Adaptive 1.5× aspect-fill capture:** improves clarity in proportion to the chosen size, preserves the current fast single-pass pipeline, and has an explicit work bound. Chosen.
- **Low-resolution first, high-resolution replacement:** best theoretical first-paint latency, but adds two capture passes, cache variants, replacement races, and visible image changes. Rejected for this modest quality improvement.

For close selection:

- **Rebuild the entire window list after every close:** can reconcile external state, but changes ordering and introduces another Accessibility query race. Rejected.
- **Remove by array index:** simple but unsafe after navigation or delayed callbacks. Rejected.
- **Remove by stable ID and normalize the existing session:** preserves user context and matches the current confirmed-close boundary. Chosen.

## Testing and Performance Validation

- Add pure target-size tests for wide, tall, square, tiny, and extreme-aspect source windows.
- Verify minimum, default, and maximum overlay scales request monotonically increasing capture sizes.
- Verify the 1.5× viewport factor, aspect-fill coverage, native-size clamp, and 480-pixel long-edge bound.
- Verify loader cancellation, stale-refresh rejection, fallback behavior, and cache reuse remain passing.
- Add session tests for closing the first, middle, and last selected item.
- Add controller tests for delayed destruction after additional navigation, repeated close-and-cycle commands, stable selected identity, scroll-token advancement after confirmed removal, and ignored stationary hover after reflow.
- Add a controller/render regression that removes an item and verifies the selected surviving tile remains bound to its stable ID after reflow.
- Update About content and view tests to require separate `Version` and `Build Number` lines sourced from bundle values.
- Run all Swift tests, all release contract tests, and the unsigned Debug app build.
- Compare current and new requested pixel counts for representative 16:9 windows. The expected default increase is roughly 2.6× pixels and the expected maximum is roughly 6× the old fixed capture, while remaining below about 110,000 pixels for common wide windows.
- Perform a local overlay smoke check when macOS Accessibility and Screen Recording permissions allow it; lack of TCC permission must be reported rather than bypassed.

## Release

Ship all three user-visible corrections through one pull request as the next patch release, expected `v1.0.9` build `10`, using the existing automatic versioning, notarized DMG, Sparkle appcast, R2 publication, and Homebrew tap pipeline. Verify the annotated tag, release assets, checksum, stapling ticket, public appcast, R2 asset, and tap update after merge.
