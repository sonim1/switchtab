# Sparkle Direct Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle-backed update checking for direct website builds while keeping the default app build Sparkle-free.

**Architecture:** Add a small `UpdateChecking` boundary owned by `AppDelegate`. Menu bar and Settings send user-initiated update requests through that boundary. Sparkle is isolated behind `DIRECT_DISTRIBUTION && canImport(Sparkle)`, so the normal build and test runner use an unavailable fallback.

**Tech Stack:** Swift, SwiftUI, AppKit, NotificationCenter, Sparkle 2, current custom `WindowSwitcherTestRunner`.

---

## File Map

- Create `WindowSwitcher/Services/UpdateController.swift`: update protocol, unavailable fallback, version display helper, update request notification, factory.
- Create `WindowSwitcher/Services/SparkleUpdateController.swift`: Sparkle adapter compiled only for direct distribution builds.
- Modify `WindowSwitcher/AppDelegate.swift`: own the update controller and observe update-check requests.
- Modify `WindowSwitcher/UI/MenuBar/MenuBarContentView.swift`: show `Check for Updates...` when update checking is available.
- Modify `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`: expose update availability, current version, manual check action, and automatic-check preference.
- Modify `WindowSwitcher/UI/Settings/ShortcutSettingsView.swift`: add the Settings `Updates` section.
- Modify `WindowSwitcher/UI/Settings/SettingsWindowController.swift`: inject the shared update controller.
- Modify `Package.swift`: no Sparkle dependency for the default package target; new source files are picked up automatically.
- Modify `WindowSwitcher.xcodeproj/project.pbxproj`: add the two new service files to the app target. Do not link Sparkle to the default app target.
- Create `WindowSwitcherTests/Services/UpdateControllerTests.swift`: pure tests for fallback, notification posting, version display, and menu model.
- Modify `WindowSwitcherTests/Services/ApplicationSettingsStoreTests.swift`: add view model update-control tests.
- Modify `WindowSwitcherTests/TestRunner.swift`: run `UpdateControllerTests`.

The workspace currently has no `.git` directory. Commit steps in this plan are verification checkpoints; when this project is inside a git worktree, run the listed commit commands.

---

## Task 1: Update Boundary

**Files:**
- Create: `WindowSwitcher/Services/UpdateController.swift`
- Create: `WindowSwitcherTests/Services/UpdateControllerTests.swift`
- Modify: `WindowSwitcherTests/TestRunner.swift`
- Modify: `WindowSwitcher.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `WindowSwitcherTests/Services/UpdateControllerTests.swift`:

```swift
import Foundation
import WindowSwitcher

enum UpdateControllerTests {
    @MainActor
    static func run() throws {
        try testUnavailableControllerDisablesUpdateChecking()
        try testVersionDisplayUsesVersionAndBuild()
        try testVersionDisplayFallsBackWhenBuildIsMissing()
        try testUpdateRequestPosterPostsNotification()
        try testMenuModelIncludesUpdateItemOnlyWhenAvailable()
    }

    @MainActor
    static func testUnavailableControllerDisablesUpdateChecking() throws {
        let controller = UnavailableUpdateController()

        try expectFalse(controller.isUpdateCheckingAvailable)
        try expectFalse(controller.automaticallyChecksForUpdates)

        controller.automaticallyChecksForUpdates = true
        controller.checkForUpdates()

        try expectFalse(controller.automaticallyChecksForUpdates)
    }

    static func testVersionDisplayUsesVersionAndBuild() throws {
        let display = ApplicationVersionProvider.currentVersionDisplay(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45"
            ]
        )

        try expectEqual(display, "1.2.3 (45)")
    }

    static func testVersionDisplayFallsBackWhenBuildIsMissing() throws {
        let display = ApplicationVersionProvider.currentVersionDisplay(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3"
            ]
        )

        try expectEqual(display, "1.2.3")
    }

    static func testUpdateRequestPosterPostsNotification() throws {
        let notificationCenter = NotificationCenter()
        let recorder = UpdateNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        UpdateRequestPoster.postCheckForUpdatesRequest(notificationCenter: notificationCenter)

        try expectTrue(recorder.didPostNotification)
    }

    static func testMenuModelIncludesUpdateItemOnlyWhenAvailable() throws {
        try expectEqual(
            MenuBarMenuModel.items(updateCheckingAvailable: false),
            [.settings, .separator, .about, .quit]
        )
        try expectEqual(
            MenuBarMenuModel.items(updateCheckingAvailable: true),
            [.settings, .checkForUpdates, .separator, .about, .quit]
        )
    }
}

