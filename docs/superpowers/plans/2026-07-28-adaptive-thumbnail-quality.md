# Adaptive Thumbnail Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve window-preview clarity in proportion to overlay size, keep selection stable after `Cmd+W` close reflow, and label the About build number before shipping `v1.0.9`.

**Architecture:** Derive a bounded 1.5× capture viewport from the existing layout metrics, then let one internal sizing policy convert each source window to an aspect-fill ScreenCaptureKit size. Preserve `SwitcherSession` as selection authority, but render tiles by stable window ID, reset hover after close reflow, and advance the existing scroll token. Keep About metadata sourced from the bundle while rendering version and build as separate labeled lines.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, XCTest/SwiftPM, Xcode, GitHub Actions, Sparkle, Cloudflare R2, Homebrew.

---

## File Map

- Modify `SwitchTab/Services/WindowThumbnailService.swift`: adaptive viewport and aspect-fill capture sizing; loader/capturer parameter flow.
- Modify `SwitchTab/AppDelegate.swift`: derive the current rendered thumbnail size and request 1.5× capture pixels.
- Modify `SwitchTabTests/Services/WindowThumbnailTests.swift`: pure sizing and loader-forwarding regressions.
- Modify `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`: stable item identity after deletion.
- Modify `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`: reset hover and force selected-item scrolling after confirmed close.
- Modify `SwitchTabTests/Services/SwitcherOverlayStateTests.swift`: first/middle/last neighbor rules.
- Modify `SwitchTabTests/Services/SwitcherOverlayPresentationPolicyTests.swift`: delayed close, close/reflow/scroll, stationary hover, and continued cycling regressions.
- Modify `SwitchTab/UI/About/AboutSwitchTabContent.swift`: separate version and labeled build strings.
- Modify `SwitchTab/UI/About/AboutSwitchTabView.swift`: separate primary and secondary metadata lines.
- Modify `SwitchTabTests/Services/AboutSwitchTabContentTests.swift`: exact About copy contracts.
- Already created `docs/superpowers/specs/2026-07-28-adaptive-thumbnail-quality-design.md`: approved design and release contract.

### Task 1: Adaptive 1.5× Thumbnail Capture

**Files:**
- Modify: `SwitchTab/Services/WindowThumbnailService.swift`
- Modify: `SwitchTab/AppDelegate.swift`
- Test: `SwitchTabTests/Services/WindowThumbnailTests.swift`

- [ ] **Step 1: Add failing pure sizing tests**

Change `WindowThumbnailTests.swift` to use `@testable import SwitchTab`, register the new tests in `run()`, and add:

```swift
static func testCaptureViewportTracksOverlayScale() throws {
    let minimum = SwitcherOverlayLayoutMetrics.metrics(for: OverlaySizeScale(0.7)).thumbnailSize
    let standard = SwitcherOverlayLayoutMetrics.metrics(for: .default).thumbnailSize
    let maximum = SwitcherOverlayLayoutMetrics.metrics(for: OverlaySizeScale(1.5)).thumbnailSize

    try expectEqual(WindowThumbnailCaptureSizing.viewportPixelSize(for: minimum), CGSize(width: 168, height: 116))
    try expectEqual(WindowThumbnailCaptureSizing.viewportPixelSize(for: standard), CGSize(width: 240, height: 165))
    try expectEqual(WindowThumbnailCaptureSizing.viewportPixelSize(for: maximum), CGSize(width: 360, height: 248))
}

static func testAspectFillCaptureSizingIsBounded() throws {
    try expectEqual(
        WindowThumbnailCaptureSizing.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: 1600, height: 900),
            viewportPixelSize: CGSize(width: 240, height: 165)
        ),
        WindowThumbnailPixelSize(width: 294, height: 165)
    )
    try expectEqual(
        WindowThumbnailCaptureSizing.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: 900, height: 1600),
            viewportPixelSize: CGSize(width: 240, height: 165)
        ),
        WindowThumbnailPixelSize(width: 240, height: 427)
    )
    try expectEqual(
        WindowThumbnailCaptureSizing.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: 5000, height: 500),
            viewportPixelSize: CGSize(width: 240, height: 165)
        ),
        WindowThumbnailPixelSize(width: 480, height: 48)
    )
    try expectEqual(
        WindowThumbnailCaptureSizing.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: 100, height: 60),
            viewportPixelSize: CGSize(width: 240, height: 165)
        ),
        WindowThumbnailPixelSize(width: 100, height: 60)
    )
}
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
```

Expected: FAIL because `WindowThumbnailCaptureSizing` and `WindowThumbnailPixelSize` do not exist.

