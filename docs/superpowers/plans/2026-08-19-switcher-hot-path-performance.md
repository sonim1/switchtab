# Switcher Hot-Path Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure and reduce avoidable switcher hot-path work by batching Accessibility reads, coalescing application window-count scans, and reusing thumbnails only within one held-modifier session.

**Architecture:** Add local unified-logging signposts around the existing synchronous and asynchronous presentation stages. Keep the current provider/loader boundaries, extending them with a typed AX batch snapshot, a serial latest-wins request loop, and explicit thumbnail cache-preservation flags. Every optimized path retains the current fallback, permission, memory-pressure, and dismissal behavior.

**Tech Stack:** Swift 6, AppKit, ApplicationServices Accessibility APIs, ScreenCaptureKit, OSLog signposts, XCTest/legacy SwitchTab test runner, Xcode Instruments.

---

## File Map

- Create `SwitchTab/Services/SwitcherPerformanceTrace.swift`: signpost names and begin/end/event helpers; no persistence or user-content metadata.
- Modify `SwitchTab/AppDelegate.swift`: trace presentation stages, route latest-wins counts, and choose thumbnail cache lifetime from `retainingSession`.
- Modify `SwitchTab/Services/AccessibilityWindowProvider.swift`: typed attribute snapshots, batched system reads, and single-read fallback.
- Modify `SwitchTab/Services/WindowThumbnailService.swift`: distinguish cancelling capture work from clearing cached thumbnails and emit the first-thumbnail event.
- Modify `SwitchTabTests/Services/SwitcherPerformanceTests.swift`: protect trace vocabulary and invocation wiring.
- Modify `SwitchTabTests/Services/AccessibilityWindowProviderTests.swift`: prove batch/fallback equivalence and call-count reduction.
- Modify `SwitchTabTests/Services/ApplicationSwitchingTests.swift`: prove latest-wins scheduling and completion suppression.
- Modify `SwitchTabTests/Services/WindowThumbnailTests.swift`: prove held-session reuse and all mandatory clear paths.
- Modify `docs/AI_CONTEXT.md`: record the new performance and cache-lifetime invariants after implementation.

### Task 1: Add local performance signposts

**Files:**
- Create: `SwitchTab/Services/SwitcherPerformanceTrace.swift`
- Modify: `SwitchTab/AppDelegate.swift:325-632`
- Modify: `SwitchTab/Services/WindowThumbnailService.swift:309-438`
- Modify: `SwitchTabTests/Services/SwitcherPerformanceTests.swift`

- [ ] **Step 1: Add a failing trace-vocabulary contract test**

Extend `SwitcherPerformanceTests.run()` and add a source contract that requires the four stable Instruments names without testing OSLog internals:

```swift
static func run() throws {
    try testIconStripSessionCreationStaysFast()
    try testPerformanceTraceDefinesStablePointsOfInterest()
}

static func testPerformanceTraceDefinesStablePointsOfInterest() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot
        .appendingPathComponent("SwitchTab/Services/SwitcherPerformanceTrace.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    for name in [
        "Switcher Invocation",
        "Accessibility Discovery",
        "Application Window Counts",
        "First Thumbnail"
    ] {
        try expectTrue(source.contains("\"\(name)\""))
    }
    try expectFalse(source.contains("localizedName"))
    try expectFalse(source.contains("window.title"))
}
```

- [ ] **Step 2: Run the suite and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: FAIL because `SwitcherPerformanceTrace.swift` does not exist.

- [ ] **Step 3: Implement the minimal signpost helper**

Create `SwitcherPerformanceTrace.swift` with a fixed points-of-interest log and typed operations:

```swift
import OSLog

struct SwitcherPerformanceInterval {
    let id: OSSignpostID
}

enum SwitcherPerformanceTrace {
    private static let log = OSLog(
        subsystem: "com.royjen.switchtab",
        category: .pointsOfInterest
    )

    static func beginInvocation(mode: SwitcherMode) -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Switcher Invocation",
            signpostID: interval.id,
            "mode=%{public}s",
            String(describing: mode)
        )
        return interval
    }

    static func endInvocation(_ interval: SwitcherPerformanceInterval, itemCount: Int) {
        os_signpost(
            .end,
            log: log,
            name: "Switcher Invocation",
            signpostID: interval.id,
            "items=%{public}d",
            itemCount
        )
    }

    static func beginAccessibilityDiscovery() -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Accessibility Discovery",
            signpostID: interval.id
        )
        return interval
    }

    static func endAccessibilityDiscovery(
        _ interval: SwitcherPerformanceInterval,
        itemCount: Int
    ) {
        os_signpost(
            .end,
            log: log,
            name: "Accessibility Discovery",
            signpostID: interval.id,
            "items=%{public}d",
            itemCount
        )
    }

    static func beginApplicationWindowCounts() -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Application Window Counts",
            signpostID: interval.id
        )
        return interval
    }

    static func endApplicationWindowCounts(
        _ interval: SwitcherPerformanceInterval,
        superseded: Bool
    ) {
        os_signpost(
            .end,
            log: log,
            name: "Application Window Counts",
            signpostID: interval.id,
            "superseded=%{public}d",
            superseded ? 1 : 0
        )
    }

    static func firstThumbnail() {
        os_signpost(.event, log: log, name: "First Thumbnail")
    }
}
```

If Swift 6 rejects the printf-style `String` argument, use the SDK-supported
`NSString` bridge while preserving the exact four names and public metadata.

- [ ] **Step 4: Wire intervals without changing control flow**

In both public shortcut entry points, begin an invocation only for `.present` or
`.switchMode`; same-mode `.advance` remains untraced because it performs no
presentation. Pass the interval into `presentWindowSwitcher` or
`presentApplicationSwitcher`, close it immediately after `overlayController.present`,
and close it with zero items on every early return.

Wrap only the synchronous `windowProvider` call in the Accessibility interval.
Wrap each application count scan in its own interval. In
`WindowThumbnailLoader`, emit `firstThumbnail()` once per refresh generation,
immediately after the first successful `store.setThumbnail`.

- [ ] **Step 5: Run focused and full verification**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: PASS, including the trace vocabulary test.

Run: `rtk swift build`

Expected: build succeeds with no Swift concurrency diagnostics.

- [ ] **Step 6: Capture the baseline**

Build a signed local Debug app using the existing developer identity, launch it,
and record Instruments Points of Interest for:

1. one-window current-app presentation;
2. a multi-window app presentation;
3. application presentation followed by window mode;
4. window → application → same window return while Command remains held.

Record interval counts and durations in an ignored `.omo/evidence/` note. Do not
commit screenshots, application names, window titles, or desktop captures.

- [ ] **Step 7: Commit tracing**

Run:

```bash
rtk git add SwitchTab/Services/SwitcherPerformanceTrace.swift \
  SwitchTab/AppDelegate.swift \
  SwitchTab/Services/WindowThumbnailService.swift \
  SwitchTabTests/Services/SwitcherPerformanceTests.swift
rtk git commit -m "perf: instrument switcher hot paths"
```

### Task 2: Batch Accessibility window attributes

**Files:**
- Modify: `SwitchTab/Services/AccessibilityWindowProvider.swift:213-447`
- Modify: `SwitchTabTests/Services/AccessibilityWindowProviderTests.swift`

- [ ] **Step 1: Write failing batch and fallback tests**

Add these tests to `AccessibilityWindowProviderTests.run()`:

```swift
try testAXSnapshotProviderUsesBatchedWindowAttributes()
try testAXSnapshotProviderFallsBackWhenBatchIsUnavailable()
try testAXWindowCountUsesRoleSubroleBatch()
```

Use a recording fake whose new method accepts `includeDetails` and returns
typed snapshots:

```swift
func batchedWindowAttributes(
    _ element: AXUIElement,
    includeDetails: Bool
) -> AXWindowAttributeSnapshot? {
    batchedReadCount += 1
    return batchedResults[index(of: element)]
}
```

