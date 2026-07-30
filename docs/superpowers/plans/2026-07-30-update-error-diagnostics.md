# Update Error Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Sparkle's generic update failure alert with a categorized, privacy-safe alert that supports retry, manual download, diagnostic copying, and prefilled GitHub issue reporting.

**Architecture:** Keep all classification and report formatting in a Sparkle-independent Foundation model so the default build and unit tests remain Sparkle-free. In direct builds, subclass `SPUStandardUserDriver` only at `showUpdaterError`, retain every other standard Sparkle screen, and let an AppKit presenter render the approved actions.

**Tech Stack:** Swift 6, Foundation, AppKit, OSLog, Sparkle 2.9.4, XCTest, Xcode project files

---

## File Map

- Create `SwitchTab/Services/UpdateDiagnostic.swift`: error categories, recursive `NSError` classification, sanitized diagnostic payload, and support URLs.
- Create `SwitchTab/Services/SparkleUpdateErrorPresenter.swift`: native AppKit alert and clipboard/report/manual-download actions; direct-distribution guarded.
- Create `SwitchTab/Services/SwitchTabUpdateUserDriver.swift`: narrow `SPUStandardUserDriver` subclass that replaces only the error UI; direct-distribution guarded.
- Modify `SwitchTab/Services/SparkleUpdateController.swift`: construct and start a raw `SPUUpdater`, coordinate acknowledgement-safe retries.
- Create `SwitchTabTests/Services/UpdateDiagnosticTests.swift`: classifier, formatting, privacy, and URL tests.
- Modify `SwitchTabTests/TestRunner.swift`: run the new test suite.
- Modify `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`: protect the Sparkle-free default-build boundary and Xcode membership.
- Modify `SwitchTab.xcodeproj/project.pbxproj`: include the three production files and one test file in their targets.

### Task 1: Classify updater failures without importing Sparkle

**Files:**
- Create: `SwitchTab/Services/UpdateDiagnostic.swift`
- Create: `SwitchTabTests/Services/UpdateDiagnosticTests.swift`
- Modify: `SwitchTabTests/TestRunner.swift:31`

- [ ] **Step 1: Write the failing classifier tests**

Create the new test suite and register it immediately before `UpdateControllerTests.run()`:

```swift
import Foundation
import SwitchTab

enum UpdateDiagnosticTests {
    static func run() throws {
        try testClassifiesNetworkFailures()
        try testClassifiesSparkleFailures()
        try testUsesRecognizedUnderlyingError()
        try testFallsBackToUnknownError()
    }

    static func testClassifiesNetworkFailures() throws {
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            ).category,
            .connection
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            ).category,
            .timeout
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
            ).category,
            .tls
        )
    }

    static func testClassifiesSparkleFailures() throws {
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 1000)
            ).category,
            .feed
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 2001)
            ).category,
            .download
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 3001)
            ).category,
            .verification
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 4012)
            ).category,
            .installation
        )
    }

    static func testUsesRecognizedUnderlyingError() throws {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let wrapper = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1002,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let result = UpdateErrorClassifier.classify(wrapper)

        try expectEqual(result.category, .connection)
        try expectEqual(result.domain, NSURLErrorDomain)
        try expectEqual(result.code, NSURLErrorCannotConnectToHost)
    }

    static func testFallsBackToUnknownError() throws {
        let result = UpdateErrorClassifier.classify(
            NSError(domain: "ExampleDomain", code: 77)
        )

        try expectEqual(result.category, .unknown)
        try expectEqual(result.domain, "ExampleDomain")
        try expectEqual(result.code, 77)
    }
}
```

Add this line in `SwitchTabTests.testAllSuites()`:

```swift
try UpdateDiagnosticTests.run()
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `rtk swift test`

Expected: compilation fails because `UpdateErrorClassifier` and its result types do not exist.

- [ ] **Step 3: Implement the minimal classifier**

Create `UpdateDiagnostic.swift` with these public types and mappings:

```swift
import Foundation