- [ ] **Step 3: Implement the minimal sizing policy**

Add the following internal types near `WindowThumbnail` in `WindowThumbnailService.swift`:

```swift
struct WindowThumbnailPixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

enum WindowThumbnailCaptureSizing {
    static let qualityScale: CGFloat = 1.5
    static let maximumLongEdge: CGFloat = 480

    static func viewportPixelSize(for thumbnailPointSize: CGSize) -> CGSize {
        CGSize(
            width: max(1, (thumbnailPointSize.width * qualityScale).rounded(.up)),
            height: max(1, (thumbnailPointSize.height * qualityScale).rounded(.up))
        )
    }

    static func targetPixelSize(
        for sourceFrame: CGRect,
        viewportPixelSize: CGSize
    ) -> WindowThumbnailPixelSize {
        let sourceWidth = max(sourceFrame.width, 1)
        let sourceHeight = max(sourceFrame.height, 1)
        let viewportWidth = max(viewportPixelSize.width, 1)
        let viewportHeight = max(viewportPixelSize.height, 1)
        let scale = min(
            max(viewportWidth / sourceWidth, viewportHeight / sourceHeight),
            1,
            maximumLongEdge / max(sourceWidth, sourceHeight)
        )

        return WindowThumbnailPixelSize(
            width: min(Int(maximumLongEdge), max(1, Int((sourceWidth * scale).rounded(.up)))),
            height: min(Int(maximumLongEdge), max(1, Int((sourceHeight * scale).rounded(.up))))
        )
    }
}
```

Replace the capturer parameter name `maxPixelSize` with `viewportPixelSize`, pass it through both loader paths, and use:

```swift
let targetSize = WindowThumbnailCaptureSizing.targetPixelSize(
    for: captureWindow.frame,
    viewportPixelSize: viewportPixelSize
)
configuration.width = targetSize.width
configuration.height = targetSize.height
```

Remove the former private aspect-fit `targetPixelSize(for:maxPixelSize:)` implementation.

- [ ] **Step 4: Wire the persisted overlay scale into capture requests**

In `AppDelegate.showCurrentAppSwitcher`, immediately before `thumbnailLoaderForRefresh().refresh`, derive and pass the viewport:

```swift
let thumbnailPointSize = SwitcherOverlayLayoutMetrics.metrics(
    for: applicationSettingsStore.overlaySizeScale
).thumbnailSize
let viewportPixelSize = WindowThumbnailCaptureSizing.viewportPixelSize(
    for: thumbnailPointSize
)
thumbnailLoaderForRefresh().refresh(
    windows: windows,
    permissionState: permissionState,
    viewportPixelSize: viewportPixelSize
)
```

Keep a default viewport of `CGSize(width: 240, height: 165)` on `WindowThumbnailLoader.refresh` only for existing direct callers and tests; production always supplies the current size.

- [ ] **Step 5: Verify loader forwarding, cancellation, and cache behavior**

Extend `FakeWindowThumbnailCapturer` with:

```swift
private(set) var requestedViewportPixelSizes: [CGSize] = []

func captureThumbnail(
    for window: WindowItem,
    viewportPixelSize: CGSize
) async -> WindowThumbnail? {
    requestedWindowIdentifiers.append(window.windowIdentifier)
    requestedViewportPixelSizes.append(viewportPixelSize)
    return thumbnails[window.windowIdentifier]
}
```

Pass `CGSize(width: 360, height: 248)` in the granted-permission loader test and assert that exact size was forwarded once. Run:

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
```

Expected: PASS, 18 XCTest cases and zero failures.

- [ ] **Step 6: Commit Task 1**

```bash
rtk git add SwitchTab/Services/WindowThumbnailService.swift SwitchTab/AppDelegate.swift SwitchTabTests/Services/WindowThumbnailTests.swift
rtk git commit -m "feat: adapt thumbnail capture quality to overlay size"
```

### Task 2: Stable Selection After `Cmd+W`

**Files:**
- Modify: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- Modify: `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayStateTests.swift`
- Test: `SwitchTabTests/Services/SwitcherOverlayPresentationPolicyTests.swift`

- [ ] **Step 1: Add failing session-neighbor tests**

Register and add the following state tests:

```swift
static func testRemovingSelectedItemChoosesNearestSurvivor() throws {
    let items = [
        SwitcherListItem(id: "a", title: "A", subtitle: nil),
        SwitcherListItem(id: "b", title: "B", subtitle: nil),
        SwitcherListItem(id: "c", title: "C", subtitle: nil)
    ]

    var middle = SwitcherSession(mode: .currentAppWindowSwitching, items: items, selectedIndex: 1)
    try expectTrue(middle.removeItem(withID: "b"))
    try expectEqual(middle.selectedItem?.id, "c")

    var last = SwitcherSession(mode: .currentAppWindowSwitching, items: items, selectedIndex: 2)
    try expectTrue(last.removeItem(withID: "c"))
    try expectEqual(last.selectedItem?.id, "b")

    var first = SwitcherSession(mode: .currentAppWindowSwitching, items: items, selectedIndex: 0)
    try expectTrue(first.removeItem(withID: "a"))
    try expectEqual(first.selectedItem?.id, "b")
}