Assertions:

- full discovery performs one batch read per element and zero individual role,
  subrole, title, or minimized reads;
- a nil batch result performs the current individual reads and yields identical
  `AccessibilityWindowSnapshot` values;
- count mode passes `includeDetails: false`, performs one batch read per element,
  does not resolve window numbers, and returns the same count.

- [ ] **Step 2: Run the suite and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: compile failure because `AXWindowAttributeSnapshot` and
`batchedWindowAttributes` do not exist.

- [ ] **Step 3: Add the typed reader boundary**

In `AccessibilityWindowProvider.swift`, add:

```swift
struct AXWindowAttributeSnapshot: Equatable {
    let role: String?
    let subrole: String?
    let title: String?
    let isMinimized: Bool
}

protocol AXWindowAttributeReading: AnyObject {
    func windowElements(of applicationElement: AXUIElement) -> [AXUIElement]?
    func focusedWindowElement(of applicationElement: AXUIElement) -> AXUIElement?
    func batchedWindowAttributes(
        _ element: AXUIElement,
        includeDetails: Bool
    ) -> AXWindowAttributeSnapshot?
    func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String?
    func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool
}
```

The system implementation calls `AXUIElementCopyMultipleAttributeValues` with
role/subrole in count mode and role/subrole/title/minimized in detail mode. Treat
an `AXValue` error placeholder, wrong type, missing role, or missing subrole as an
unusable batch and return nil.

- [ ] **Step 4: Centralize fallback semantics**

Add a provider helper that tries the batch first and otherwise reads exactly the
attributes the caller needs:

```swift
private func windowAttributes(
    _ element: AXUIElement,
    includeDetails: Bool
) -> AXWindowAttributeSnapshot {
    if let attributes = attributeReader.batchedWindowAttributes(
        element,
        includeDetails: includeDetails
    ) {
        return attributes
    }

    return AXWindowAttributeSnapshot(
        role: attributeReader.stringAttribute(element, kAXRoleAttribute as CFString),
        subrole: attributeReader.stringAttribute(element, kAXSubroleAttribute as CFString),
        title: includeDetails
            ? attributeReader.stringAttribute(element, kAXTitleAttribute as CFString)
            : nil,
        isMinimized: includeDetails
            ? attributeReader.boolAttribute(element, kAXMinimizedAttribute as CFString)
            : false
    )
}
```

Use `includeDetails: false` in `windowCount` and `true` in `windows`. Pass the
already-read title and minimized value into `windowSnapshot` so it makes no
additional AX calls.

- [ ] **Step 5: Update existing fakes explicitly**

Every existing `AXWindowAttributeReading` fake must implement the new method.
Fakes not testing batching return nil so their prior individual-read assertions
remain meaningful. Do not add a protocol default that could hide missing test
intent.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: PASS; batch tests show one cross-process batch call per window and
fallback tests preserve all current results.

- [ ] **Step 7: Commit AX batching**

Run:

```bash
rtk git add SwitchTab/Services/AccessibilityWindowProvider.swift \
  SwitchTabTests/Services/AccessibilityWindowProviderTests.swift
rtk git commit -m "perf: batch accessibility window attributes"
```

### Task 3: Coalesce application window-count scans

**Files:**
- Modify: `SwitchTab/AppDelegate.swift:1409-1444`
- Modify: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **Step 1: Write failing latest-wins tests**

Replace the single deferral-only test with three behaviors, retaining its
original assertion:

```swift
try testWindowCountLoaderDefersWorkFromCaller()
try testWindowCountLoaderKeepsOnlyNewestPendingRequest()
try testWindowCountLoaderSuppressesSupersededCompletion()
```

For the pending test, suspend the worker queue, submit application IDs 1, 2, and
3, resume it, and assert only ID 3 reaches `loadCounts` and completion.

For the in-flight test, block ID 1 inside `loadCounts`, submit IDs 2 and 3, then
release ID 1. Assert execution order `[1, 3]`, completion only for ID 3, and no
execution for ID 2.

