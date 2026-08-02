import Foundation
import XCTest
@testable import SwitchTab

final class AppSettingsCommandRoutingTests: XCTestCase {
    func testCommandCommaRoutesToCustomSettingsWindow() throws {
        try AppStoreDistributionSettingsTests.testAppSettingsCommandRoutesToCustomSettingsWindow()
    }
}

enum AppStoreDistributionSettingsTests {
    static func run() throws {
        try testInfoPlistUsesAppStoreBundleIdentifier()
        try testInfoPlistDeclaresAppBundleMetadata()
        try testBuildAndDistributionPathsUseSwitchTab()
        try testXcodeProjectUsesAppStoreBundleIdentifier()
        try testAppSandboxIsDisabledForGlobalWindowSwitching()
        try testSparkleAdapterIsDirectDistributionGuarded()
        try testSparkleErrorUIIsDirectDistributionGuarded()
        try testEnabledApplicationConflictUsesConfiguredForwardAndShiftReverse()
        try testDisabledApplicationContributesNoWindowConflicts()
        try testWindowRegistrationConflictListsComeFromPolicyBoundary()
        try testApplicationCandidateIsAWindowRegistrationConflict()
        try testApplicationShortcutTransactionSucceedsInOrder()
        try testApplicationShortcutTransactionRestoresAfterCandidateFailure()
        try testApplicationShortcutTransactionRestoresAfterWindowFailure()
        try testAppDelegateReferencesShortcutConflictPolicy()
        try testAppDelegateUsesUnifiedShortcutLifecycle()
        try testSettingsWindowInjectsUnifiedShortcutCallbacks()
        try testDirectDistributionScriptGeneratesIsolatedProjectVariant()
        try testDirectDistributionScriptPinsSparkleToExactRevision()
        try testDirectDistributionScriptRequiresSparklePublicKey()
        try testDirectDistributionScriptRequiresHTTPSUpdateFeedURL()
        try testDirectDistributionScriptAutomatesReleaseArtifacts()
        try testDocumentationCoversDirectDistributionBuild()
    }

    static func testInfoPlistUsesAppStoreBundleIdentifier() throws {
        let infoPlistURL = projectRoot.appendingPathComponent("SwitchTab/Resources/Info.plist")
        let contents = try String(contentsOf: infoPlistURL, encoding: .utf8)

        try expectTrue(contents.contains("<string>com.royjen.switchtab</string>"))
        try expectFalse(contents.contains("com.local.SwitchTab"))
    }