public enum UpdateFailureCategory: String, Equatable, Sendable {
    case connection
    case timeout
    case tls
    case feed
    case download
    case verification
    case installation
    case unknown

    public var stage: String {
        switch self {
        case .connection, .timeout, .tls, .feed: "Feed download"
        case .download: "Update download"
        case .verification: "Update verification"
        case .installation: "Update installation"
        case .unknown: "Update check"
        }
    }

    public var title: String {
        switch self {
        case .connection, .timeout, .tls: "Unable to Connect to the Update Server"
        case .feed: "Unable to Read Update Information"
        case .download: "Unable to Download the Update"
        case .verification: "Unable to Verify the Update"
        case .installation: "Unable to Install the Update"
        case .unknown: "Unable to Check for Updates"
        }
    }

    public var explanation: String {
        switch self {
        case .connection:
            "Your network, VPN, or security proxy may be blocking the connection."
        case .timeout:
            "The update server took too long to respond. Check your connection and try again."
        case .tls:
            "A secure connection could not be established. A VPN or security proxy may be inspecting the connection."
        case .feed:
            "SwitchTab received update information it could not read."
        case .download:
            "The update file could not be downloaded."
        case .verification:
            "The downloaded update did not pass SwitchTab's security checks."
        case .installation:
            "The update could not be installed. Check that SwitchTab is in Applications and is writable."
        case .unknown:
            "An unexpected updater error occurred."
        }
    }
}

public struct UpdateErrorDescriptor: Equatable, Sendable {
    public let category: UpdateFailureCategory
    public let domain: String
    public let code: Int

    public init(category: UpdateFailureCategory, domain: String, code: Int) {
        self.category = category
        self.domain = domain
        self.code = code
    }

    public var technicalSummary: String {
        "\(category.stage) · \(domain) \(code)"
    }
}

public enum UpdateErrorClassifier {
    public static func classify(_ error: NSError) -> UpdateErrorDescriptor {
        var current: NSError? = error
        var fallback = descriptor(for: error)
        var recognizedFallback: UpdateErrorDescriptor?
        var visited = Set<ObjectIdentifier>()

        while let candidate = current,
              visited.insert(ObjectIdentifier(candidate)).inserted {
            let descriptor = descriptor(for: candidate)
            if descriptor.category != .unknown {
                if candidate.domain == NSURLErrorDomain {
                    return descriptor
                }
                if recognizedFallback == nil {
                    recognizedFallback = descriptor
                }
            }
            fallback = descriptor
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return recognizedFallback ?? fallback
    }

    private static func descriptor(for error: NSError) -> UpdateErrorDescriptor {
        let category: UpdateFailureCategory
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost:
                category = .connection
            case NSURLErrorTimedOut:
                category = .timeout
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                category = .tls
            default:
                category = .unknown
            }
        } else if error.domain == "SUSparkleErrorDomain" {
            switch error.code {
            case 3, 4, 1000, 1002, 1004:
                category = .feed
            case 2000, 2001:
                category = .download
            case 3000, 3001, 3002:
                category = .verification
            case 4000 ... 4012:
                category = .installation
            default:
                category = .unknown
            }
        } else {
            category = .unknown
        }

        return UpdateErrorDescriptor(category: category, domain: error.domain, code: error.code)
    }
}
```

- [ ] **Step 4: Run the tests and verify GREEN**

Run: `rtk swift test`

Expected: all 18 XCTest cases pass, including the expanded `testAllSuites` body.

- [ ] **Step 5: Commit the classifier**

```bash
rtk git add SwitchTab/Services/UpdateDiagnostic.swift SwitchTabTests/Services/UpdateDiagnosticTests.swift SwitchTabTests/TestRunner.swift
rtk git commit -m "feat: classify update failures"
```

### Task 2: Build sanitized diagnostics and support links

**Files:**
- Modify: `SwitchTab/Services/UpdateDiagnostic.swift`
- Modify: `SwitchTabTests/Services/UpdateDiagnosticTests.swift`

- [ ] **Step 1: Add failing formatting and privacy tests**

Append these calls to `UpdateDiagnosticTests.run()` and add their methods:

```swift
try testFormatsDeterministicDiagnostic()
try testDiagnosticExcludesRawPrivateErrorData()
try testBuildsSupportURLs()