- [ ] **Step 2: Run the suite and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: FAIL because the current loader executes every queued request and
publishes the first completion.

- [ ] **Step 3: Implement one-running-plus-one-pending scheduling**

Inside `ApplicationWindowCountLoader`, add a locked request state:

```swift
private struct Request: @unchecked Sendable {
    let generation: UInt64
    let applications: [ApplicationItem]
    let completion: @Sendable ([ApplicationItem]) -> Void
}

private let lock = NSLock()
private var generation: UInt64 = 0
private var pendingRequest: Request?
private var workerIsRunning = false
```

`load` increments the generation, replaces `pendingRequest`, and starts one
worker only when idle. The worker repeatedly takes the pending request under the
lock, runs `loadCounts` outside the lock, and publishes only when the completed
generation still equals the newest generation. When pending is nil, it marks
itself idle under the same lock before returning.

Never hold the lock during AX work or user completion. Keep the queue serial and
retain `.userInitiated` QoS.

- [ ] **Step 4: Trace completed and superseded work**

Start `Application Window Counts` immediately before `loadCounts`. End it with
`superseded: true` when a newer generation exists and `false` when publishing.
Queued requests replaced before execution create no interval.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: PASS; observed executions are `[1, 3]`, only request 3 completes, and
deferral remains intact.

- [ ] **Step 6: Commit count coalescing**

Run:

```bash
rtk git add SwitchTab/AppDelegate.swift \
  SwitchTabTests/Services/ApplicationSwitchingTests.swift
rtk git commit -m "perf: coalesce application window counts"
```

### Task 4: Reuse thumbnails within a held session

**Files:**
- Modify: `SwitchTab/Services/WindowThumbnailService.swift:328-438`
- Modify: `SwitchTab/AppDelegate.swift:278-279, 427-560, 727-743`
- Modify: `SwitchTabTests/Services/WindowThumbnailTests.swift`

- [ ] **Step 1: Write failing cache-lifetime tests**

Add to `WindowThumbnailTests.run()`:

```swift
try await testThumbnailLoaderPreservesCacheAcrossRetainedRefresh()
try await testThumbnailLoaderPreservingCancelDropsInFlightWorkButKeepsCompletedCache()
try testThumbnailLoaderClearsPreservedCacheWhenPreviewPermissionIsBlocked()
```

The retained-refresh test captures window 7 once, begins another refresh with
preservation enabled, requests window 7 again, and asserts capture IDs remain
`[7]` and the cached key remains.

The preserving-cancel test seeds a completed cached thumbnail, starts a paused
capture for another window, cancels while preserving, resumes the stale capture,
and asserts only the seeded key remains.

The permission test seeds the store, begins a preserving refresh with blocked
Screen Recording, and asserts the store is empty and no demand is accepted.

- [ ] **Step 2: Run the suite and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: compile failure because preservation parameters do not exist.

- [ ] **Step 3: Add explicit preservation parameters**

Change loader APIs without changing their safe defaults:

```swift
public func beginRefresh(
    permissionState: PermissionState,
    viewportPixelSize: CGSize = CGSize(width: 240, height: 165),
    preservingCachedThumbnails: Bool = false
) {
    refreshGeneration += 1
    requestQueue.clear()
    activeWindowIDs.removeAll(keepingCapacity: true)
    previewsAllowed = !permissionState.blocksWindowPreviews
    self.viewportPixelSize = viewportPixelSize
    refreshTask?.cancel()
    if !preservingCachedThumbnails || !previewsAllowed {
        store.clear()
    }
}

public func cancel(preservingCachedThumbnails: Bool = false) {
    refreshGeneration += 1
    previewsAllowed = false
    requestQueue.clear()
    activeWindowIDs.removeAll(keepingCapacity: true)
    refreshTask?.cancel()
    if !preservingCachedThumbnails {
        store.clear()
    }
}
```

