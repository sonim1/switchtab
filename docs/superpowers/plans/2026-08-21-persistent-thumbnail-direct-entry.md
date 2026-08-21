# Persistent Thumbnail Direct Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopening the window switcher directly shows a retained thumbnail immediately and refreshes it once in the new presentation generation.

**Architecture:** Keep completed thumbnails in the existing process-lifetime `WindowThumbnailStore` across normal overlay dismissal and both fresh presentation paths. Make `WindowThumbnailLoader` treat a cache hit as stale display data, not as a reason to skip the once-per-generation refresh. Keep explicit full clears for permission loss, app termination, SwitchTab termination, and critical memory pressure.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, Combine, XCTest-compatible legacy test runner

---

### Task 1: Make cache hits revalidate once per generation

**Files:**
- Modify: `SwitchTab/Services/WindowThumbnailService.swift`
- Modify: `SwitchTabTests/Services/WindowThumbnailTests.swift`

- [ ] **Step 1: Write the failing stale-while-revalidate test**

Add the test to `WindowThumbnailTests.run()` and implement:

```swift
@MainActor
static func testThumbnailLoaderRefreshesCachedThumbnailOnceInNewGeneration() async throws {
    let window = makeWindow(7)
    let stale = WindowThumbnail(pngData: Data("stale".utf8))
    let fresh = WindowThumbnail(pngData: Data("fresh".utf8))
    let store = WindowThumbnailStore()
    store.setThumbnail(stale, for: window.id)
    let capturer = FakeWindowThumbnailCapturer(thumbnails: [7: fresh])
    let loader = WindowThumbnailLoader(store: store, capturer: capturer)
    let permission = PermissionState(accessibility: .granted, screenRecording: .granted)

    loader.beginRefresh(permissionState: permission, preservingCachedThumbnails: true)
    loader.requestThumbnail(for: window, priority: .selected)
    loader.requestThumbnail(for: window, priority: .visible)
    await loader.waitForCurrentRefresh()
    loader.requestThumbnail(for: window, priority: .selected)
    await loader.waitForCurrentRefresh()

    try expectEqual(capturer.requestedWindowIdentifiers, [7])
    try expectEqual(store.thumbnail(for: window.id), fresh)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: failure because the current `containsThumbnail` guard prevents capture for a cached key.

- [ ] **Step 3: Implement generation-scoped demand tracking**

In `WindowThumbnailLoader`, replace the cache-hit exclusion with a `requestedWindowIDs` set:

```swift
private var requestedWindowIDs: Set<String> = []
```

Clear it in `beginRefresh` and `cancel`. In `requestThumbnail`, guard against `requestedWindowIDs` and `activeWindowIDs`, then insert the ID before enqueueing. Do not guard on `store.containsThumbnail`; the store continues supplying the stale image while capture runs.

Add a test-visible store accessor without changing the public UI API:

```swift
func thumbnail(for key: String) -> WindowThumbnail? {
    thumbnails[key]
}
```

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run `rtk swift test --filter SwitchTabTests/testAllSuites`.

Expected: all legacy suites pass and the cached thumbnail is replaced after one capture.

- [ ] **Step 5: Commit**

```bash
rtk git add SwitchTab/Services/WindowThumbnailService.swift SwitchTabTests/Services/WindowThumbnailTests.swift
rtk git commit -m "fix: revalidate retained window thumbnails"
```

### Task 2: Bound and invalidate the process-lifetime cache

**Files:**
- Modify: `SwitchTab/Services/WindowThumbnailService.swift`
- Modify: `SwitchTabTests/Services/WindowThumbnailTests.swift`

- [ ] **Step 1: Write failing store policy tests**

Add tests proving:

```swift
@MainActor
static func testThumbnailStoreDefaultLimitKeepsSixteenMostRecentEntries() throws {
    let store = WindowThumbnailStore()
    for index in 0..<17 {
        store.setThumbnail(WindowThumbnail(pngData: Data([UInt8(index)])), for: "42-\(index)")
    }
    try expectEqual(store.cachedEntryCount, 16)
    try expectEqual(store.containsThumbnail(for: "42-0"), false)
}

@MainActor
static func testThumbnailStoreRemovesWindowAndOwningProcessEntries() throws {
    let store = WindowThumbnailStore()
    store.setThumbnail(WindowThumbnail(pngData: Data("a".utf8)), for: "42-7")
    store.setThumbnail(WindowThumbnail(pngData: Data("b".utf8)), for: "42-8")
    store.setThumbnail(WindowThumbnail(pngData: Data("c".utf8)), for: "43-7")

    store.removeThumbnail(for: "42-7")
    store.removeThumbnails(ownerProcessIdentifier: 42)

    try expectEqual(store.cachedKeys, ["43-7"])
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Expected: default-count assertion fails at 17 and removal methods do not compile.

- [ ] **Step 3: Implement the approved limits and removal APIs**

Change defaults to 16 entries / 24 MiB and warning trim to 8 entries / 12 MiB. Add `removeThumbnail(for:)` and `removeThumbnails(ownerProcessIdentifier:)`, removing encoded data, decoded data, and access-order entries while publishing one change notification.

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run `rtk swift test --filter SwitchTabTests/testAllSuites`.

- [ ] **Step 5: Commit**

```bash
rtk git add SwitchTab/Services/WindowThumbnailService.swift SwitchTabTests/Services/WindowThumbnailTests.swift
rtk git commit -m "feat: bound persistent thumbnail cache"
```

### Task 3: Preserve on dismissal and clear only at invalidation boundaries

**Files:**
- Modify: `SwitchTab/AppDelegate.swift`
- Modify: `docs/AI_CONTEXT.md`

- [x] **Step 1: Change normal presentation lifecycle calls**

In both `presentWindowSwitcher` and `presentApplicationSwitcher`, cancel prior thumbnail work while preserving completed cache. Begin every permitted window refresh with `preservingCachedThumbnails: true`, regardless of `retainingSession`. Change overlay `onDismiss` to preserve completed cache.

- [x] **Step 2: Wire explicit invalidation**

Keep full clears by passing `preservingCachedThumbnails: false` from `applicationWillTerminate` and critical memory pressure. On confirmed window destruction remove its exact key. On workspace application termination remove every key with that process prefix. Permission-blocked `beginRefresh` continues clearing regardless of the preservation flag.

- [x] **Step 3: Update current project truth**

Replace the held-session-only thumbnail invariant in `docs/AI_CONTEXT.md` with process-lifetime bounded reuse, stale-while-revalidate behavior, and the explicit invalidation boundaries.

- [x] **Step 4: Run full verification**

```bash
rtk swift test
rtk swift build
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
```

Expected: 0 failures and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual behavior verification**

Run the built app with Accessibility and Screen Recording granted:

1. Open window mode directly and wait for thumbnails.
2. Dismiss by releasing the modifier.
3. Open window mode directly again.
4. Confirm the previous thumbnail appears on the first frame, then updates without selection or layout movement.
5. Confirm application-to-window held-session switching still behaves the same.

- [x] **Step 6: Commit**

```bash
rtk git add SwitchTab/AppDelegate.swift docs/AI_CONTEXT.md
rtk git commit -m "feat: retain thumbnails across switcher sessions"
```