static func testFormatsDeterministicDiagnostic() throws {
    let diagnostic = UpdateDiagnostic(
        descriptor: UpdateErrorDescriptor(
            category: .tls,
            domain: NSURLErrorDomain,
            code: NSURLErrorSecureConnectionFailed
        ),
        appVersion: "1.1.0 (11)",
        macOSVersion: "macOS 26.0",
        architecture: "arm64",
        timestamp: Date(timeIntervalSince1970: 1_785_422_400)
    )

    try expectTrue(diagnostic.report.contains("SwitchTab: 1.1.0 (11)"))
    try expectTrue(diagnostic.report.contains("Category: tls"))
    try expectTrue(diagnostic.report.contains("Error: NSURLErrorDomain -1200"))
    try expectFalse(diagnostic.report.contains("Optional"))
}

static func testDiagnosticExcludesRawPrivateErrorData() throws {
    let privateURL = "https://updates.example.test/private?employee=kendrick"
    let privatePath = "/Users/kendrick/Secret/update.dmg"
    let error = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorCannotConnectToHost,
        userInfo: [
            NSURLErrorFailingURLStringErrorKey: privateURL,
            NSFilePathErrorKey: privatePath,
            NSLocalizedDescriptionKey: "Failed for kendrick at \(privateURL)"
        ]
    )

    let diagnostic = UpdateDiagnostic.make(
        error: error,
        appVersion: "1.1.0 (11)",
        macOSVersion: "macOS 26.0",
        architecture: "arm64",
        timestamp: Date(timeIntervalSince1970: 1_785_422_400)
    )

    try expectFalse(diagnostic.report.contains("kendrick"))
    try expectFalse(diagnostic.report.contains(privateURL))
    try expectFalse(diagnostic.report.contains(privatePath))
}

