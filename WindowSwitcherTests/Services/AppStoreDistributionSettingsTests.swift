import Foundation

enum AppStoreDistributionSettingsTests {
    static func run() throws {
        try testInfoPlistUsesAppStoreBundleIdentifier()
        try testInfoPlistDeclaresAppBundleMetadata()
        try testXcodeProjectUsesAppStoreBundleIdentifier()
        try testAppSandboxIsDisabledForGlobalWindowSwitching()
        try testSparkleAdapterIsDirectDistributionGuarded()
        try testDirectDistributionScriptGeneratesIsolatedProjectVariant()
        try testDirectDistributionScriptRequiresSparklePublicKey()
        try testDirectDistributionScriptAutomatesReleaseArtifacts()
        try testReadmeDocumentsDirectDistributionBuild()
    }

    static func testInfoPlistUsesAppStoreBundleIdentifier() throws {
        let infoPlistURL = projectRoot.appendingPathComponent("WindowSwitcher/Resources/Info.plist")
        let contents = try String(contentsOf: infoPlistURL, encoding: .utf8)

        try expectTrue(contents.contains("<string>com.royjen.switchtab</string>"))
        try expectFalse(contents.contains("com.local.SwitchTab"))
    }

    static func testInfoPlistDeclaresAppBundleMetadata() throws {
        let infoPlistURL = projectRoot.appendingPathComponent("WindowSwitcher/Resources/Info.plist")
        let contents = try String(contentsOf: infoPlistURL, encoding: .utf8)

        try expectTrue(contents.contains("<key>CFBundleExecutable</key>"))
        try expectTrue(contents.contains("<string>$(EXECUTABLE_NAME)</string>"))
        try expectTrue(contents.contains("<key>CFBundlePackageType</key>"))
        try expectTrue(contents.contains("<string>APPL</string>"))
    }

    static func testXcodeProjectUsesAppStoreBundleIdentifier() throws {
        let projectURL = projectRoot.appendingPathComponent("WindowSwitcher.xcodeproj/project.pbxproj")
        let contents = try String(contentsOf: projectURL, encoding: .utf8)

        try expectTrue(contents.contains("PRODUCT_BUNDLE_IDENTIFIER = com.royjen.switchtab;"))
        try expectFalse(contents.contains("PRODUCT_BUNDLE_IDENTIFIER = com.local.SwitchTab;"))
    }

    static func testAppSandboxIsDisabledForGlobalWindowSwitching() throws {
        let entitlementsURL = projectRoot.appendingPathComponent("WindowSwitcher/Resources/WindowSwitcher.entitlements")
        let contents = try String(contentsOf: entitlementsURL, encoding: .utf8)

        try expectFalse(contents.contains("<key>com.apple.security.app-sandbox</key>"))
        try expectFalse(contents.contains("<false/>"))
    }

    static func testSparkleAdapterIsDirectDistributionGuarded() throws {
        let adapterURL = projectRoot.appendingPathComponent("WindowSwitcher/Services/SparkleUpdateController.swift")
        let contents = try String(contentsOf: adapterURL, encoding: .utf8)

        try expectTrue(contents.contains("#if DIRECT_DISTRIBUTION && canImport(Sparkle)"))
        try expectTrue(contents.contains("import Sparkle"))

        let projectURL = projectRoot.appendingPathComponent("WindowSwitcher.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

        try expectFalse(projectContents.contains("DIRECT_DISTRIBUTION;"))
    }

    static func testDirectDistributionScriptGeneratesIsolatedProjectVariant() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("SPARKLE_PACKAGE_VERSION=\"${SPARKLE_PACKAGE_VERSION:-2.9.3}\""))
        try expectTrue(contents.contains("https://github.com/sparkle-project/Sparkle"))
        try expectTrue(contents.contains("WindowSwitcher/Resources/Info.direct.plist"))
        try expectTrue(contents.contains("DIRECT_DISTRIBUTION"))
        try expectTrue(contents.contains("XCRemoteSwiftPackageReference"))
        try expectTrue(contents.contains("XCSwiftPackageProductDependency"))
        try expectTrue(contents.contains("xcodebuild"))
        try expectTrue(contents.contains("PBXPROJ_PATH=\"$WORKSPACE_DIR/WindowSwitcher.xcodeproj/project.pbxproj\""))
        try expectFalse(contents.contains("PBXPROJ_PATH=\"$PROJECT_ROOT/WindowSwitcher.xcodeproj/project.pbxproj\""))
    }

    static func testDirectDistributionScriptRequiresSparklePublicKey() throws {
        let scriptURL = projectRoot.appendingPathComponent("scripts/build-direct-distribution.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        try expectTrue(contents.contains("SPARKLE_PUBLIC_ED_KEY"))
        try expectTrue(contents.contains("require_env \"SPARKLE_PUBLIC_ED_KEY\" \"$SPARKLE_PUBLIC_ED_KEY\""))
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
