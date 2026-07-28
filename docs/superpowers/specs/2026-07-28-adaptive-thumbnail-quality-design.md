# Adaptive Thumbnail Quality Design

## Problem

SwitchTab currently captures every window preview inside a fixed `180×112` pixel box. The size slider can render a thumbnail as large as `240×165` points, so macOS must enlarge a relatively small image. The mismatch is more visible on Retina displays and can make window contents difficult to identify.

## Success Criteria

- Capture resolution follows the selected overlay size instead of remaining fixed.
- The existing small, default, and large slider positions all look visibly clearer, with the largest improvement at larger sizes.
- Thumbnail presentation remains asynchronous and does not delay opening or navigating the overlay.
- Capture dimensions remain bounded for unusually wide or tall windows.
- Window ordering, hover, close, fallback icons, permissions, and size settings remain unchanged.

## Design

Use a fixed balanced quality factor of `1.5` pixels per rendered thumbnail point. `AppDelegate` will derive the current thumbnail point size from `SwitcherOverlayLayoutMetrics` and pass the quality-adjusted viewport size into `WindowThumbnailLoader` for that presentation.

`ScreenCaptureKitWindowThumbnailCapturer` will calculate an aspect-fill capture size for the source window. This matches SwiftUI's existing `scaledToFill` rendering: the captured image must cover both requested viewport dimensions before SwiftUI crops it. The current aspect-fit calculation can undersupply one dimension and cause an additional upscale.

The calculated image will never exceed the source window's native size and will keep its longest edge at or below 480 pixels. The long-edge limit bounds ScreenCaptureKit work, PNG encoding, memory, and cache size for unusual aspect ratios. Typical 16:9 windows will request approximately:

- minimum slider size: about `205×116` pixels;
- default size: about `293×165` pixels;
- maximum slider size: about `440×248` pixels.

The loader remains single-pass and asynchronous. The store continues to cache one PNG and one decoded `NSImage` per window. There is no progressive reload, new setting, quality selector, or cache variant.

## Data Flow

1. Read the persisted overlay scale when presenting the switcher.
2. Derive `SwitcherOverlayLayoutMetrics.thumbnailSize`.
3. Multiply both viewport dimensions by `1.5` and pass the result to the loader.
4. Derive an aspect-fill ScreenCaptureKit configuration from the source window aspect ratio.
5. Clamp to native source dimensions and the 480-pixel long-edge limit.
6. Capture, encode, cache, and render through the existing asynchronous path.

Capture failures retain the current behavior: skip the unavailable thumbnail and show the existing application-icon or window-symbol fallback. Cancellation and presentation-generation handling remain unchanged.

## Alternatives Considered

- **Fixed larger capture size:** smallest code change, but wastes work for small thumbnails and remains insufficient or excessive as the slider changes.
- **Adaptive 1.5× aspect-fill capture:** improves clarity in proportion to the chosen size, preserves the current fast single-pass pipeline, and has an explicit work bound. Chosen.
- **Low-resolution first, high-resolution replacement:** best theoretical first-paint latency, but adds two capture passes, cache variants, replacement races, and visible image changes. Rejected for this modest quality improvement.

## Testing and Performance Validation

- Add pure target-size tests for wide, tall, square, tiny, and extreme-aspect source windows.
- Verify minimum, default, and maximum overlay scales request monotonically increasing capture sizes.
- Verify the 1.5× viewport factor, aspect-fill coverage, native-size clamp, and 480-pixel long-edge bound.
- Verify loader cancellation, stale-refresh rejection, fallback behavior, and cache reuse remain passing.
- Run all Swift tests, all release contract tests, and the unsigned Debug app build.
- Compare current and new requested pixel counts for representative 16:9 windows. The expected default increase is roughly 2.6× pixels and the expected maximum is roughly 6× the old fixed capture, while remaining below about 110,000 pixels for common wide windows.
- Perform a local overlay smoke check when macOS Accessibility and Screen Recording permissions allow it; lack of TCC permission must be reported rather than bypassed.

## Release

Ship through a pull request as the next patch release, expected `v1.0.9`, using the existing automatic versioning, notarized DMG, Sparkle appcast, R2 publication, and Homebrew tap pipeline. Verify the annotated tag, release assets, checksum, stapling ticket, public appcast, R2 asset, and tap update after merge.
