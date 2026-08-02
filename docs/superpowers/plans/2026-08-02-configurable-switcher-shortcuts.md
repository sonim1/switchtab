# Configurable Switcher Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both switcher modes a unified enabled state and configurable shortcut, defaulting fresh installs to enabled `Cmd + \`` and enabled `Cmd + Tab`.

**Architecture:** Persist two `SwitcherShortcutConfiguration` values in one versioned payload and expose them through one `ShortcutSettingsViewModel`. Keep the existing window hotkey and application EventTap registrars separate because their input semantics differ, but route configuration changes through the same store and settings UI.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreGraphics EventTap, UserDefaults, XCTest, Xcode 16.

---

## File map

- `SwitchTab/Models/ShortcutSetting.swift`: add the unified per-mode configuration value and defaults.
- `SwitchTab/Services/ShortcutSettingsStore.swift`: replace the window-only payload with versioned dual-mode persistence and legacy migration.
- `SwitchTab/Services/ApplicationSettingsStore.swift`: retain only the legacy Cmd-Tab key needed by migration; remove active ownership of app switching.
- `SwitchTab/Services/ShortcutValidationService.swift`: validate dynamic mode-to-mode conflicts instead of reserving fixed Cmd-Tab values.
- `SwitchTab/Services/ApplicationSwitchingHotkeyController.swift`: register a supplied forward shortcut and its Shift reverse variant.
- `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`: own both configurations, per-mode errors, toggles, recording, reset, persistence, and rollback.
- `SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift`: remove legacy app switching state.
- `SwitchTab/UI/Settings/ShortcutSettingsView.swift`: render two matching configurable rows with status text and toggles.
- `SwitchTab/UI/Settings/SettingsWindowController.swift`: inject unified shortcut callbacks.
- `SwitchTab/AppDelegate.swift`: load, suspend, register, restore, and dismiss both modes from unified configuration.
- `SwitchTabTests/Services/ShortcutSettingsStoreTests.swift`: cover defaults, migration, persistence, and ViewModel behavior.
- `SwitchTabTests/Services/ShortcutValidationTests.swift`: cover configurable forward/reverse conflicts.
- `SwitchTabTests/Services/ApplicationSwitchingTests.swift`: cover configurable EventTap registration.
- `SwitchTabTests/Services/ApplicationSettingsStoreTests.swift`: remove tests for ownership moved to `ShortcutSettingsStore`.
- `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`: add lightweight source contracts for settings wiring and recording lifecycle.

### Task 1: Unified configuration model and migration

**Files:**
- Modify: `SwitchTab/Models/ShortcutSetting.swift`
- Modify: `SwitchTab/Services/ShortcutSettingsStore.swift`
- Test: `SwitchTabTests/Services/ShortcutSettingsStoreTests.swift`

- [ ] **Step 1: Write failing default and migration tests**

Add these calls to `ShortcutSettingsStoreTests.run()` and implement the tests:

```swift
try testFreshInstallLoadsBothModesEnabled()
try testLegacyInstallPreservesWindowShortcutAndExplicitAppState()
try testLegacyFootprintWithoutExplicitAppStateKeepsAppSwitchingDisabled()
try testUnifiedPayloadWinsOverLegacyValues()
```