private final class UpdateNotificationRecorder: @unchecked Sendable {
    private(set) var didPostNotification = false

    func record() {
        didPostNotification = true
    }
}
```

Add this call to `WindowSwitcherTests/TestRunner.swift` after `ApplicationSettingsStoreTests.run()`:

```swift
try UpdateControllerTests.run()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: FAIL at compile time with missing symbols such as `UnavailableUpdateController`, `ApplicationVersionProvider`, `UpdateRequestPoster`, or `MenuBarMenuModel`.

- [ ] **Step 3: Add the minimal update boundary**

Create `WindowSwitcher/Services/UpdateController.swift`:

```swift
import Foundation

public extension Notification.Name {
    static let checkForUpdates = Notification.Name("WindowSwitcher.checkForUpdates")
}

@MainActor
public protocol UpdateChecking: AnyObject {
    var isUpdateCheckingAvailable: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var currentVersionDisplay: String { get }
    func checkForUpdates()
}

@MainActor
public final class UnavailableUpdateController: UpdateChecking {
    public init() {}

    public var isUpdateCheckingAvailable: Bool {
        false
    }

    public var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {}
}

public enum ApplicationVersionProvider {
    public static func currentVersionDisplay(bundle: Bundle = .main) -> String {
        currentVersionDisplay(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func currentVersionDisplay(infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String
        let displayedVersion = version?.isEmpty == false ? version! : "Unknown"

        guard let build,
              !build.isEmpty else {
            return displayedVersion
        }

        return "\(displayedVersion) (\(build))"
    }
}

@MainActor
public enum UpdateControllerFactory {
    public static func make() -> any UpdateChecking {
        #if DIRECT_DISTRIBUTION && canImport(Sparkle)
        return SparkleUpdateController()
        #else
        return UnavailableUpdateController()
        #endif
    }
}

public enum UpdateRequestPoster {
    public static func postCheckForUpdatesRequest(
        notificationCenter: NotificationCenter = .default
    ) {
        notificationCenter.post(name: .checkForUpdates, object: nil)
    }
}
```

Add `UpdateController.swift` to `WindowSwitcher.xcodeproj/project.pbxproj`:

```text
PBXBuildFile: UpdateController.swift in Sources
PBXFileReference: UpdateController.swift
PBXGroup Services: UpdateController.swift
PBXSourcesBuildPhase WindowSwitcher: UpdateController.swift in Sources
```

- [ ] **Step 4: Run the tests to verify the next expected failure**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: FAIL because `MenuBarMenuModel` and `MenuBarMenuItemKind` are not defined yet.

- [ ] **Step 5: Add the pure menu model**

Modify `WindowSwitcher/UI/MenuBar/MenuBarContentView.swift` near the top:

```swift
public enum MenuBarMenuItemKind: Equatable {
    case settings
    case checkForUpdates
    case separator
    case about
    case quit
}

public enum MenuBarMenuModel {
    public static func items(updateCheckingAvailable: Bool) -> [MenuBarMenuItemKind] {
        if updateCheckingAvailable {
            return [.settings, .checkForUpdates, .separator, .about, .quit]
        }

        return [.settings, .separator, .about, .quit]
    }
}
```

- [ ] **Step 6: Run the tests to verify Task 1 passes**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: PASS and output includes `All tests passed`.

- [ ] **Step 7: Commit checkpoint**

If `.git` exists:

```bash
rtk git add WindowSwitcher/Services/UpdateController.swift WindowSwitcher/UI/MenuBar/MenuBarContentView.swift WindowSwitcherTests/Services/UpdateControllerTests.swift WindowSwitcherTests/TestRunner.swift WindowSwitcher.xcodeproj/project.pbxproj
rtk git commit -m "feat: add update checking boundary"
```

Expected in the current workspace: skip commit because `rtk git status --short` reports this is not a git repository.

---

## Task 2: Menu Bar and AppDelegate Wiring

**Files:**
- Modify: `WindowSwitcher/AppDelegate.swift`
- Modify: `WindowSwitcher/UI/MenuBar/MenuBarContentView.swift`
- Modify: `WindowSwitcherTests/Services/UpdateControllerTests.swift`

- [ ] **Step 1: Write the failing notification wiring test**

Append to `UpdateControllerTests.run()`:

```swift
try testMenuUpdateActionPostsUpdateRequest()
```

Add this test:

```swift
static func testMenuUpdateActionPostsUpdateRequest() throws {
    let notificationCenter = NotificationCenter()
    let recorder = UpdateNotificationRecorder()
    let observer = notificationCenter.addObserver(
        forName: .checkForUpdates,
        object: nil,
        queue: nil
    ) { _ in
        recorder.record()
    }
    defer {
        notificationCenter.removeObserver(observer)
    }

    MenuBarUpdateAction.postCheckForUpdatesRequest(notificationCenter: notificationCenter)

    try expectTrue(recorder.didPostNotification)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: FAIL because `MenuBarUpdateAction` does not exist.

- [ ] **Step 3: Add menu bar update action and menu item**

Modify `WindowSwitcher/UI/MenuBar/MenuBarContentView.swift`:

```swift
public enum MenuBarUpdateAction {
    public static func postCheckForUpdatesRequest(
        notificationCenter: NotificationCenter = .default
    ) {
        UpdateRequestPoster.postCheckForUpdatesRequest(notificationCenter: notificationCenter)
    }
}
```

Add an update checker property and initializer parameter:

```swift
private let updateChecker: any UpdateChecking

public init(
    store: ApplicationSettingsStore = ApplicationSettingsStore(),
    updateChecker: any UpdateChecking = UnavailableUpdateController()
) {
    self.store = store
    self.updateChecker = updateChecker
    super.init()
    refreshVisibility()
    settingsObserver = NotificationCenter.default.addObserver(
        forName: .applicationSettingsDidChange,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated {
            self?.refreshVisibility()
        }
    }
}
```

Replace `makeMenu()` with:

```swift
private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    for item in MenuBarMenuModel.items(updateCheckingAvailable: updateChecker.isUpdateCheckingAvailable) {
        switch item {
        case .settings:
            menu.addItem(menuItem(title: "Settings", action: #selector(showSettings)))
        case .checkForUpdates:
            menu.addItem(menuItem(title: "Check for Updates...", action: #selector(checkForUpdates)))
        case .separator:
            menu.addItem(.separator())
        case .about:
            menu.addItem(menuItem(title: "About SwitchTab", action: #selector(showAbout)))
        case .quit:
            menu.addItem(menuItem(title: "Quit", action: #selector(quit)))
        }
    }
    return menu
}
```

Add the action:

```swift
@objc private func checkForUpdates() {
    MenuBarUpdateAction.postCheckForUpdatesRequest()
}
```

- [ ] **Step 4: Wire AppDelegate to observe update requests**

Modify `WindowSwitcher/AppDelegate.swift`:

```swift
private let updateChecker: any UpdateChecking = UpdateControllerFactory.make()
private var updateCheckRequestObserver: NSObjectProtocol?
```

Pass the update checker to the menu bar controller:

```swift
menuBarStatusItemController = MenuBarStatusItemController(
    store: applicationSettingsStore,
    updateChecker: updateChecker
)
```

Call the observer from launch:

```swift
observeUpdateCheckRequests()
```

Remove the observer on termination:

```swift
removeObserver(&updateCheckRequestObserver)
```

Add the observer method:

```swift
private func observeUpdateCheckRequests() {
    observe(.checkForUpdates, storing: &updateCheckRequestObserver) { [weak self] in
        self?.updateChecker.checkForUpdates()
    }
}
```

- [ ] **Step 5: Run tests and app build**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build
```

Expected: tests pass and Xcode build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit checkpoint**

If `.git` exists:

```bash
rtk git add WindowSwitcher/AppDelegate.swift WindowSwitcher/UI/MenuBar/MenuBarContentView.swift WindowSwitcherTests/Services/UpdateControllerTests.swift
rtk git commit -m "feat: wire update checks from menu bar"
```

Expected in the current workspace: skip commit because `rtk git status --short` reports this is not a git repository.

---

## Task 3: Settings Update Controls

**Files:**
- Modify: `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`
- Modify: `WindowSwitcher/UI/Settings/ShortcutSettingsView.swift`
- Modify: `WindowSwitcher/UI/Settings/SettingsWindowController.swift`
- Modify: `WindowSwitcher/AppDelegate.swift`
- Modify: `WindowSwitcherTests/Services/ApplicationSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing view model tests**

Add these calls to `ApplicationSettingsStoreTests.run()` after `testViewModelUpdatesOverlaySize()`:

```swift
try testViewModelHidesUpdateControlsWhenUnavailable()
try testViewModelForwardsManualUpdateChecks()
try testViewModelUpdatesAutomaticCheckPreference()
```

Add these tests:

```swift
@MainActor
static func testViewModelHidesUpdateControlsWhenUnavailable() throws {
    let viewModel = ApplicationSettingsViewModel(
        store: ApplicationSettingsStore(userDefaults: makeDefaults()),
        launchAtLoginService: FakeLaunchAtLoginService(),
        updateChecker: UnavailableUpdateController()
    )

    try expectFalse(viewModel.updateCheckingAvailable)
    try expectEqual(viewModel.currentVersionDisplay.isEmpty, false)
}

@MainActor
static func testViewModelForwardsManualUpdateChecks() throws {
    let updateChecker = FakeUpdateChecker(isAvailable: true)
    let viewModel = ApplicationSettingsViewModel(
        store: ApplicationSettingsStore(userDefaults: makeDefaults()),
        launchAtLoginService: FakeLaunchAtLoginService(),
        updateChecker: updateChecker
    )

    viewModel.checkForUpdates()

    try expectEqual(updateChecker.checkCount, 1)
}

@MainActor
static func testViewModelUpdatesAutomaticCheckPreference() throws {
    let updateChecker = FakeUpdateChecker(isAvailable: true)
    let viewModel = ApplicationSettingsViewModel(
        store: ApplicationSettingsStore(userDefaults: makeDefaults()),
        launchAtLoginService: FakeLaunchAtLoginService(),
        updateChecker: updateChecker
    )

    viewModel.setAutomaticallyChecksForUpdates(true)

    try expectTrue(viewModel.automaticallyChecksForUpdates)
    try expectTrue(updateChecker.automaticallyChecksForUpdates)
}
```

Add this fake at the bottom of `ApplicationSettingsStoreTests.swift`:

```swift
@MainActor
private final class FakeUpdateChecker: UpdateChecking {
    private let isAvailable: Bool
    private(set) var checkCount = 0
    var automaticallyChecksForUpdates = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isUpdateCheckingAvailable: Bool {
        isAvailable
    }

    var currentVersionDisplay: String {
        "1.0 (1)"
    }

    func checkForUpdates() {
        checkCount += 1
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: FAIL because `ApplicationSettingsViewModel` has no update checker initializer argument or update properties.

- [ ] **Step 3: Extend the application settings view model**

Modify `WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift`:

```swift
@Published public private(set) var updateCheckingAvailable: Bool
@Published public private(set) var currentVersionDisplay: String
@Published public private(set) var automaticallyChecksForUpdates: Bool

private let updateChecker: any UpdateChecking
```

Update the initializer signature:

```swift
public init(
    store: ApplicationSettingsStore = ApplicationSettingsStore(),
    launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
    updateChecker: (any UpdateChecking)? = nil
) {
    let resolvedLaunchAtLoginService = launchAtLoginService ?? LaunchAtLoginService()
    let resolvedUpdateChecker = updateChecker ?? UnavailableUpdateController()

    self.store = store
    self.launchAtLoginService = resolvedLaunchAtLoginService
    self.updateChecker = resolvedUpdateChecker
    self.startsAtLogin = resolvedLaunchAtLoginService.startsAtLogin
    self.menuBarIconVisible = store.menuBarIconVisible
    self.overlaySize = store.overlaySize
    self.updateCheckingAvailable = resolvedUpdateChecker.isUpdateCheckingAvailable
    self.currentVersionDisplay = resolvedUpdateChecker.currentVersionDisplay
    self.automaticallyChecksForUpdates = resolvedUpdateChecker.automaticallyChecksForUpdates
}
```

Add methods:

```swift
public func checkForUpdates() {
    guard updateCheckingAvailable else {
        return
    }

    updateChecker.checkForUpdates()
}

public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    guard updateCheckingAvailable else {
        automaticallyChecksForUpdates = false
        return
    }

    updateChecker.automaticallyChecksForUpdates = enabled
    automaticallyChecksForUpdates = updateChecker.automaticallyChecksForUpdates
}
```

- [ ] **Step 4: Add Settings UI**

Modify `WindowSwitcher/UI/Settings/ShortcutSettingsView.swift` under the overlay size picker and before the first divider:

```swift
if applicationSettingsViewModel.updateCheckingAvailable {
    Divider()

    Text("Updates")
        .font(.title3.weight(.semibold))

    HStack {
        Text("Version")
        Spacer()
        Text(applicationSettingsViewModel.currentVersionDisplay)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    Button {
        applicationSettingsViewModel.checkForUpdates()
    } label: {
        Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
            .labelStyle(.titleAndIcon)
    }

    Toggle(
        "Automatically check for updates",
        isOn: Binding(
            get: { applicationSettingsViewModel.automaticallyChecksForUpdates },
            set: { applicationSettingsViewModel.setAutomaticallyChecksForUpdates($0) }
        )
    )
}
```

- [ ] **Step 5: Inject the shared update controller into Settings**

Modify `WindowSwitcher/UI/Settings/SettingsWindowController.swift`:

```swift
public init(
    activationCoordinator: SettingsActivationPolicyCoordinator,
    updateChecker: any UpdateChecking = UnavailableUpdateController()
) {
    let hostingController = FloatingPanelFactory.hostingController(
        rootView: ShortcutSettingsView(
            applicationSettingsViewModel: ApplicationSettingsViewModel(updateChecker: updateChecker)
        ),
        contentSize: SettingsWindowSizingPolicy.contentSize
    )
    ...
}
```

Modify `WindowSwitcher/AppDelegate.swift` in `showSettingsWindow()`:

```swift
settingsWindowController = SettingsWindowController(
    activationCoordinator: SettingsActivationPolicyCoordinator(
        policyApplier: NSApplicationActivationPolicyApplier()
    ),
    updateChecker: updateChecker
)
```

- [ ] **Step 6: Run tests and app build**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build
```

Expected: tests pass and Xcode build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit checkpoint**

If `.git` exists:

```bash
rtk git add WindowSwitcher/UI/Settings/ApplicationSettingsViewModel.swift WindowSwitcher/UI/Settings/ShortcutSettingsView.swift WindowSwitcher/UI/Settings/SettingsWindowController.swift WindowSwitcher/AppDelegate.swift WindowSwitcherTests/Services/ApplicationSettingsStoreTests.swift
rtk git commit -m "feat: add settings update controls"
```

Expected in the current workspace: skip commit because `rtk git status --short` reports this is not a git repository.

---

## Task 4: Sparkle Adapter Source

**Files:**
- Create: `WindowSwitcher/Services/SparkleUpdateController.swift`
- Modify: `WindowSwitcher.xcodeproj/project.pbxproj`
- Modify: `WindowSwitcherTests/Services/AppStoreDistributionSettingsTests.swift`

- [ ] **Step 1: Write the source hygiene test**

Add this call to `AppStoreDistributionSettingsTests.run()`:

```swift
try testSparkleAdapterIsDirectDistributionGuarded()
```

Add this test:

```swift
static func testSparkleAdapterIsDirectDistributionGuarded() throws {
    let adapterURL = projectRoot.appendingPathComponent("WindowSwitcher/Services/SparkleUpdateController.swift")
    let contents = try String(contentsOf: adapterURL, encoding: .utf8)

    try expectTrue(contents.contains("#if DIRECT_DISTRIBUTION && canImport(Sparkle)"))
    try expectTrue(contents.contains("import Sparkle"))

    let projectURL = projectRoot.appendingPathComponent("WindowSwitcher.xcodeproj/project.pbxproj")
    let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

    try expectFalse(projectContents.contains("DIRECT_DISTRIBUTION;"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: FAIL because `SparkleUpdateController.swift` does not exist.

- [ ] **Step 3: Add the guarded Sparkle adapter**

Create `WindowSwitcher/Services/SparkleUpdateController.swift`:

```swift
#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import Foundation
import Sparkle

@MainActor
public final class SparkleUpdateController: NSObject, UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    public override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    public var isUpdateCheckingAvailable: Bool {
        updaterController.updater.canCheckForUpdates
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
```

Add `SparkleUpdateController.swift` to `WindowSwitcher.xcodeproj/project.pbxproj`:

```text
PBXBuildFile: SparkleUpdateController.swift in Sources
PBXFileReference: SparkleUpdateController.swift
PBXGroup Services: SparkleUpdateController.swift
PBXSourcesBuildPhase WindowSwitcher: SparkleUpdateController.swift in Sources
```

Do not add Sparkle package references to `WindowSwitcher.xcodeproj/project.pbxproj` in this task. Without the `DIRECT_DISTRIBUTION` compilation condition and Sparkle package product, this source compiles to an empty file.

- [ ] **Step 4: Run default-build tests**

Run:

```bash
rtk test swift run WindowSwitcherTestRunner
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build
```

Expected: tests pass and Xcode build ends with `** BUILD SUCCEEDED **`. Settings and menu bar do not show update controls in this default build.

- [ ] **Step 5: Commit checkpoint**

If `.git` exists:

```bash
rtk git add WindowSwitcher/Services/SparkleUpdateController.swift WindowSwitcher.xcodeproj/project.pbxproj WindowSwitcherTests/Services/AppStoreDistributionSettingsTests.swift
rtk git commit -m "feat: add guarded sparkle update adapter"
```

Expected in the current workspace: skip commit because `rtk git status --short` reports this is not a git repository.

---

## Task 5: Direct Distribution Build Notes

**Files:**
- Modify: `docs/superpowers/specs/2026-07-02-sparkle-direct-update-design.md`
- Create: `docs/superpowers/plans/2026-07-02-direct-release-automation-followup.md`

- [ ] **Step 1: Document the exact direct build contract**

Append this section to `docs/superpowers/specs/2026-07-02-sparkle-direct-update-design.md`:

```markdown
## Direct Build Contract

The default `WindowSwitcher` app target remains Sparkle-free. A direct
distribution build must supply three things together:

1. The `DIRECT_DISTRIBUTION` Swift compilation condition.
2. The Sparkle 2 package product linked into the direct app target.
3. `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` in the direct
   distribution Info.plist.

Do not link Sparkle into the default app target used for App Store-oriented
builds. Use a separate direct distribution target or release automation that
produces a direct-only app bundle.
```

- [ ] **Step 2: Add a follow-up release automation plan stub with concrete scope**

Create `docs/superpowers/plans/2026-07-02-direct-release-automation-followup.md`:

```markdown
# Direct Release Automation Follow-Up

Scope for the release automation pass:

- Create a dedicated direct distribution app target or generated Xcode project
  variant that links Sparkle 2.
- Add a direct distribution Info.plist with `SUFeedURL`,
  `SUPublicEDKey`, and `SUEnableAutomaticChecks`.
- Generate and store the Sparkle private key outside the repository.
- Archive, Developer ID sign, notarize, zip, sign the update archive, generate
  `appcast.xml`, and upload release assets to Cloudflare R2.
- Verify that the default app target has no Sparkle package product dependency.
```

- [ ] **Step 3: Run documentation and source checks**

Run:

```bash
rtk grep "DIRECT_DISTRIBUTION" WindowSwitcher docs/superpowers
rtk grep "Sparkle" WindowSwitcher.xcodeproj/project.pbxproj
rtk test swift run WindowSwitcherTestRunner
```

Expected:

- First command finds the guarded adapter and direct build contract.
- Second command finds only `SparkleUpdateController.swift` source references, not `XCRemoteSwiftPackageReference` or `XCSwiftPackageProductDependency`.
- Tests pass with `All tests passed`.

- [ ] **Step 4: Commit checkpoint**

If `.git` exists:

```bash
rtk git add docs/superpowers/specs/2026-07-02-sparkle-direct-update-design.md docs/superpowers/plans/2026-07-02-direct-release-automation-followup.md
rtk git commit -m "docs: capture direct update release contract"
```

Expected in the current workspace: skip commit because `rtk git status --short` reports this is not a git repository.

---

## Final Verification

- [ ] Run the fast test runner:

```bash
rtk test swift run WindowSwitcherTestRunner
```

Expected: `All tests passed`.

- [ ] Run the Xcode app build:

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WindowSwitcher.xcodeproj -scheme WindowSwitcher -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] Confirm default build stays Sparkle-free:

```bash
rtk grep "XCRemoteSwiftPackageReference|XCSwiftPackageProductDependency|DIRECT_DISTRIBUTION;" WindowSwitcher.xcodeproj/project.pbxproj
```

Expected: no matches for package references or default direct-distribution flags.

---

## Self-Review

Spec coverage:

- Manual menu bar update check: Task 2.
- Settings update controls: Task 3.
- Automatic check preference: Task 3.
- Sparkle adapter: Task 4.
- App Store/default build isolation: Task 4 and Task 5.
- Cloudflare/appcast release path: Task 5 as a scoped release automation follow-up.

Unresolved-marker scan:

- No unresolved marker entries.
- No vague "add error handling" steps.
- Each code-changing step includes concrete code or an exact project-file insertion target.

Type consistency:

- `UpdateChecking` is the single protocol used by `UnavailableUpdateController`, `SparkleUpdateController`, `ApplicationSettingsViewModel`, `SettingsWindowController`, `MenuBarStatusItemController`, and `AppDelegate`.
- `UpdateRequestPoster` owns the notification name posting, and `MenuBarUpdateAction` delegates to it.
- The direct adapter is only referenced inside the same conditional compilation expression that defines it.
