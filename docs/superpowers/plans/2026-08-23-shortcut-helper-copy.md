# Shortcut Helper Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the redundant shortcut-recording helper text while a row is idle, while retaining the recording prompt and accessibility instructions.

**Architecture:** Keep the decision in the existing `ShortcutSettingsRowPresentation` value so it can be tested without rendering SwiftUI. The row conditionally renders the returned text; all keycap and accessibility modifiers remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager, Xcode

---

## File Structure

- Modify `SwitchTab/UI/Settings/ShortcutSettingsView.swift`: expose the helper-copy presentation rule and conditionally render it.
- Modify `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`: verify idle and recording helper-copy behavior.

### Task 1: Remove Idle Shortcut Helper Copy

**Files:**
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsView.swift:490-610`
- Test: `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift:88-126`

- [x] **Step 1: Write the failing presentation test**

Add these assertions inside `testShortcutRowPresentationUsesModeSpecificLabelsAndStatus()` after creating `enabledPresentation`:

```swift
try expectEqual(enabledPresentation.helperText(isRecording: false), nil)
try expectEqual(enabledPresentation.helperText(isRecording: true), "Press shortcut now")
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
```

Expected: compilation fails because `ShortcutSettingsRowPresentation` has no `helperText(isRecording:)` member.

- [x] **Step 3: Add the minimal presentation rule**

Add to `ShortcutSettingsRowPresentation`:

```swift
func helperText(isRecording: Bool) -> String? {
    isRecording ? "Press shortcut now" : nil
}
```

- [x] **Step 4: Render helper copy only when present**

Replace the unconditional helper `Text` in `ShortcutRecorderRow` with:

```swift
if let helperText = presentation.helperText(isRecording: isRecording) {
    Text(helperText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(layout.titleLineLimit)
        .truncationMode(.tail)
}
```

Do not change the keycap button or its accessibility modifiers.

- [x] **Step 5: Run focused and full verification**

Run:

```bash
rtk swift test --filter SwitchTabTests/testAllSuites
rtk swift test
rtk swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer rtk xcodebuild \
  -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
```

Expected: all tests pass with one intentional private benchmark skip, both builds succeed, and the diff check reports no whitespace errors.

- [x] **Step 6: Commit the implementation**

```bash
rtk git add SwitchTab/UI/Settings/ShortcutSettingsView.swift \
  SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift \
  docs/superpowers/plans/2026-08-23-shortcut-helper-copy.md
rtk git commit -m "fix: remove redundant shortcut helper copy"
```