```swift
static func testFreshInstallLoadsBothModesEnabled() throws {
    let store = ShortcutSettingsStore(userDefaults: makeDefaults())
    let configurations = store.loadConfigurations()

    try expectEqual(configurations, [.defaultCurrentAppWindows, .defaultApplicationSwitching])
    try expectTrue(configurations.allSatisfy(\.isEnabled))
}

static func testLegacyInstallPreservesWindowShortcutAndExplicitAppState() throws {
    let defaults = makeDefaults()
    let legacyWindow = ShortcutSetting.defaultCurrentAppWindowSwitching.replacingWithValidation(
        keyEquivalent: "K",
        modifiers: ["command"],
        isUsable: true
    )
    defaults.set(try JSONEncoder().encode(legacyWindow), forKey: ShortcutSettingsStore.legacyWindowShortcutStorageKey)
    defaults.set(false, forKey: ApplicationSettingsStore.replacesCommandTabKey)

    let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

    try expectEqual(configurations[0], SwitcherShortcutConfiguration(mode: .currentAppWindowSwitching, isEnabled: true, shortcut: legacyWindow))
    try expectEqual(configurations[1], SwitcherShortcutConfiguration(mode: .applicationSwitching, isEnabled: false, shortcut: .defaultApplicationSwitching))
}

static func testLegacyFootprintWithoutExplicitAppStateKeepsAppSwitchingDisabled() throws {
    let defaults = makeDefaults()
    defaults.set(["finder"], forKey: "SwitchTab.recency.currentAppWindowSwitching")

    let configurations = ShortcutSettingsStore(userDefaults: defaults).loadConfigurations()

    try expectFalse(configurations[1].isEnabled)
}

static func testUnifiedPayloadWinsOverLegacyValues() throws {
    let defaults = makeDefaults()
    let store = ShortcutSettingsStore(userDefaults: defaults)
    let saved = [
        SwitcherShortcutConfiguration(mode: .currentAppWindowSwitching, isEnabled: false, shortcut: .defaultCurrentAppWindowSwitching),
        SwitcherShortcutConfiguration(mode: .applicationSwitching, isEnabled: true, shortcut: .defaultApplicationSwitching)
    ]
    try store.saveConfigurations(saved)
    defaults.set(true, forKey: ApplicationSettingsStore.replacesCommandTabKey)

    try expectEqual(store.loadConfigurations(), saved)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: compile failure because `SwitcherShortcutConfiguration`, `loadConfigurations`, and `saveConfigurations` do not exist.

- [ ] **Step 3: Add the configuration model**

Add to `ShortcutSetting.swift`:

```swift
public struct SwitcherShortcutConfiguration: Codable, Equatable, Sendable {
    public let mode: SwitcherMode
    public var isEnabled: Bool
    public var shortcut: ShortcutSetting

    public init(mode: SwitcherMode, isEnabled: Bool, shortcut: ShortcutSetting) {
        self.mode = mode
        self.isEnabled = isEnabled
        self.shortcut = shortcut
    }

    public static let defaultCurrentAppWindows = SwitcherShortcutConfiguration(
        mode: .currentAppWindowSwitching,
        isEnabled: true,
        shortcut: .defaultCurrentAppWindowSwitching
    )

    public static let defaultApplicationSwitching = SwitcherShortcutConfiguration(
        mode: .applicationSwitching,
        isEnabled: true,
        shortcut: .defaultApplicationSwitching
    )

    public static func defaultValue(for mode: SwitcherMode) -> SwitcherShortcutConfiguration {
        switch mode {
        case .currentAppWindowSwitching: .defaultCurrentAppWindows
        case .applicationSwitching: .defaultApplicationSwitching
        }
    }
}
```

- [ ] **Step 4: Implement versioned storage and one-time migration**

Replace the window-only load/save API in `ShortcutSettingsStore` with:

```swift
public static let legacyWindowShortcutStorageKey = "SwitchTab.shortcut.currentAppWindowSwitching"
private static let configurationsStorageKey = "SwitchTab.shortcut.configurations"
private static let currentPayloadVersion = 1

private struct StoredConfigurations: Codable {
    let version: Int
    let configurations: [SwitcherShortcutConfiguration]
}

public func loadConfigurations() -> [SwitcherShortcutConfiguration] {
    if let data = userDefaults.data(forKey: Self.configurationsStorageKey),
       let payload = try? decoder.decode(StoredConfigurations.self, from: data),
       payload.version == Self.currentPayloadVersion,
       Set(payload.configurations.map(\.mode.rawValue)) == Set(SwitcherMode.allCases.map(\.rawValue)) {
        return SwitcherMode.allCases.compactMap { mode in
            payload.configurations.first { $0.mode == mode }
        }
    }

    let migrated = migratedConfigurations()
    try? saveConfigurations(migrated)
    return migrated
}

public func saveConfigurations(_ configurations: [SwitcherShortcutConfiguration]) throws {
    let ordered = SwitcherMode.allCases.compactMap { mode in
        configurations.first { $0.mode == mode }
    }
    let payload = StoredConfigurations(version: Self.currentPayloadVersion, configurations: ordered)
    let data = try encoder.encode(payload)
    guard userDefaults.data(forKey: Self.configurationsStorageKey) != data else { return }
    userDefaults.set(data, forKey: Self.configurationsStorageKey)
}