static func testDelayedRemovalPreservesMovedSelectionIdentity() throws {
    var session = SwitcherSession(
        mode: .currentAppWindowSwitching,
        items: [
            SwitcherListItem(id: "a", title: "A", subtitle: nil),
            SwitcherListItem(id: "b", title: "B", subtitle: nil),
            SwitcherListItem(id: "c", title: "C", subtitle: nil)
        ],
        selectedIndex: 1
    )
    try expectTrue(session.moveSelection(by: 1))
    try expectTrue(session.removeItem(withID: "b"))
    try expectEqual(session.selectedItem?.id, "c")
    try expectEqual(session.selectedIndex, 1)
}
```

- [ ] **Step 2: Add a failing controller regression for reflow**

Add `testConfirmedCloseRescrollsAndBlocksStationaryHover` to `SwitcherOverlayPresentationPolicyTests`:

```swift
static func testConfirmedCloseRescrollsAndBlocksStationaryHover() throws {
    let controller = SwitcherOverlayController(
        thumbnailStore: WindowThumbnailStore(),
        eventTapBackend: RecordingSwitcherOverlayEventTapBackend(),
        eventSink: RecordingSwitcherOverlayEventSink()
    )
    var closeConfirmation: (id: String, presentationID: UInt64)?
    var confirmedIDs: [String] = []
    controller.present(
        mode: .currentAppWindowSwitching,
        items: closeTestItems(count: 3),
        selectedIndex: 1,
        onClose: { closeConfirmation = ($0.id, $1) },
        onConfirm: { confirmedIDs.append($0.id) }
    )
    controller.enableHoverSelectionIfPointerMoved(to: CGPoint(
        x: NSEvent.mouseLocation.x + 400,
        y: NSEvent.mouseLocation.y + 400
    ))
    let tokenBeforeClose = controller.presentationScrollToken
    _ = controller.handle(.closeSelected)
    guard let token = closeConfirmation else {
        throw TestFailure.failed("Expected close confirmation")
    }

    controller.confirmWindowDisappeared(id: token.id, presentationID: token.presentationID)
    try expectEqual(controller.presentationScrollToken, tokenBeforeClose + 1)

    controller.hoverItem(at: 0)
    _ = controller.handle(.confirm)
    try expectEqual(confirmedIDs, ["window-2"])
}
```

Update `testHoverRemainsCorrectAfterConfirmedCloseRerender` so it explicitly calls `enableHoverSelectionIfPointerMoved` again after confirmation before expecting hover to change selection.

- [ ] **Step 3: Run the suite and verify RED**

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
```

Expected: FAIL because confirmed close does not advance the scroll token and stationary hover remains enabled.

- [ ] **Step 4: Implement close-reflow stabilization**

In `SwitcherIconStripView`, replace transient index identity:

```swift
ForEach(Array(items.enumerated()), id: \.element.id) { indexedItem in
    let index = indexedItem.offset
    let item = indexedItem.element
    SwitcherWindowTile(
        item: item,
        index: index,
        isSelected: index == selectedIndex,
        showsThumbnails: showsThumbnails,
        hoverEnabled: hoverEnabled,
        layoutMetrics: layoutMetrics,
        thumbnailStore: thumbnailStore,
        applicationIconStore: applicationIconStore,
        onConfirm: onConfirm,
        onClose: onClose,
        onHover: onHover
    )
    .id(item.id)
}
```

In the `.updated` branch of `confirmWindowDisappeared`, before layout update, add:

```swift
presentationModel.setHoverSelectionEnabled(false)
presentationPointerLocation = NSEvent.mouseLocation
presentationModel.advanceScrollToken()
updatePresentationLayout(session: session, panel: panel)
```

Do not change `SwitcherSession.removeItem(withID:)`; the new state tests document its already-correct identity and neighbor behavior.

- [ ] **Step 5: Add continued-cycle coverage and verify GREEN**

After the stationary-hover assertion, start a fresh presentation and add this exact continued-cycle sequence:

```swift
closeConfirmation = nil
confirmedIDs = []
controller.present(
    mode: .currentAppWindowSwitching,
    items: closeTestItems(count: 3),
    selectedIndex: 1,
    onClose: { closeConfirmation = ($0.id, $1) },
    onConfirm: { confirmedIDs.append($0.id) }
)
_ = controller.handle(.closeSelected)
guard let cycleToken = closeConfirmation else {
    throw TestFailure.failed("Expected continued-cycle close confirmation")
}
controller.confirmWindowDisappeared(
    id: cycleToken.id,
    presentationID: cycleToken.presentationID
)
_ = controller.handle(.moveDown)
_ = controller.handle(.confirm)
try expectEqual(confirmedIDs, ["window-0"])
```

This proves the corrected `window-2` selection continues cycling without a skip.

Run:

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
```

Expected: PASS, including the existing delayed stable-ID close and hover tests.

- [ ] **Step 6: Commit Task 2**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherIconStripView.swift SwitchTab/UI/Overlay/SwitcherOverlayController.swift SwitchTabTests/Services/SwitcherOverlayStateTests.swift SwitchTabTests/Services/SwitcherOverlayPresentationPolicyTests.swift
rtk git commit -m "fix: keep selection stable after closing a window"
```

### Task 3: Separate About Version and Build Number

**Files:**
- Modify: `SwitchTab/UI/About/AboutSwitchTabContent.swift`
- Modify: `SwitchTab/UI/About/AboutSwitchTabView.swift`
- Test: `SwitchTabTests/Services/AboutSwitchTabContentTests.swift`

- [ ] **Step 1: Write failing copy tests**

Replace `testFormatsVersionWithBuild` with:

```swift
static func testFormatsVersionAndBuildSeparately() throws {
    let content = AboutSwitchTabContent(
        version: "1.2.3",
        build: "45",
        usageDashboard: .empty
    )

    try expectEqual(content.versionLine, "Version 1.2.3")
    try expectEqual(content.buildLine, "Build Number 45")
}

static func testOmitsEmptyBuildLine() throws {
    let content = AboutSwitchTabContent(
        version: "1.2.3",
        build: "",
        usageDashboard: .empty
    )

    try expectEqual(content.versionLine, "Version 1.2.3")
    try expectEqual(content.buildLine, nil)
}
```

Register both tests in `run()`.

- [ ] **Step 2: Run the suite and verify RED**

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
```

Expected: FAIL because `versionLine` still includes `(45)` and `buildLine` does not exist.

- [ ] **Step 3: Implement separate content strings**

Use:

```swift
public var versionLine: String {
    "Version \(version)"
}

public var buildLine: String? {
    guard !build.isEmpty else {
        return nil
    }
    return "Build Number \(build)"
}
```

In `AboutSwitchTabView`, replace the single version `Text` with:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(content.versionLine)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white.opacity(0.72))
    if let buildLine = content.buildLine {
        Text(buildLine)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.52))
    }
}
```

- [ ] **Step 4: Verify GREEN and commit**

```bash
rtk test swift test --filter SwitchTabTests/testAllSuites
rtk git add SwitchTab/UI/About/AboutSwitchTabContent.swift SwitchTab/UI/About/AboutSwitchTabView.swift SwitchTabTests/Services/AboutSwitchTabContentTests.swift
rtk git commit -m "fix: label the About build number"
```

Expected: tests pass and About content exposes `Version 1.0.9` plus `Build Number 10` once automatic versioning runs.

### Task 4: Full Verification and Review Gate

**Files:**
- Verify all changed production, test, spec, and plan files.
- Evidence: `.omo/evidence/adaptive-thumbnail-quality/` if the reviewer uses OMO-style artifacts; evidence remains git-ignored.

- [ ] **Step 1: Run all release contracts**

```bash
rtk test bash -lc 'set -euo pipefail; for test_script in scripts/tests/*.sh; do rtk test bash "$test_script"; done'
```

Expected: all 13 contract scripts exit 0.

- [ ] **Step 2: Run the complete Swift suite with visible XCTest evidence**

```bash
rtk proxy swift test
```

Expected: `Executed 18 tests, with 0 failures`.

- [ ] **Step 3: Build the unsigned app**