Reset the per-generation first-thumbnail flag in `beginRefresh`. A cache hit on
return requires no new first-thumbnail event because no capture completes.

- [ ] **Step 4: Route session lifetime from AppDelegate**

Replace the helper with:

```swift
private func cancelThumbnailLoadingIfNeeded(
    preservingCachedThumbnails: Bool = false
) {
    thumbnailLoader?.cancel(
        preservingCachedThumbnails: preservingCachedThumbnails
    )
}
```

At the start of both presentation functions, pass
`preservingCachedThumbnails: retainingSession`. When beginning a window refresh,
pass the same value. Keep `overlayController.onDismiss`, app termination, and
critical memory pressure on the default clearing behavior.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: PASS; retained transitions reuse a completed entry, while dismissal,
permission loss, ordinary cancel, and critical pressure still clear.

- [ ] **Step 6: Commit held-session reuse**

Run:

```bash
rtk git add SwitchTab/Services/WindowThumbnailService.swift \
  SwitchTab/AppDelegate.swift \
  SwitchTabTests/Services/WindowThumbnailTests.swift
rtk git commit -m "perf: reuse thumbnails within held sessions"
```

### Task 5: Verify measurements and document invariants

**Files:**
- Modify: `docs/AI_CONTEXT.md`
- Modify: `docs/superpowers/specs/2026-08-19-switcher-hot-path-performance-design.md` only if measured results require narrowing or dropping an optimization

- [ ] **Step 1: Repeat the native performance scenarios**

Record the same four Instruments scenarios used for the baseline. Compare
Accessibility Discovery median/p95, invocation median/p95, first-thumbnail
timing, count interval executions, and capture events.

Acceptance rules:

- keep AX batching only if 10-window and high-window-count median discovery is
  lower with no p95 regression;
- rapid count requests execute current plus newest only;
- returning to an unchanged window list in one held session produces no second
  capture event;
- three one-second idle samples remain 0.0% CPU and memory remains within normal
  variance of the approximately 25 MB baseline;
- cache bounds remain 32 entries and 64 MiB.

If AX batching does not meet its rule, revert only Task 2 and retain the tracing,
coalescing, and held-session work. Record evidence locally without committing
private application/window names.

- [ ] **Step 2: Update durable project context**

Add these invariants to `docs/AI_CONTEXT.md`:

```markdown
- Window discovery batches AX role, subrole, title, and minimized reads when the
  target supports it, falling back to individual reads without changing inclusion.
- Application window-count enrichment is latest-wins: stale queued scans do no AX
  work and stale in-flight results do not publish.
- Thumbnail cache reuse is limited to one held-modifier session; dismissal,
  preview-permission loss, app termination, and critical pressure clear it.
- Performance traces use local Points of Interest only and never record window
  titles, application names, or process identifiers.
```

- [ ] **Step 3: Run complete verification**

Run:

```bash
rtk swift build
rtk swift test
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
rtk proxy zsh -lc 'for test_script in scripts/tests/*-test.sh; do rtk proxy bash "$test_script" || exit; done'
rtk proxy zsh -lc 'for script in scripts/*.sh scripts/tests/*.sh; do rtk proxy bash -n "$script" || exit; done'
rtk proxy env SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
rtk git diff --check
```

Expected: all Swift tests pass, unsigned app build succeeds, every release
contract and shell syntax check passes, prepare-only succeeds, and diff check is
clean.

- [ ] **Step 4: Commit documentation**

Run:

```bash
rtk git add docs/AI_CONTEXT.md \
  docs/superpowers/specs/2026-08-19-switcher-hot-path-performance-design.md
rtk git commit -m "docs: record switcher performance invariants"
```

- [ ] **Step 5: Review final scope**

Run:

```bash
rtk git diff origin/main...HEAD --stat
rtk git diff origin/main...HEAD
rtk git status --short --branch
```

Expected: only tracing, AX batching, latest-wins count loading, held-session
thumbnail reuse, their tests, and the approved design/context documentation are
present; the worktree is clean.
