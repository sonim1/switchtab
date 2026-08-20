# Switcher Hot-Path Performance Design

## Goal

Reduce avoidable work between a shortcut event and a usable switcher without
changing switching behavior, ordering, permissions, layout, or keyboard
semantics. Add enough local instrumentation to prove whether each optimization
helps before it ships.

The installed app is already healthy while idle: three samples showed 0.0% CPU,
about 25 MB of memory, and three to four threads. This work therefore targets
invocation hot paths rather than background activity.

## Scope

This change has four parts:

1. Add local signpost intervals for switcher invocation, Accessibility window
   discovery, overlay presentation, and first-thumbnail availability.
2. Batch Accessibility attributes needed for window discovery, with the current
   single-attribute reads retained as a compatibility fallback.
3. Make application window-count enrichment latest-wins so rapid presentations
   do not perform queued stale scans or publish stale results.
4. Preserve bounded thumbnails while one held-modifier session switches modes,
   then clear them on final dismissal, permission loss, cancellation outside a
   retained session, or critical memory pressure.

## Non-Goals

- No new user-facing setting, command, overlay state, or visual treatment.
- No persistent window or thumbnail cache across separate switcher sessions.
- No polling, background prewarming, or work while the switcher is idle.
- No telemetry, network reporting, or persistent performance history.
- No change to which Accessibility windows qualify or how window identity is
  resolved.
- No parallel thumbnail captures; capture remains serial and demand-driven.

## Current Constraints

- Window presentation synchronously discovers windows before the panel can be
  shown. Each accepted window currently requires several cross-process
  Accessibility reads.
- Application tiles appear immediately, but every presentation starts another
  serial full-app window-count scan. A presentation identifier prevents stale
  UI publication but does not prevent stale work.
- Thumbnail loading is bounded and demand-driven, but both refresh and cancel
  clear the store. Switching away from and back to window mode during one held
  session therefore recaptures otherwise valid thumbnails.
- Dismissal must continue to release thumbnail work and cached preview data.

## Architecture

### Local Performance Tracing

Add a small internal tracing helper backed by unified logging signposts. It
records intervals and points only; it does not retain application names,
window titles, process identifiers, or other user content.

The trace points are:

- shortcut handler entered;
- Accessibility discovery started and ended, including only mode and item
  count as public numeric metadata;
- overlay presentation completed;
- first requested thumbnail became available;
- application window-count enrichment started, superseded, and completed.

Window-mode invocation uses one trace identifier from the shortcut entry point
through overlay presentation. Thumbnail completion is asynchronous and closes
its own child interval. Application mode records presentation and enrichment as
separate intervals because counts do not block the initial panel.

Signpost creation must be cheap when Instruments is not attached. Existing
debug-file logging remains unchanged and is not used for timing because it has
only second-level timestamps and performs file I/O.

### Batched Accessibility Reads

Extend the Accessibility reader boundary with a typed window-attribute snapshot
containing role, subrole, title, and minimized state. The system implementation
requests those values together with
`AXUIElementCopyMultipleAttributeValues`. The private window-number resolver and
the application-level focused-window lookup remain separate because they use
different APIs and semantics.

If the batched call fails, returns a malformed value, or omits a required role
or subrole, the reader falls back to the existing individual attribute calls for
that window. A partial batch must never silently change inclusion behavior.

Both full discovery and window counting use the same typed snapshot boundary.
Tests use a fake reader to prove that the batch path avoids individual reads and
that fallback produces the same snapshots and counts as today.

### Latest-Wins Window Counts

Replace fire-and-forget queue submissions with a serial latest-wins worker:

1. A load request replaces any pending request.
2. If no worker is active, one starts.
3. A running Accessibility scan is allowed to finish because the underlying
   synchronous AX calls are not cancellable.
4. Its completion is published only if it is still the newest generation.
5. The worker then processes the single newest pending request, if one exists.

This bounds useful work to the current scan plus the newest request. Superseded
queued scans do not call Accessibility and never invoke their completion.
Synchronization stays inside the loader; AppDelegate continues to guard the UI
update with the overlay presentation identifier as a second safety boundary.

### Held-Session Thumbnail Reuse

Separate stopping thumbnail work from clearing thumbnail data.

- Fresh presentation, ordinary dismissal, app termination, preview-permission
  loss, and critical memory pressure stop work and clear the store.
- A retained mode switch stops queued or active capture work but preserves the
  bounded store.
- Returning to window mode in the same held session begins a new generation
  without clearing preserved entries. Existing `containsThumbnail` checks avoid
  recapture for matching `ownerPID-windowID` keys.
- Entries for other applications may remain until the held session ends, but
  the existing 32-entry and 64 MiB LRU limits still apply.
- If preview permission is blocked on return, preserved previews are cleared
  before presentation and no new requests are accepted.

The cache never crosses a completed or cancelled switcher session.

## Data Flow

```text
shortcut event
  -> begin invocation signpost
  -> resolve routing decision
  -> window mode
       -> begin AX discovery signpost
       -> fetch window elements
       -> batch role/subrole/title/minimized per element
       -> per-window fallback only when batch is unusable
       -> order items
       -> present overlay and end invocation signpost
       -> demand-driven thumbnail worker
          -> reuse held-session entry or capture
          -> record first-thumbnail signpost
  -> application mode
       -> enumerate running applications
       -> present overlay and end invocation signpost
       -> replace pending count request
       -> publish newest generation only
```

## Failure and Compatibility Behavior

- Batched AX failure degrades to the current single-read path.
- An Accessibility denial or unavailable application leaves existing permission
  and retained-session behavior unchanged.
- Superseded count requests produce no UI callback.
- Thumbnail capture failure keeps the existing placeholder.
- Permission loss clears preserved previews rather than rendering stale content.
- Memory warning trimming and critical-pressure clearing retain their current
  limits and priority.

## Verification

### Automated Tests

- Batched AX reads produce the same inclusion, title, minimized, focused, and
  identifier results as individual reads.
- Successful batches perform no individual role, subrole, title, or minimized
  reads.
- Malformed and failed batches use the individual-read fallback.
- Window counting uses the batch snapshot and preserves unknown-count behavior.
- The count loader runs the current request plus only the newest pending request,
  suppressing stale completions.
- A retained mode switch preserves cached thumbnails and skips recapture on
  return.
- Fresh sessions, final dismissal, permission loss, and critical pressure clear
  previews.
- Existing queue bounds, LRU limits, selection stability, mode switching, and
  permission-degradation suites continue to pass.

### Native Measurement

Use Instruments Points of Interest on the same machine and build for repeated
scenarios with 1, 10, and approximately 30 windows, plus rapid application-mode
re-entry and window/application mode toggling.

Record median and p95 for:

- shortcut to overlay presentation;
- Accessibility discovery;
- overlay presentation to first thumbnail;
- application window-count enrichment.

The AX batching portion ships only if the 10-window and high-window-count cases
show lower median discovery time without a p95 regression. Held-session return
must show no capture for an unchanged cached window. Idle sampling must remain at
0% CPU under ordinary observation, and thumbnail memory must remain within the
existing 32-entry and 64 MiB limits.

## Delivery Sequence

1. Add trace points and capture a baseline.
2. Implement and verify batched Accessibility reads.
3. Implement and verify latest-wins window counts.
4. Implement and verify held-session thumbnail reuse.
5. Capture the same native measurements and compare them with the baseline.

Each optimization is independently testable and may be dropped if measurement
shows no benefit. No optimization is justified solely by reduced source-level
operation counts.
