# Persistent Window Thumbnail Cache Design

## Context

Window mode currently clears completed thumbnails when a held-modifier session
ends. Reopening the overlay therefore shows application icons first and replaces
them with thumbnails after new captures finish. The transition is correct but
makes repeated use feel slower than it is.

The default window thumbnail is also small at `160 x 110 pt`. The approved new
base size is `192 x 132 pt`; application-switcher icon sizing remains unchanged.

## Goals

- Reopen window mode with the most recent thumbnail immediately when one exists.
- Refresh every visible or selected cached thumbnail in the background so the
  old image is only a temporary stale-while-revalidate value.
- Keep thumbnail memory bounded and responsive to memory pressure.
- Increase the default window thumbnail to `192 x 132 pt` without changing the
  application-switcher layout.
- Benchmark the encoding/display pipeline before choosing PNG or JPEG.

## Non-goals

- No disk persistence or cache restoration after SwitchTab quits.
- No WebP dependency. The local macOS ImageIO destination list supports PNG and
  JPEG encoding but not WebP encoding.
- No background polling, prewarming, telemetry, or capture while the overlay is
  closed.
- No changes to selection, ordering, focus, shortcuts, or confirmation behavior.

## Considered Approaches

### 1. Keep PNG and only extend cache lifetime

This is the smallest change and preserves alpha and sharp UI text. It removes
the icon flash on cache hits, but retains the current encode-before-display
latency for fresh captures.

### 2. Encode JPEG before display

JPEG can reduce encoded bytes and may encode faster. Quality `0.65`, `0.70`, and
`0.75` are plausible thumbnail settings. It still delays first display until
encoding finishes, removes alpha, and may introduce artifacts around text and
thin UI lines.

### 3. Display the captured image first, encode the cache afterward

This is the preferred candidate. A successful ScreenCaptureKit `CGImage` is
published for display before cache encoding. Encoding then runs off the main
actor and stores the persistent in-memory representation. This avoids the
wasteful alternative of encoding PNG for immediate display and then encoding
the same image again as JPEG.

The benchmark decides whether approach 3 is justified and whether its stored
representation is JPEG or PNG. If it offers no material latency benefit, the
implementation falls back to approach 1 or 2, whichever the measurements
support.

## Benchmark Gate

Benchmark before product behavior changes. Feed the same captured `CGImage`
fixtures through:

1. PNG encode, decode, and display-ready conversion;
2. JPEG encode, decode, and display-ready conversion at qualities `0.65`,
   `0.70`, and `0.75`;
3. captured-image display-ready conversion followed by background encoding for
   each viable cache format.

Use representative light, dark, text-heavy, and image-heavy windows at the new
capture target derived from `192 x 132 pt`. Record at least 30 warmed iterations
per fixture and report median and p95 for:

- time to first display-ready image;
- encode time;
- decode time for a cache hit;
- encoded byte count;
- estimated decoded RGBA cost.

Inspect the actual thumbnails at their rendered size and at 2x zoom. The chosen
JPEG quality is the lowest tested setting before text edges, thin rules, dark
gradients, or window shadows show objectionable artifacts. `0.70` is the default
candidate, not a predetermined result.

Decision rules:

- Prefer captured-image-first only when it lowers median time to first display
  without a p95 regression or main-actor work increase.
- Prefer JPEG only when it materially lowers encoded size or total background
  encoding cost and passes visual inspection.
- Keep PNG if JPEG's benefit is small, alpha handling is visibly wrong, or UI
  detail degrades.
- Record honest results locally; do not commit captured window contents.

## Cache Architecture

The cache remains memory-only and LRU-evicted, but completed entries survive a
normal overlay dismissal and a later held-modifier session.

Hard limits:

- 16 completed entries;
- 24 MiB estimated encoded plus decoded image cost;
- warning-pressure trim to 8 entries and 12 MiB;
- critical-pressure clear.

The limits are dual gates: eviction runs when either entry count or estimated
cost is exceeded. Enlarging the rendered thumbnail therefore cannot silently
increase memory without bound.

Cache keys must identify both the owning process and the window. App termination
removes that process's entries, and confirmed window closure removes that
window's entry. Screen Recording permission loss and SwitchTab termination clear
the whole cache. A normal overlay dismissal cancels queued/in-flight work but
keeps completed entries.

Decoded display objects are hotter and more expensive than encoded data. The
store may retain decoded images for current visible demand, but eviction and
memory-pressure accounting must include their RGBA cost. Offscreen decoded
objects should be released before useful encoded entries are discarded when the
chosen representation supports that split.

## Stale-While-Revalidate Flow

1. Window discovery returns the current candidate list.
2. The store supplies matching cached thumbnails immediately.
3. Selected and visible windows are still enqueued once for the new refresh
   generation even when a cached entry exists.
4. Capture remains serial and demand-driven.
5. A successful fresh capture replaces the cached image without moving
   selection or changing tile geometry.
6. A failed capture leaves the previous cached thumbnail visible for that
   presentation.
7. Results from cancelled or older generations never publish or overwrite a
   newer cache entry.

There is no extra cross-fade requirement. Direct replacement avoids additional
animation work and preserves the current stable layout.

## Layout Change

Change only the window-mode base thumbnail from `160 x 110 pt` to
`192 x 132 pt`. Existing continuous overlay scaling still applies, so user
settings remain valid. Application-mode icon and caption geometry do not change.

Layout verification must cover narrow and wide screens, one and many windows,
all supported scale values, scrolling, selection visibility, title truncation,
and close-button hit targets. Fewer visible columns are acceptable when required
by the larger approved thumbnail, but the panel must remain on-screen.

## Failure and Privacy Behavior

- Without Screen Recording permission, do not show retained previews; clear the
  cache and keep the icon fallback.
- Encoding failure must not remove a usable previous cache entry.
- Cache work never blocks switching, confirmation, or cancellation.
- Captures, benchmark fixtures, app names, window titles, and image bytes remain
  local and are not committed or logged.

## Test Strategy

- Benchmark tests compare identical images across PNG, JPEG qualities, and the
  captured-image-first path.
- Store tests cover the 16-entry and 24 MiB gates, LRU order, warning trim,
  critical clear, and decoded-cost accounting.
- Loader tests cover cache-hit immediate display, once-per-generation refresh,
  fresh replacement, failed-refresh retention, and stale-result rejection.
- Lifecycle tests cover normal dismissal preservation, permission-loss clear,
  process/window removal, and termination clear.
- Layout tests assert `192 x 132 pt` at scale 1 and unchanged application-mode
  metrics.
- Full Swift tests, Swift build, unsigned Xcode build, and manual held-Command
  reopen checks are required before shipping.

## Acceptance Criteria

- Reopening a previously viewed window list shows cached thumbnails on the first
  rendered frame instead of application icons.
- Visible cached thumbnails are refreshed and replaced with current captures.
- Cache use never exceeds 16 entries or 24 MiB by its defined accounting model.
- Memory warning and critical-pressure behavior matches the approved limits.
- Default window thumbnails render at `192 x 132 pt`; application mode is
  unchanged.
- The final image format and display pipeline are justified by recorded benchmark
  results rather than assumption.