    static func testInfoPlistDeclaresAppBundleMetadata() throws {
        let infoPlistURL = projectRoot.appendingPathComponent("SwitchTab/Resources/Info.plist")
        let contents = try String(contentsOf: infoPlistURL, encoding: .utf8)

        try expectTrue(contents.contains("<key>CFBundleExecutable</key>"))
        try expectTrue(contents.contains("<string>$(EXECUTABLE_NAME)</string>"))
        try expectTrue(contents.contains("<key>CFBundlePackageType</key>"))
        try expectTrue(contents.contains("<string>APPL</string>"))
        try expectTrue(contents.contains("<key>CFBundleShortVersionString</key>"))
        try expectTrue(contents.contains("<string>$(MARKETING_VERSION)</string>"))
        try expectTrue(contents.contains("<key>CFBundleVersion</key>"))
        try expectTrue(contents.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
    }

    static func testBuildAndDistributionPathsUseSwitchTab() throws {
        let packageURL = projectRoot.appendingPathComponent("Package.swift")
        let packageContents = try String(contentsOf: packageURL, encoding: .utf8)
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let scriptContents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(packageContents.contains(".testTarget("))
        try expectTrue(packageContents.contains("name: \"SwitchTabTests\""))
        try expectTrue(packageContents.contains("path: \"SwitchTab\""))
        try expectTrue(packageContents.contains("path: \"SwitchTabTests\""))
        try expectTrue(scriptContents.contains("SwitchTab.xcodeproj/project.pbxproj"))
        try expectFalse(scriptContents.contains("WindowSwitcher.xcodeproj/project.pbxproj"))
        try expectFalse(packageContents.contains("WindowSwitcher"))
    }

    static func testAppSettingsCommandRoutesToCustomSettingsWindow() throws {
        let appURL = projectRoot.appendingPathComponent("SwitchTab/SwitchTabApp.swift")
        let contents = try String(contentsOf: appURL, encoding: .utf8)

        try expectTrue(contents.contains("CommandGroup(replacing: .appSettings)"))
        try expectTrue(contents.contains("NotificationCenter.default.post(name: .showSettingsWindow"))
        try expectTrue(contents.contains(".keyboardShortcut(\",\", modifiers: .command)"))
    }

    static func testXcodeProjectUsesAppStoreBundleIdentifier() throws {
        let projectURL = projectRoot.appendingPathComponent("SwitchTab.xcodeproj/project.pbxproj")
        let contents = try String(contentsOf: projectURL, encoding: .utf8)

        try expectTrue(contents.contains("PRODUCT_BUNDLE_IDENTIFIER = com.royjen.switchtab;"))
        try expectFalse(contents.contains("PRODUCT_BUNDLE_IDENTIFIER = com.local.SwitchTab;"))
    }

    static func testAppSandboxIsDisabledForGlobalWindowSwitching() throws {
        let entitlementsURL = projectRoot.appendingPathComponent("SwitchTab/Resources/SwitchTab.entitlements")
        let contents = try String(contentsOf: entitlementsURL, encoding: .utf8)

        try expectFalse(contents.contains("<key>com.apple.security.app-sandbox</key>"))
        try expectFalse(contents.contains("<false/>"))
    }

    static func testSparkleAdapterIsDirectDistributionGuarded() throws {
        let adapterURL = projectRoot.appendingPathComponent("SwitchTab/Services/SparkleUpdateController.swift")
        let contents = try String(contentsOf: adapterURL, encoding: .utf8)

        try expectTrue(contents.contains("#if DIRECT_DISTRIBUTION && canImport(Sparkle)"))
        try expectTrue(contents.contains("import Sparkle"))

        let projectURL = projectRoot.appendingPathComponent("SwitchTab.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

        try expectFalse(projectContents.contains("DIRECT_DISTRIBUTION;"))
    }

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
        try expectTrue(controller.contains("sessionInProgress"))
        try expectFalse(controller.contains("SPUStandardUpdaterController("))

        let driver = try String(
            contentsOf: projectRoot.appendingPathComponent("SwitchTab/Services/SwitchTabUpdateUserDriver.swift"),
            encoding: .utf8
        )
        guard let acknowledgement = driver.range(of: "acknowledgement()"),
              let actionCallback = driver.range(of: "didChooseAction?(action)") else {
            throw TestFailure.failed("Expected acknowledgement before the update action callback")
        }
        try expectTrue(acknowledgement.lowerBound < actionCallback.lowerBound)

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
    }

    static func testEnabledApplicationConflictUsesConfiguredForwardAndShiftReverse() throws {
        let applicationShortcutConflicts = AppDelegateShortcutConflictPolicy
            .enabledApplicationShortcuts(in: conflictConfigurations(applicationEnabled: true))

        try expectEqual(applicationShortcutConflicts.count, 2)
        try expectEqual(applicationShortcutConflicts[0], customApplicationShortcut)
        try expectEqual(applicationShortcutConflicts[1].id, "application-switching-reverse")
        try expectEqual(applicationShortcutConflicts[1].mode, .applicationSwitching)
        try expectEqual(applicationShortcutConflicts[1].keyEquivalent, "Space")
        try expectEqual(applicationShortcutConflicts[1].keyCode, 49)
        try expectEqual(
            applicationShortcutConflicts[1].modifiers,
            ["option", "control", "shift"]
        )
        try expectTrue(applicationShortcutConflicts[1].isUsable)
    }

    static func testDisabledApplicationContributesNoWindowConflicts() throws {
        let configurations = conflictConfigurations(applicationEnabled: false)

        try expectEqual(
            AppDelegateShortcutConflictPolicy.enabledApplicationShortcuts(in: configurations),
            []
        )

        let existingShortcuts = AppDelegateShortcutConflictPolicy
            .windowRegistrationExistingShortcuts(
                windowSetting: conflictingWindowShortcut,
                configurations: configurations
            )
        try expectEqual(existingShortcuts.forward, [])
        try expectEqual(existingShortcuts.reverse, [conflictingWindowShortcut])
    }

    static func testWindowRegistrationConflictListsComeFromPolicyBoundary() throws {
        let configurations = conflictConfigurations(applicationEnabled: true)
        let applicationShortcutConflicts = AppDelegateShortcutConflictPolicy
            .enabledApplicationShortcuts(in: configurations)

        let registrationExistingShortcuts = AppDelegateShortcutConflictPolicy
            .windowRegistrationExistingShortcuts(
                windowSetting: conflictingWindowShortcut,
                configurations: configurations
            )
        try expectEqual(registrationExistingShortcuts.forward, applicationShortcutConflicts)
        try expectEqual(
            registrationExistingShortcuts.reverse,
            [conflictingWindowShortcut] + applicationShortcutConflicts
        )

        let registrar = AppDelegateConflictRecordingRegistrar()
        let service = HotkeyService(registrar: registrar)
        let result = service.registerFirstUsable(
            primaryCandidate: conflictingWindowShortcut,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: registrationExistingShortcuts.forward,
            mode: .currentAppWindowSwitching
        ) {}

        try expectEqual(result, .registered)
        try expectEqual(
            service.registeredSetting(for: .currentAppWindowSwitching),
            .fallbackCurrentAppWindowSwitching
        )
        try expectEqual(registrar.registeredKeyCodes, [50])
    }

    static func testApplicationCandidateIsAWindowRegistrationConflict() throws {
        let windowShortcut = ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "K",
            keyCode: 40,
            modifiers: ["command"],
            isUsable: true
        )
        let applicationCandidate = ShortcutSetting(
            id: "application-switching",
            mode: .applicationSwitching,
            keyEquivalent: "`",
            keyCode: 50,
            modifiers: ["option", "control"],
            isUsable: true
        )
        let configurations = [
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: true,
                shortcut: windowShortcut
            ),
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: true,
                shortcut: applicationCandidate
            )
        ]

        let conflicts = AppDelegateShortcutConflictPolicy
            .windowRegistrationExistingShortcuts(
                windowSetting: windowShortcut,
                configurations: configurations
            )

        try expectEqual(conflicts.forward.first, applicationCandidate)
        try expectEqual(
            conflicts.forward.last,
            applicationCandidate.reverseVariant(id: "application-switching-reverse")
        )
    }

    static func testApplicationShortcutTransactionSucceedsInOrder() throws {
        var events: [String] = []
        let transaction = ApplicationShortcutLifecycleTransaction(
            suspendWindow: { events.append("suspend-window") },
            registerApplicationCandidate: {
                events.append("register-app-candidate")
                return true
            },
            registerWindowWithCandidateConflicts: {
                events.append("register-window")
                return true
            },
            restorePreviousApplication: { events.append("restore-app") },
            restorePreviousWindow: { events.append("restore-window") }
        )

        try expectTrue(transaction.apply())
        try expectEqual(
            events,
            ["suspend-window", "register-app-candidate", "register-window"]
        )
    }

    static func testApplicationShortcutTransactionRestoresAfterCandidateFailure() throws {
        var events: [String] = []
        let transaction = ApplicationShortcutLifecycleTransaction(
            suspendWindow: { events.append("suspend-window") },
            registerApplicationCandidate: {
                events.append("register-app-candidate")
                return false
            },
            registerWindowWithCandidateConflicts: {
                events.append("register-window")
                return true
            },
            restorePreviousApplication: { events.append("restore-app") },
            restorePreviousWindow: { events.append("restore-window") }
        )

        try expectFalse(transaction.apply())
        try expectEqual(
            events,
            [
                "suspend-window",
                "register-app-candidate",
                "restore-app",
                "restore-window"
            ]
        )
    }

    static func testApplicationShortcutTransactionRestoresAfterWindowFailure() throws {
        var events: [String] = []
        let transaction = ApplicationShortcutLifecycleTransaction(
            suspendWindow: { events.append("suspend-window") },
            registerApplicationCandidate: {
                events.append("register-app-candidate")
                return true
            },
            registerWindowWithCandidateConflicts: {
                events.append("register-window")
                return false
            },
            restorePreviousApplication: { events.append("restore-app") },
            restorePreviousWindow: { events.append("restore-window") }
        )

        try expectFalse(transaction.apply())
        try expectEqual(
            events,
            [
                "suspend-window",
                "register-app-candidate",
                "register-window",
                "restore-app",
                "restore-window"
            ]
        )
    }

    static func testAppDelegateReferencesShortcutConflictPolicy() throws {
        let appDelegateSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SwitchTab/AppDelegate.swift"),
            encoding: .utf8
        )
        guard let appDelegateDeclaration = appDelegateSource.range(
            of: "public final class AppDelegate"
        ) else {
            throw TestFailure.failed("Expected AppDelegate declaration")
        }
        let appDelegateImplementation = appDelegateSource[appDelegateDeclaration.lowerBound...]

        try expectTrue(appDelegateImplementation.contains("AppDelegateShortcutConflictPolicy"))
        try expectTrue(appDelegateImplementation.contains("windowRegistrationExistingShortcuts"))
    }

    static func testAppDelegateUsesUnifiedShortcutLifecycle() throws {
        let source = try sourceContents(at: "SwitchTab/AppDelegate.swift")
        let implementation = try sourceSection(
            source,
            startingAt: "public final class AppDelegate",
            endingBefore: "enum ApplicationSwitcherWindowCountPolicy"
        )
        let recordingLifecycle = try sourceSection(
            implementation,
            startingAt: "private func observeShortcutRecording",
            endingBefore: "private func observeWorkspaceApplicationActivation"
        )
        guard let recordingEnd = recordingLifecycle.range(
            of: ".shortcutRecordingDidEnd"
        ) else {
            throw TestFailure.failed("Expected shortcut recording end observer")
        }
        let recordingBegin = recordingLifecycle[..<recordingEnd.lowerBound]
        let recordingRestore = recordingLifecycle[recordingEnd.lowerBound...]
        let launch = try sourceSection(
            implementation,
            startingAt: "public func applicationDidFinishLaunching",
            endingBefore: "public func applicationShouldHandleReopen"
        )
        let applicationPresentation = try sourceSection(
            implementation,
            startingAt: "public func showApplicationSwitcher",
            endingBefore: "private func thumbnailLoaderForRefresh"
        )
        let triggerShortcuts = try sourceSection(
            implementation,
            startingAt: "private func applicationTriggerShortcut",
            endingBefore: "private func registerWindowHotkeys"
        )
        let shortcutTransaction = try sourceSection(
            implementation,
            startingAt: "private func applyShortcutChange",
            endingBefore: "private func applyEnabledChange"
        )
        let requiredSymbols = [
            "shortcutStore.loadConfigurations()",
            "registerConfiguredHotkeys",
            "applyShortcutChange",
            "applyEnabledChange"
        ]
        let missingSymbols = requiredSymbols.filter { !implementation.contains($0) }

        try expectEqual(missingSymbols, [])
        try expectTrue(launch.contains("shortcutStore.loadConfigurations()"))
        try expectTrue(launch.contains("registerConfiguredHotkeys"))
        try expectTrue(recordingBegin.contains("hotkeyService.unregisterAll"))
        try expectTrue(recordingBegin.contains("applicationHotkeyController.unregisterAll"))
        try expectTrue(recordingBegin.contains("persistRegistrationMessages"))
        try expectTrue(recordingRestore.contains("shortcutStore.loadConfigurations()"))
        try expectTrue(recordingRestore.contains("registerConfiguredHotkeys"))
        try expectFalse(implementation.contains("applicationSettingsStore.replacesCommandTab"))
        try expectFalse(implementation.contains(".commandTabReplacementDidChange"))
        try expectFalse(implementation.contains("observeShortcutChanges"))
        try expectTrue(applicationPresentation.contains("applicationTriggerShortcut"))
        try expectFalse(applicationPresentation.contains(".defaultApplicationSwitching"))
        try expectTrue(triggerShortcuts.contains("configuredShortcut"))
        try expectFalse(triggerShortcuts.contains(".defaultApplicationSwitching"))
        try expectTrue(shortcutTransaction.contains("ApplicationShortcutLifecycleTransaction"))
    }

    static func testSettingsWindowInjectsUnifiedShortcutCallbacks() throws {
        let source = try sourceContents(
            at: "SwitchTab/UI/Settings/SettingsWindowController.swift"
        )
        let controller = try sourceSection(
            source,
            startingAt: "public final class SettingsWindowController",
            endingBefore: "private extension ApplicationActivationPolicy"
        )
        let initializer = try sourceSection(
            controller,
            startingAt: "public init(",
            endingBefore: "public func show()"
        )

        try expectTrue(initializer.contains("onShortcutChanged"))
        try expectTrue(initializer.contains("SwitcherShortcutConfiguration"))
        try expectTrue(initializer.contains("onEnabledChanged"))
        try expectTrue(initializer.contains("ShortcutSettingsViewModel("))
    }

    static func testDirectDistributionScriptGeneratesIsolatedProjectVariant() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("https://github.com/sparkle-project/Sparkle"))
        try expectTrue(contents.contains("SwitchTab/Resources/Info.direct.plist"))
        try expectTrue(contents.contains("DIRECT_DISTRIBUTION"))
        try expectTrue(contents.contains("plutil -replace SUEnableAutomaticChecks -bool NO"))
        try expectTrue(contents.contains("XCRemoteSwiftPackageReference"))
        try expectTrue(contents.contains("XCSwiftPackageProductDependency"))
        try expectTrue(contents.contains("xcodebuild"))
        try expectTrue(contents.contains("PBXPROJ_PATH=\"$WORKSPACE_DIR/SwitchTab.xcodeproj/project.pbxproj\""))
        try expectFalse(contents.contains("PBXPROJ_PATH=\"$PROJECT_ROOT/SwitchTab.xcodeproj/project.pbxproj\""))
    }

    static func testDirectDistributionScriptPinsSparkleToExactRevision() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("SPARKLE_PACKAGE_REVISION=\"${SPARKLE_PACKAGE_REVISION:-b6496a74a087257ef5e6da1c5b29a447a60f5bd7}\""))
        try expectTrue(contents.contains("kind = revision;"))
        try expectTrue(contents.contains("revision = #{sparkle_revision};"))
        try expectFalse(contents.contains("kind = upToNextMajorVersion;"))
        try expectFalse(contents.contains("minimumVersion = #{sparkle_version};"))
    }

    static func testDirectDistributionScriptRequiresSparklePublicKey() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("SPARKLE_PUBLIC_ED_KEY"))
        try expectTrue(contents.contains("require_env \"SPARKLE_PUBLIC_ED_KEY\" \"$SPARKLE_PUBLIC_ED_KEY\""))
    }

    static func testDirectDistributionScriptRequiresHTTPSUpdateFeedURL() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("SWITCHTAB_UPDATE_FEED_URL must start with https://"))
        try expectTrue(contents.contains("[[ ! \"$SWITCHTAB_UPDATE_FEED_URL\" == https://* ]]"))
    }

    static func testDirectDistributionScriptAutomatesReleaseArtifacts() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("--release"))
        try expectTrue(contents.contains("DEVELOPER_ID_APPLICATION"))
        try expectTrue(contents.contains("NOTARYTOOL_KEYCHAIN_PROFILE"))
        try expectTrue(contents.contains("DIRECT_RELEASE_OUTPUT_DIR"))
        try expectTrue(contents.contains("hdiutil create"))
        try expectTrue(contents.contains("notarytool submit"))
        try expectTrue(contents.contains("stapler staple"))
        try expectTrue(contents.contains("stapler validate"))
        try expectTrue(contents.contains("spctl -a -vv -t open"))
        try expectTrue(contents.contains("spctl -a -vv -t exec"))
        try expectTrue(contents.contains("shasum -a 256"))
    }

    static func testDocumentationCoversDirectDistributionBuild() throws {
        let readmeURL = projectRoot.appendingPathComponent("README.md")
        let readmeContents = try String(contentsOf: readmeURL, encoding: .utf8)
        let guideURL = projectRoot.appendingPathComponent("docs/direct-distribution.md")
        let guideContents = try String(contentsOf: guideURL, encoding: .utf8)

        try expectTrue(readmeContents.contains("AppIcon-256.png"))
        try expectTrue(readmeContents.contains("docs/development.md"))
        try expectTrue(readmeContents.contains("docs/direct-distribution.md"))
        try expectTrue(readmeContents.contains("docs/update-hosting.md"))
        try expectTrue(readmeContents.contains("docs/release-workflow.md"))
        try expectTrue(guideContents.contains("Direct Distribution"))
        try expectTrue(guideContents.contains("scripts/build-direct-distribution.sh"))
        try expectTrue(guideContents.contains("SPARKLE_PUBLIC_ED_KEY"))
        try expectTrue(guideContents.contains("SWITCHTAB_UPDATE_FEED_URL"))
        try expectTrue(guideContents.contains("DEVELOPER_ID_APPLICATION"))
    }

    private static var customApplicationShortcut: ShortcutSetting {
        ShortcutSetting.defaultApplicationSwitching.replacingWithValidation(
            keyEquivalent: "Space",
            keyCode: 49,
            modifiers: ["option", "control"],
            isUsable: true
        )
    }

    private static var conflictingWindowShortcut: ShortcutSetting {
        ShortcutSetting(
            id: "current-app-window-switching",
            mode: .currentAppWindowSwitching,
            keyEquivalent: "Space",
            keyCode: 49,
            modifiers: ["option", "control"],
            isUsable: true
        )
    }

    private static func conflictConfigurations(
        applicationEnabled: Bool
    ) -> [SwitcherShortcutConfiguration] {
        [
            SwitcherShortcutConfiguration(
                mode: .currentAppWindowSwitching,
                isEnabled: true,
                shortcut: conflictingWindowShortcut
            ),
            SwitcherShortcutConfiguration(
                mode: .applicationSwitching,
                isEnabled: applicationEnabled,
                shortcut: customApplicationShortcut
            )
        ]
    }

    private static func sourceContents(at path: String) throws -> String {
        try String(
            contentsOf: projectRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func sourceSection(
        _ source: some StringProtocol,
        startingAt startMarker: String,
        endingBefore endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker),
              let end = source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
              ) else {
            throw TestFailure.failed(
                "Expected source section from \(startMarker) to \(endMarker)"
            )
        }

        return Substring(source[start.lowerBound..<end.lowerBound])
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class AppDelegateConflictRecordingRegistrar: HotkeyRegistering {
    private(set) var registeredKeyCodes: [UInt16?] = []

    func register(setting: ShortcutSetting, handler _: @escaping () -> Void) -> Bool {
        registeredKeyCodes.append(setting.keyCode)
        return true
    }

    func unregisterAll() {}
}