private func migratedConfigurations() -> [SwitcherShortcutConfiguration] {
    let legacyWindow = load(
        key: Self.legacyWindowShortcutStorageKey,
        defaultSetting: .defaultCurrentAppWindowSwitching
    )
    let explicitApplicationState = userDefaults.object(
        forKey: ApplicationSettingsStore.replacesCommandTabKey
    ) as? Bool
    let applicationEnabled = explicitApplicationState ?? !hasLegacyFootprint
    return [
        SwitcherShortcutConfiguration(mode: .currentAppWindowSwitching, isEnabled: true, shortcut: legacyWindow),
        SwitcherShortcutConfiguration(mode: .applicationSwitching, isEnabled: applicationEnabled, shortcut: .defaultApplicationSwitching)
    ]
}

private var hasLegacyFootprint: Bool {
    [
        Self.legacyWindowShortcutStorageKey,
        Self.registrationMessagesKey,
        ApplicationSettingsStore.menuBarIconVisibleKey,
        ApplicationSettingsStore.overlaySizeScaleKey,
        ApplicationSettingsStore.overlaySizeKey,
        "SwitchTab.recency.currentAppWindowSwitching",
        "SwitchTab.recency.applicationSwitching"
    ].contains { userDefaults.object(forKey: $0) != nil }
}
```

Make `SwitcherMode` conform to `CaseIterable`. Keep legacy keys in place for rollback.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: all tests pass after existing callers are temporarily served by deprecated `load()` and `save(_:)` wrappers delegating to the window configuration. Remove the wrappers in Task 4 after callers move.

Use these temporary wrappers:

```swift
public func load() -> ShortcutSetting {
    loadConfigurations().first {
        $0.mode == .currentAppWindowSwitching
    }?.shortcut ?? .defaultCurrentAppWindowSwitching
}

public func save(_ setting: ShortcutSetting) throws {
    var configurations = loadConfigurations()
    guard let index = configurations.firstIndex(where: {
        $0.mode == .currentAppWindowSwitching
    }) else { return }
    configurations[index].shortcut = setting
    try saveConfigurations(configurations)
}
```

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add SwitchTab/Models/ShortcutSetting.swift SwitchTab/Models/SwitcherMode.swift SwitchTab/Services/ShortcutSettingsStore.swift SwitchTabTests/Services/ShortcutSettingsStoreTests.swift
rtk git commit -m "feat: persist unified switcher shortcuts"
```

### Task 2: Unified ViewModel and dynamic conflict validation

**Files:**
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`
- Modify: `SwitchTab/Services/ShortcutValidationService.swift`
- Modify: `SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift`
- Modify: `SwitchTab/Services/ApplicationSettingsStore.swift`
- Test: `SwitchTabTests/Services/ShortcutSettingsStoreTests.swift`
- Test: `SwitchTabTests/Services/ShortcutValidationTests.swift`
- Test: `SwitchTabTests/Services/ApplicationSettingsStoreTests.swift`

- [ ] **Step 1: Write failing ViewModel and conflict tests**

Add tests proving:

```swift
static func testViewModelTogglesOneModeWithoutChangingTheOther() throws {
    let defaults = makeDefaults()
    let viewModel = ShortcutSettingsViewModel(store: ShortcutSettingsStore(userDefaults: defaults))

    viewModel.setEnabled(false, for: .currentAppWindowSwitching)

    try expectFalse(viewModel.configuration(for: .currentAppWindowSwitching).isEnabled)
    try expectTrue(viewModel.configuration(for: .applicationSwitching).isEnabled)
}

static func testDisabledModeShortcutRemainsEditable() throws {
    let viewModel = ShortcutSettingsViewModel(store: ShortcutSettingsStore(userDefaults: makeDefaults()))
    viewModel.setEnabled(false, for: .applicationSwitching)

    let didRecord = viewModel.record(
        capture: ShortcutCapture(keyEquivalent: "Space", modifiers: ["option"], keyCode: 49),
        for: .applicationSwitching
    )

    try expectTrue(didRecord)
    try expectFalse(viewModel.configuration(for: .applicationSwitching).isEnabled)
    try expectEqual(viewModel.configuration(for: .applicationSwitching).shortcut.displayText, "Option + Space")
}