static func testBuildsSupportURLs() throws {
    let diagnostic = UpdateDiagnostic(
        descriptor: UpdateErrorDescriptor(category: .connection, domain: NSURLErrorDomain, code: -1009),
        appVersion: "1.1.0 (11)",
        macOSVersion: "macOS 26.0",
        architecture: "arm64",
        timestamp: Date(timeIntervalSince1970: 1_785_422_400)
    )

    try expectEqual(UpdateSupportLinks.latestRelease.absoluteString, "https://github.com/sonim1/switchtab/releases/latest")
    let reportURL = try requireValue(UpdateSupportLinks.reportIssue(for: diagnostic))
    try expectEqual(reportURL.host, "github.com")
    try expectEqual(reportURL.path, "/sonim1/switchtab/issues/new")
    try expectTrue(reportURL.absoluteString.contains("body="))
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `rtk swift test`

Expected: compilation fails because `UpdateDiagnostic` and `UpdateSupportLinks` do not exist.

- [ ] **Step 3: Implement the payload and URLs**

Append the following API to `UpdateDiagnostic.swift`:

```swift
public struct UpdateDiagnostic: Equatable, Sendable {
    public let descriptor: UpdateErrorDescriptor
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: String
    public let timestamp: Date

    public init(
        descriptor: UpdateErrorDescriptor,
        appVersion: String,
        macOSVersion: String,
        architecture: String,
        timestamp: Date
    ) {
        self.descriptor = descriptor
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.timestamp = timestamp
    }

    public static func make(
        error: NSError,
        appVersion: String = ApplicationVersionProvider.currentVersionDisplay(),
        macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String? = nil,
        timestamp: Date = Date()
    ) -> UpdateDiagnostic {
        UpdateDiagnostic(
            descriptor: UpdateErrorClassifier.classify(error),
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            architecture: architecture ?? currentArchitecture,
            timestamp: timestamp
        )
    }

    public var report: String {
        let date = ISO8601DateFormatter().string(from: timestamp)
        return """
        SwitchTab Update Diagnostic
        SwitchTab: \(appVersion)
        macOS: \(macOSVersion)
        Architecture: \(architecture)
        Stage: \(descriptor.category.stage)
        Category: \(descriptor.category.rawValue)
        Error: \(descriptor.domain) \(descriptor.code)
        Time: \(date)
        """
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

public enum UpdateSupportLinks {
    public static let latestRelease = URL(
        string: "https://github.com/sonim1/switchtab/releases/latest"
    )!

    public static func reportIssue(for diagnostic: UpdateDiagnostic) -> URL? {
        var components = URLComponents(
            string: "https://github.com/sonim1/switchtab/issues/new"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "title",
                value: "Update failure: \(diagnostic.descriptor.category.rawValue)"
            ),
            URLQueryItem(
                name: "body",
                value: """
                ## What happened?

                Describe your network, VPN, and the steps that reproduced the error.

                ## Diagnostic information

                \(diagnostic.report)
                """
            )
        ]
        return components?.url
    }
}
```

- [ ] **Step 4: Run the tests and verify GREEN**

Run: `rtk swift test`

Expected: all XCTest cases pass and the report contains no private fixture values.

- [ ] **Step 5: Commit diagnostic formatting**

```bash
rtk git add SwitchTab/Services/UpdateDiagnostic.swift SwitchTabTests/Services/UpdateDiagnosticTests.swift
rtk git commit -m "feat: format safe update diagnostics"
```

### Task 3: Replace only Sparkle's generic error alert

**Files:**
- Create: `SwitchTab/Services/SparkleUpdateErrorPresenter.swift`
- Create: `SwitchTab/Services/SwitchTabUpdateUserDriver.swift`
- Modify: `SwitchTab/Services/SparkleUpdateController.swift`
- Modify: `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`

- [ ] **Step 1: Add a failing source-boundary contract test**

Add `testSparkleErrorUIIsDirectDistributionGuarded()` to the suite and call it from `run()`:

```swift
static func testSparkleErrorUIIsDirectDistributionGuarded() throws {
    for path in [
        "SwitchTab/Services/SparkleUpdateController.swift",
        "SwitchTab/Services/SparkleUpdateErrorPresenter.swift",
        "SwitchTab/Services/SwitchTabUpdateUserDriver.swift"
    ] {
        let contents = try String(
            contentsOf: projectRoot.appendingPathComponent(path),
            encoding: .utf8
        )
        try expectTrue(contents.contains("#if DIRECT_DISTRIBUTION && canImport(Sparkle)"))
    }

    let controller = try String(
        contentsOf: projectRoot.appendingPathComponent("SwitchTab/Services/SparkleUpdateController.swift"),
        encoding: .utf8
    )
    try expectTrue(controller.contains("SPUUpdater("))
    try expectTrue(controller.contains("SwitchTabUpdateUserDriver("))
    try expectTrue(controller.contains("didAbortWithError"))
    try expectTrue(controller.contains("UpdateDiagnostic.make"))
    try expectFalse(controller.contains("SPUStandardUpdaterController("))

    let driver = try String(
        contentsOf: projectRoot.appendingPathComponent("SwitchTab/Services/SwitchTabUpdateUserDriver.swift"),
        encoding: .utf8
    )
    let acknowledgement = try requireValue(driver.range(of: "acknowledgement()"))
    let actionCallback = try requireValue(driver.range(of: "didChooseAction?(action)"))
    try expectTrue(acknowledgement.lowerBound < actionCallback.lowerBound)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `rtk swift test`

Expected: failure because the two new guarded source files do not exist and the controller still uses `SPUStandardUpdaterController`.

- [ ] **Step 3: Implement the native alert presenter**

Create `SparkleUpdateErrorPresenter.swift`. Keep the whole file inside the direct-distribution guard. Implement:

```swift
#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit

@MainActor
public enum UpdateErrorAlertAction: Equatable {
    case retry
    case downloadManually
    case cancel
}

@MainActor
public final class SparkleUpdateErrorPresenter: NSObject {
    private var diagnostic: UpdateDiagnostic?

    public func present(error: NSError) -> UpdateErrorAlertAction {
        let diagnostic = UpdateDiagnostic.make(error: error)
        self.diagnostic = diagnostic

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = diagnostic.descriptor.category.title
        alert.informativeText = diagnostic.descriptor.category.explanation
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Download Manually")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = makeAccessoryView(for: diagnostic)

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .downloadManually
        default: return .cancel
        }
    }

    private func makeAccessoryView(for diagnostic: UpdateDiagnostic) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let summary = NSTextField(labelWithString: diagnostic.descriptor.technicalSummary)
        summary.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        summary.textColor = .secondaryLabelColor

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 14
        actions.addArrangedSubview(linkButton("Copy Diagnostics", action: #selector(copyDiagnostics)))
        actions.addArrangedSubview(linkButton("Report Issue ↗", action: #selector(reportIssue)))

        stack.addArrangedSubview(summary)
        stack.addArrangedSubview(actions)
        return stack
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        return button
    }

    @objc private func copyDiagnostics() {
        guard let diagnostic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic.report, forType: .string)
    }

    @objc private func reportIssue() {
        guard let diagnostic,
              let url = UpdateSupportLinks.reportIssue(for: diagnostic) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
```

- [ ] **Step 4: Implement the narrow Sparkle user driver**

Create `SwitchTabUpdateUserDriver.swift`:

```swift
#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit
import Sparkle

@MainActor
public final class SwitchTabUpdateUserDriver: SPUStandardUserDriver {
    public var didChooseAction: ((UpdateErrorAlertAction) -> Void)?
    private let errorPresenter: SparkleUpdateErrorPresenter

    public init(
        hostBundle: Bundle = .main,
        errorPresenter: SparkleUpdateErrorPresenter = SparkleUpdateErrorPresenter()
    ) {
        self.errorPresenter = errorPresenter
        super.init(hostBundle: hostBundle, delegate: nil)
    }

    public override func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        super.dismissUpdateInstallation()
        let action = errorPresenter.present(error: error as NSError)
        acknowledgement()
        didChooseAction?(action)
    }
}
#endif
```

- [ ] **Step 5: Replace the standard controller wrapper with `SPUUpdater`**

Change `SparkleUpdateController` to own the raw updater and keep the existing public API:

```swift
#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit
import Foundation
import OSLog
import Sparkle

@MainActor
public final class SparkleUpdateController: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private let logger = Logger(subsystem: "com.royjen.switchtab", category: "Updates")
    private let errorPresenter: SparkleUpdateErrorPresenter
    private let userDriver: SwitchTabUpdateUserDriver
    private var updater: SPUUpdater!

    public override init() {
        errorPresenter = SparkleUpdateErrorPresenter()
        userDriver = SwitchTabUpdateUserDriver(errorPresenter: errorPresenter)
        super.init()
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        userDriver.didChooseAction = { [weak self] action in
            self?.handleUpdateAction(action)
        }
        startUpdater()
    }

    public var isUpdateCheckingAvailable: Bool { updater.canCheckForUpdates }

    public var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {
        updater.checkForUpdates()
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let diagnostic = UpdateDiagnostic.make(error: error as NSError)
        logger.error("\(diagnostic.report, privacy: .public)")
    }

    private func startUpdater() {
        do {
            try updater.start()
        } catch {
            let action = errorPresenter.present(error: error as NSError)
            switch action {
            case .retry:
                DispatchQueue.main.async { [weak self] in self?.startUpdater() }
            case .downloadManually:
                NSWorkspace.shared.open(UpdateSupportLinks.latestRelease)
            case .cancel:
                break
            }
        }
    }

    private func handleUpdateAction(_ action: UpdateErrorAlertAction) {
        switch action {
        case .retry:
            DispatchQueue.main.async { [weak self] in self?.updater.checkForUpdates() }
        case .downloadManually:
            NSWorkspace.shared.open(UpdateSupportLinks.latestRelease)
        case .cancel:
            break
        }
    }
}
#endif
```

Use Sparkle 2.9.4's verified throwing `start()` API; do not bypass or discard a start error.

- [ ] **Step 6: Run the default-build tests and verify GREEN**

Run: `rtk swift test`

Expected: all XCTest cases pass; the guarded Sparkle sources are excluded from the SwiftPM/default build.

- [ ] **Step 7: Commit the error UI integration**

```bash
rtk git add SwitchTab/Services/SparkleUpdateErrorPresenter.swift SwitchTab/Services/SwitchTabUpdateUserDriver.swift SwitchTab/Services/SparkleUpdateController.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
rtk git commit -m "feat: show actionable update errors"
```

### Task 4: Add Xcode membership and verify both distribution paths

**Files:**
- Modify: `SwitchTab.xcodeproj/project.pbxproj`
- Modify: `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift`

- [ ] **Step 1: Add a failing project-membership assertion**

Extend `testSparkleErrorUIIsDirectDistributionGuarded()`:

```swift
let project = try String(
    contentsOf: projectRoot.appendingPathComponent("SwitchTab.xcodeproj/project.pbxproj"),
    encoding: .utf8
)
for file in [
    "UpdateDiagnostic.swift",
    "SparkleUpdateErrorPresenter.swift",
    "SwitchTabUpdateUserDriver.swift",
    "UpdateDiagnosticTests.swift"
] {
    try expectTrue(project.contains("/* \(file) in Sources */"))
}
```

- [ ] **Step 2: Run the contract and verify RED**

Run: `rtk swift test`

Expected: `testSparkleErrorUIIsDirectDistributionGuarded` fails because the new files are not in the Xcode targets.

- [ ] **Step 3: Add the four files to the project**

Use these unused IDs and mappings:

```text
A00000000000000000000108 / B00000000000000000000108  UpdateDiagnostic.swift
A00000000000000000000109 / B00000000000000000000109  SparkleUpdateErrorPresenter.swift
A00000000000000000000110 / B00000000000000000000110  SwitchTabUpdateUserDriver.swift
A00000000000000000000111 / B00000000000000000000111  UpdateDiagnosticTests.swift
```

Add these `PBXBuildFile` entries:

```text
A00000000000000000000108 /* UpdateDiagnostic.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000108 /* UpdateDiagnostic.swift */; };
A00000000000000000000109 /* SparkleUpdateErrorPresenter.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000109 /* SparkleUpdateErrorPresenter.swift */; };
A00000000000000000000110 /* SwitchTabUpdateUserDriver.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000110 /* SwitchTabUpdateUserDriver.swift */; };
A00000000000000000000111 /* UpdateDiagnosticTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000111 /* UpdateDiagnosticTests.swift */; };
```

Add matching `PBXFileReference` entries, place the three production references in `G00000000000000000000004 /* Services */`, place the test reference in `G00000000000000000000011 /* Services */`, and add the matching build-file IDs to the production and test Sources phases. Do not add Sparkle package references or `DIRECT_DISTRIBUTION` flags to the checked-in project.

The resulting entries must contain exactly these names:

```text
UpdateDiagnostic.swift in Sources
SparkleUpdateErrorPresenter.swift in Sources
SwitchTabUpdateUserDriver.swift in Sources
UpdateDiagnosticTests.swift in Sources
```

- [ ] **Step 4: Run default tests and unsigned Xcode build**

Run:

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: tests pass and the default Xcode build succeeds without resolving or linking Sparkle.

- [ ] **Step 5: Generate and compile the direct-distribution project**

Run:

```bash
SPARKLE_PUBLIC_ED_KEY=dummy rtk proxy scripts/build-direct-distribution.sh --prepare-only
rtk xcodebuild -project .build/direct-distribution/workspace/SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -derivedDataPath .build/direct-distribution/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: the generated project resolves pinned Sparkle 2.9.4 and compiles the custom user driver against its actual Swift interface.

