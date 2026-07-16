import Foundation

enum AppStoreDistributionSettingsTests {
    static func run() throws {
        try testInfoPlistUsesAppStoreBundleIdentifier()
        try testInfoPlistDeclaresAppBundleMetadata()
        try testBuildAndDistributionPathsUseSwitchTab()
        try testXcodeProjectUsesAppStoreBundleIdentifier()
        try testAppSandboxIsDisabledForGlobalWindowSwitching()
        try testSparkleAdapterIsDirectDistributionGuarded()
        try testDirectDistributionScriptGeneratesIsolatedProjectVariant()
        try testDirectDistributionScriptPinsSparkleToExactRevision()
        try testDirectDistributionScriptRequiresSparklePublicKey()
        try testDirectDistributionScriptRequiresHTTPSUpdateFeedURL()
        try testDirectDistributionScriptAutomatesReleaseArtifacts()
        try testReadmeDocumentsDirectDistributionBuild()
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

    static func testReadmeDocumentsDirectDistributionBuild() throws {
        let readmeURL = projectRoot.appendingPathComponent("README.md")
        let contents = try String(contentsOf: readmeURL, encoding: .utf8)

        try expectTrue(contents.contains("Direct Distribution Build"))
        try expectTrue(contents.contains("scripts/build-direct-distribution.sh"))
        try expectTrue(contents.contains("SPARKLE_PUBLIC_ED_KEY"))
        try expectTrue(contents.contains("SWITCHTAB_UPDATE_FEED_URL"))
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