static func testApplicationReverseVariantCannotCollideWithWindowShortcut() throws {
    let validator = ShortcutValidationService()
    let application = ShortcutSetting(
        id: "application-switching",
        mode: .applicationSwitching,
        keyEquivalent: "K",
        modifiers: ["command"],
        isUsable: true
    )
    let window = ShortcutSetting(
        id: "current-app-window-switching",
        mode: .currentAppWindowSwitching,
        keyEquivalent: "K",
        modifiers: ["command", "shift"],
        isUsable: true
    )

    try expectEqual(
        validator.validate(application.reverseVariant(id: "application-switching-reverse"), existing: [window]),
        .duplicate
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: compile failures for mode-aware ViewModel methods and a failing conflict assertion because fixed Cmd-Tab reservation still owns validation policy.

- [ ] **Step 3: Replace fixed reservation with dynamic validation**

Remove `applicationSwitchingReservedShortcuts` from `ShortcutValidationService`. Keep unusable, modifier, and supplied-existing checks. In the ViewModel, validate both candidate directions against both directions of the other mode:

```swift
private func validationResult(
    for candidate: ShortcutSetting,
    other: ShortcutSetting
) -> ShortcutValidationResult {
    let otherReverse = other.reverseVariant(id: "\(other.id)-reverse")
    let existing = [other, otherReverse]
    let forward = validator.validate(candidate, existing: existing)
    guard forward == .valid else { return forward }
    return validator.validate(
        candidate.reverseVariant(id: "\(candidate.id)-reverse"),
        existing: existing
    )
}
```

- [ ] **Step 4: Implement mode-aware ViewModel mutations**

Replace the single `currentAppWindowShortcut` ownership with two configurations loaded from the unified store. Expose:

```swift
public func configuration(for mode: SwitcherMode) -> SwitcherShortcutConfiguration
public func errorMessage(for mode: SwitcherMode) -> String?
public func setEnabled(_ enabled: Bool, for mode: SwitcherMode)
public func record(capture: ShortcutCapture, for mode: SwitcherMode) -> Bool
public func resetToDefault(for mode: SwitcherMode) -> Bool
```

Use two callbacks so registration semantics stay explicit:

```swift
private let onShortcutChanged: (
    SwitcherShortcutConfiguration,
    SwitcherShortcutConfiguration
) -> Bool
private let onEnabledChanged: (SwitcherShortcutConfiguration) -> Void
```

`setEnabled` saves and publishes before calling `onEnabledChanged`. `record` validates and calls `onShortcutChanged` before saving; if saving fails after registration, call `onShortcutChanged(previous, candidate)` to restore the live registration. `resetToDefault` records the mode default shortcut without changing `isEnabled`.

- [ ] **Step 5: Remove legacy app-switch ownership**

Delete `replacesCommandTab`, `saveReplacesCommandTab`, `.commandTabReplacementDidChange`, and matching ViewModel properties/methods. Keep only `ApplicationSettingsStore.replacesCommandTabKey` with a legacy migration comment. Remove the obsolete tests from `ApplicationSettingsStoreTests`.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: all tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
rtk git add SwitchTab/Services/ShortcutValidationService.swift SwitchTab/Services/ApplicationSettingsStore.swift SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift SwitchTab/UI/Settings/ApplicationSettingsViewModel.swift SwitchTabTests/Services/ShortcutSettingsStoreTests.swift SwitchTabTests/Services/ShortcutValidationTests.swift SwitchTabTests/Services/ApplicationSettingsStoreTests.swift
rtk git commit -m "feat: manage both switcher shortcuts together"
```

### Task 3: Configurable application EventTap registration

**Files:**
- Modify: `SwitchTab/Services/ApplicationSwitchingHotkeyController.swift`
- Test: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **Step 1: Write a failing custom shortcut registration test**

```swift
static func testControllerRegistersCustomForwardAndShiftReverseShortcuts() throws {
    let registrar = ApplicationSwitchingRecordingRegistrar()
    let controller = ApplicationSwitchingHotkeyController(
        hotkeyService: HotkeyService(registrar: registrar)
    )
    let custom = ShortcutSetting(
        id: "application-switching",
        mode: .applicationSwitching,
        keyEquivalent: "Space",
        keyCode: 49,
        modifiers: ["option"],
        isUsable: true
    )

    try expectTrue(controller.updateRegistration(setting: custom, enabled: true, forwardHandler: {}, reverseHandler: {}))
    try expectEqual(registrar.attemptedSettings[0], custom)
    try expectEqual(
        registrar.attemptedSettings[1],
        custom.reverseVariant(id: "application-switching-reverse")
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: compile failure because `updateRegistration` does not accept `setting`.

- [ ] **Step 3: Register the supplied setting**

Change the controller API to:

```swift
public func updateRegistration(
    setting: ShortcutSetting,
    enabled: Bool,
    forwardHandler: @escaping () -> Void,
    reverseHandler: @escaping () -> Void
) -> Bool
```

Register `setting` first and `setting.reverseVariant(id: "application-switching-reverse")` second. Pass `[setting]` as the reverse registration's existing list. Change the recovery copy to `Application switching needs Accessibility permission...` so it stays accurate for custom keys.

- [ ] **Step 4: Update existing controller tests and verify GREEN**

Pass `.defaultApplicationSwitching` into every existing `updateRegistration` call.

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: all tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add SwitchTab/Services/ApplicationSwitchingHotkeyController.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift
rtk git commit -m "feat: register custom application shortcuts"
```

### Task 4: App lifecycle and settings-window integration

**Files:**
- Modify: `SwitchTab/AppDelegate.swift`
- Modify: `SwitchTab/UI/Settings/SettingsWindowController.swift`
- Test: `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`

- [ ] **Step 1: Write failing source-contract tests for critical wiring**

Add a new XCTest that reads `AppDelegate.swift` and asserts all of these strings are present:

```swift
XCTAssertTrue(source.contains("shortcutStore.loadConfigurations()"))
XCTAssertTrue(source.contains("applicationHotkeyController.unregisterAll()"))
XCTAssertTrue(source.contains("registerConfiguredHotkeys"))
XCTAssertTrue(source.contains("applyShortcutChange"))
XCTAssertTrue(source.contains("applyEnabledChange"))
```

Also assert `ApplicationSettingsStore.replacesCommandTab` and `.commandTabReplacementDidChange` are absent from AppDelegate.

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk swift test --filter AppDelegateShortcutConfigurationTests`

Expected: assertions fail because AppDelegate still loads one window shortcut and one legacy Boolean.

- [ ] **Step 3: Load and register unified configurations at launch**

In `applicationDidFinishLaunching`, load once and call:

```swift
registerConfiguredHotkeys(shortcutStore.loadConfigurations())
```

Implement `registerConfiguredHotkeys` as a two-mode switch that calls window registration or `applicationHotkeyController.updateRegistration(setting:enabled:...)`. Disabled modes unregister only their own service and dismiss only an active overlay for that mode.

- [ ] **Step 4: Suspend and restore both modes during recording**

On `.shortcutRecordingDidBegin`, call both `hotkeyService.unregisterAll()` and `applicationHotkeyController.unregisterAll()`. On `.shortcutRecordingDidEnd`, reload the unified payload and call `registerConfiguredHotkeys`.

- [ ] **Step 5: Add transactional callbacks**

Implement:

```swift
private func applyShortcutChange(
    candidate: SwitcherShortcutConfiguration,
    previous: SwitcherShortcutConfiguration
) -> Bool

private func applyEnabledChange(_ configuration: SwitcherShortcutConfiguration)
```

The shortcut callback registers the candidate exactly; on failure it re-registers `previous`. The enabled callback registers or unregisters only its mode and persists registration messages.

Pass both callbacks through `SettingsWindowController` into `ShortcutSettingsViewModel`. Remove the obsolete shortcut-change notification observer after all settings changes use callbacks. Remove deprecated `ShortcutSettingsStore.load()` and `save(_:)` wrappers.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `rtk swift test --filter AppDelegateShortcutConfigurationTests`

Expected: pass.

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: all tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
rtk git add SwitchTab/AppDelegate.swift SwitchTab/UI/Settings/SettingsWindowController.swift SwitchTab/Services/ShortcutSettingsStore.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
rtk git commit -m "feat: apply unified shortcut lifecycle"
```

### Task 5: Dual-row settings UI

**Files:**
- Modify: `SwitchTab/UI/Settings/ShortcutSettingsView.swift`
- Test: `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`

- [ ] **Step 1: Write a failing UI source contract**

Read `ShortcutSettingsView.swift` and assert:

```swift
XCTAssertTrue(source.contains("Current App Windows"))
XCTAssertTrue(source.contains("Application Switching"))
XCTAssertTrue(source.contains("configuration.isEnabled ? \"Enabled\" : \"Disabled\""))
XCTAssertTrue(source.contains("viewModel.setEnabled"))
XCTAssertTrue(source.contains("viewModel.record"))
XCTAssertTrue(source.contains("viewModel.resetToDefault"))
XCTAssertFalse(source.contains("Replace macOS Cmd-Tab"))
```

- [ ] **Step 2: Run tests and verify RED**

Run: `rtk swift test --filter ShortcutSettingsUISourceTests`

Expected: assertions fail because the app mode is still a Toggle-only row.

- [ ] **Step 3: Generalize `ShortcutRecorderRow`**

Add inputs `configuration`, `isRecording`, `onEnabledChange`, and `onRecord`. Render controls in this order:

```swift
Text(configuration.isEnabled ? "Enabled" : "Disabled")
    .font(.caption.weight(.medium))
    .foregroundStyle(configuration.isEnabled ? Color.accentColor : .secondary)
    .frame(width: 54, alignment: .trailing)

Toggle("Enable \(configuration.shortcut.displayName)", isOn: enabledBinding)
    .labelsHidden()
    .toggleStyle(.switch)

Button(action: beginRecording) { shortcutKeycap }
Button(action: onReset) { Image(systemName: "arrow.counterclockwise") }
```

The keycap and reset button do not depend on `isEnabled`. Keep each row's minimum height fixed and reserve message space only when a message exists so toggling does not resize the panel.

- [ ] **Step 4: Render both configurations**

Replace the legacy app Toggle row with two calls using modes `.currentAppWindowSwitching` and `.applicationSwitching`. Update section copy to `Configure window and application switching shortcuts.`. Route mode into ViewModel record, reset, toggle, and message methods.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `rtk swift test --filter ShortcutSettingsUISourceTests`

Expected: pass.

Run: `rtk swift test --filter SwitchTabTests/testAllSuites`

Expected: all tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add SwitchTab/UI/Settings/ShortcutSettingsView.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
rtk git commit -m "feat: add configurable shortcut rows"
```

### Task 6: Verification, review, and release

**Files:**
- Modify only if verification finds defects directly caused by this feature.

- [ ] **Step 1: Run final automated verification**

Run:

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check origin/main...HEAD
```

Expected: 0 test failures, `** BUILD SUCCEEDED **`, no whitespace errors.

- [ ] **Step 2: Run release contract tests**

Run every executable test script under `scripts/tests/` using `rtk test bash <script>`.

Expected: every script exits 0.

- [ ] **Step 3: Perform real macOS QA**

Build and launch the isolated Debug app. Verify both rows show enabled defaults and stable height; record custom shortcuts while enabled and disabled; test reset; test duplicate rejection; verify each toggle restores native key handling; verify `Cmd + \`` window focus and `Cmd + Tab` application activation by Command release and mouse click; relaunch and verify persistence.

- [ ] **Step 4: Review and ship**

Run the project review workflow, fix only findings caused by this branch, then use the project ship workflow to prepare the next patch version, push, create and merge the PR, wait for CI, publish the signed/notarized GitHub release, validate the Sparkle feed and SHA-256, and confirm the Homebrew Cask PR merges.

- [ ] **Step 5: Report evidence**

Report PR, release, and Homebrew links plus exact test count, build result, real-QA outcomes, public DMG hash, and release status.