```bash
rtk test xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Expected: exit 0 and `BUILD SUCCEEDED` in unfiltered evidence.

- [ ] **Step 4: Validate bounded quality and interaction behavior**

Confirm the sizing tests prove `168×116`, `240×165`, and `360×248` viewports; common 16:9 captures remain below 110,000 pixels; extreme long edges stop at 480. If TCC permissions permit, open multiple windows, cycle, close a middle window with `Cmd+W`, continue cycling, and inspect thumbnail clarity at minimum/default/maximum. If TCC blocks the smoke test, record the exact permission boundary and do not modify the TCC database.

- [ ] **Step 5: Run hygiene and independent review**

```bash
rtk git diff --check origin/main...HEAD
rtk git status --short --branch --untracked-files=all
```

Expected: no whitespace errors and no uncommitted files. Review the complete `origin/main...HEAD` diff against the approved spec; require score 99/100 or higher and no blocker before publishing.

### Task 5: PR, Automatic Versioning, and `v1.0.9` Release

**Files:**
- Do not manually edit `SwitchTab.xcodeproj/project.pbxproj`; the existing version GitHub App owns the bump.
- Verify `.github/workflows/ci.yml`, `.github/workflows/automatic-release.yml`, and `.github/workflows/release.yml` through their existing contract tests only.

- [ ] **Step 1: Push and create the PR**

```bash
rtk git push -u origin codex/adaptive-thumbnail-quality
rtk gh pr create --repo sonim1/switchtab --base main --head codex/adaptive-thumbnail-quality --title "Improve thumbnail clarity and close selection stability" --body-file /tmp/switchtab-v109-pr-body.md
```

Before running the command, create `/tmp/switchtab-v109-pr-body.md` with `apply_patch` and this exact structure, replacing only the evidence counts with observed values:

```markdown
## Summary
- adapt thumbnail capture to the rendered overlay size at 1.5×, bounded to a 480 px long edge
- keep keyboard selection stable after Cmd+W close reflow
- show version and build number on separate About lines

## Validation
- `swift test --filter SwitchTabTests/testAllSuites`
- `swift test`
- all release contract scripts under `scripts/tests/`
- unsigned Debug Xcode build
```

Expected: a ready PR targeting `main`.

- [ ] **Step 2: Verify the bot-owned version commit and CI**

Poll every 30 seconds:

```bash
pr_url="$(rtk gh pr view --repo sonim1/switchtab --json url --jq .url)"
pr_number="${pr_url##*/}"
rtk gh pr checks "$pr_number" --repo sonim1/switchtab
```

Expected: the bot adds `chore: bump version to 1.0.9 (10)` and `policy`, `version`, and `verify` all pass. Fetch and fast-forward the local branch to the bot commit before final status checks.

- [ ] **Step 3: Merge only after the gate is green**

```bash
rtk gh pr merge "$pr_number" --repo sonim1/switchtab --squash --delete-branch
rtk gh pr view "$pr_number" --repo sonim1/switchtab --json state,mergedAt,mergeCommit,url
```

Expected: `state` is `MERGED`; record the exact 40-hex merge SHA.

- [ ] **Step 4: Monitor both release workflows**

Record the merge SHA, resolve workflow run IDs by name and SHA, then watch each run:

```bash
merge_sha="$(rtk gh pr view "$pr_number" --repo sonim1/switchtab --json mergeCommit --jq .mergeCommit.oid)"
automatic_run_id="$(rtk gh run list --repo sonim1/switchtab --workflow 'Automatic Release' --commit "$merge_sha" --limit 1 --json databaseId --jq '.[0].databaseId')"
rtk gh run watch "$automatic_run_id" --repo sonim1/switchtab --exit-status
release_run_id="$(rtk gh run list --repo sonim1/switchtab --workflow Release --commit "$merge_sha" --limit 1 --json databaseId --jq '.[0].databaseId')"
rtk gh run watch "$release_run_id" --repo sonim1/switchtab --exit-status
```

Expected: `verify`, `release`, and `notify` all conclude `success`.

- [ ] **Step 5: Verify the public release chain**

Verify:

```bash
rtk gh release view v1.0.9 --repo sonim1/switchtab --json tagName,name,publishedAt,url,assets
rtk git fetch origin tag v1.0.9
rtk git cat-file -t v1.0.9
rtk git rev-parse 'v1.0.9^{}'
rtk proxy curl -fsSL https://updates.switchtab.royjen.com/appcast.xml
```

Expected:

- `v1.0.9` is an annotated tag peeled to the recorded merge SHA.
- GitHub Release contains `SwitchTab-1.0.9-10.dmg`, its `.sha256`, and `release-manifest.json`.
- The downloaded checksum verifies, `hdiutil verify` succeeds, and `xcrun stapler validate` succeeds.
- The public appcast reports short version `1.0.9`, build `10`, and enclosure `SwitchTab-1.0.9-10.dmg`.
- The public R2 DMG SHA-256 equals the release manifest.
- The Homebrew tap update PR for `switchtab 1.0.9` passes CI and merges.

Only after every assertion above passes may the release be reported complete.