- [ ] **Step 6: Commit project integration**

```bash
rtk git add SwitchTab.xcodeproj/project.pbxproj SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
rtk git commit -m "build: include update diagnostic sources"
```

### Task 5: Exercise the real failure and normal update paths

**Files:**
- Modify only if verification finds a defect in files already owned by Tasks 1-4.

- [ ] **Step 1: Build a signed diagnostic app with a deliberately failing feed**

Resolve the existing trusted Developer ID identity and use a local closed port:

```bash
SWITCHTAB_SIGNING_IDENTITY="$(rtk proxy security find-identity -v -p codesigning | rtk proxy awk -F\" '/Developer ID Application/ { print $2; exit }')"
SWITCHTAB_PUBLIC_KEY="$(rtk proxy plutil -extract SUPublicEDKey raw /Applications/SwitchTab.app/Contents/Info.plist)"
rtk proxy test -n "$SWITCHTAB_SIGNING_IDENTITY"
rtk proxy test -n "$SWITCHTAB_PUBLIC_KEY"
SPARKLE_PUBLIC_ED_KEY="$SWITCHTAB_PUBLIC_KEY" \
SWITCHTAB_UPDATE_FEED_URL="https://127.0.0.1:1/appcast.xml" \
DEVELOPER_ID_APPLICATION="$SWITCHTAB_SIGNING_IDENTITY" \
rtk proxy scripts/build-direct-distribution.sh
rtk proxy open -n .build/direct-distribution/DerivedData/Build/Products/Release/SwitchTab.app
```

