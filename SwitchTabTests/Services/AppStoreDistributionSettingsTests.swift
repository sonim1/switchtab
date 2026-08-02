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
        try testAppDelegateReferencesShortcutConflictPolicy()
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