Expected: the signed Release app builds and launches as a separate instance. Do not replace `/Applications/SwitchTab.app`.

- [ ] **Step 2: Verify the approved error UX manually**

Trigger Check for Updates and verify:

1. No generic Sparkle "retrieving update information" alert appears.
2. The alert identifies a connection/TLS category and shows domain/code.
3. Copy Diagnostics places only the allowlisted fields on the clipboard.
4. Report Issue opens a prefilled GitHub issue but does not submit it.
5. Download Manually opens the latest release page.
6. Try Again produces one new check after the prior cycle closes, not overlapping alerts.

- [ ] **Step 3: Restore and verify the production feed**

Rebuild with the production feed, launch a new instance of the generated app, and trigger Check for Updates:

```bash
SWITCHTAB_SIGNING_IDENTITY="$(rtk proxy security find-identity -v -p codesigning | rtk proxy awk -F\" '/Developer ID Application/ { print $2; exit }')"
SWITCHTAB_PUBLIC_KEY="$(rtk proxy plutil -extract SUPublicEDKey raw /Applications/SwitchTab.app/Contents/Info.plist)"
SPARKLE_PUBLIC_ED_KEY="$SWITCHTAB_PUBLIC_KEY" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.royjen.com/appcast.xml" \
DEVELOPER_ID_APPLICATION="$SWITCHTAB_SIGNING_IDENTITY" \
rtk proxy scripts/build-direct-distribution.sh
rtk proxy open -n .build/direct-distribution/DerivedData/Build/Products/Release/SwitchTab.app
```

Expected: Sparkle's existing update-found or up-to-date UI appears normally; the custom error alert does not appear.

- [ ] **Step 4: Run the complete repository gate**

Run:

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug CODE_SIGNING_ALLOWED=NO build
rtk test bash scripts/tests/release-tooling-test.sh
rtk test bash scripts/tests/release-local-test.sh
rtk test bash scripts/tests/generate-appcast-test.sh
rtk git diff --check
rtk git status --short
```

Expected: every command exits 0; status contains only the intended feature commits/files.

- [ ] **Step 5: Commit any verification-only correction**

If Steps 1-4 required a scoped correction, commit only that correction:

```bash
rtk git add SwitchTab/Services/UpdateDiagnostic.swift SwitchTab/Services/SparkleUpdateErrorPresenter.swift SwitchTab/Services/SwitchTabUpdateUserDriver.swift SwitchTab/Services/SparkleUpdateController.swift SwitchTabTests/Services/UpdateDiagnosticTests.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift SwitchTabTests/TestRunner.swift SwitchTab.xcodeproj/project.pbxproj
rtk git commit -m "fix: verify update error recovery"
```

If no correction was required, do not create an empty commit.
