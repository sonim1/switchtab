#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
WORKSPACE_DIR="$BUILD_ROOT/workspace"
DERIVED_DATA_DIR="$BUILD_ROOT/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"
SWITCHTAB_UPDATE_FEED_URL="${SWITCHTAB_UPDATE_FEED_URL:-https://updates.switchtab.royjen.com/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PACKAGE_REVISION="${SPARKLE_PACKAGE_REVISION:-b6496a74a087257ef5e6da1c5b29a447a60f5bd7}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARYTOOL_KEYCHAIN_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"
NOTARYTOOL_KEYCHAIN_PATH="${NOTARYTOOL_KEYCHAIN_PATH:-}"
DIRECT_RELEASE_OUTPUT_DIR="${DIRECT_RELEASE_OUTPUT_DIR:-$BUILD_ROOT/release}"
PREPARE_ONLY=0
RELEASE=0
CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"

usage() {
    cat <<'EOF'
Usage: scripts/build-direct-distribution.sh [--prepare-only] [--release]

Environment:
  SPARKLE_PUBLIC_ED_KEY          Required Sparkle EdDSA public key.
  SWITCHTAB_UPDATE_FEED_URL      Optional appcast URL. Defaults to https://updates.switchtab.royjen.com/appcast.xml
  SPARKLE_PACKAGE_REVISION       Optional Sparkle package commit revision. Defaults to Sparkle 2.9.4.
  CONFIGURATION                  Optional Xcode configuration. Defaults to Release
  CODESIGN_BIN                   Optional codesign executable. Defaults to /usr/bin/codesign.
  DIRECT_BUILD_ROOT              Optional generated workspace root. Defaults to .build/direct-distribution
  DIRECT_RELEASE_OUTPUT_DIR      Optional release artifact directory. Defaults to .build/direct-distribution/release
  DEVELOPER_ID_APPLICATION       Required with --release. Example: Developer ID Application: Name (TEAMID)
  NOTARYTOOL_KEYCHAIN_PROFILE    Required with --release. Keychain profile created by xcrun notarytool store-credentials.
  NOTARYTOOL_KEYCHAIN_PATH       Optional Keychain containing the notarytool profile.
EOF
}

require_env() {
    local name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "$name is required" >&2
        exit 64
    fi
}

sign_code() {
    local path="$1"

    if [[ -e "$path" ]]; then
        local codesign_args=(--force --options runtime)

        if [[ "$RELEASE" == "1" ]]; then
            codesign_args+=(--timestamp --sign "$DEVELOPER_ID_APPLICATION")
        else
            codesign_args+=(--sign -)
        fi

        "$CODESIGN_BIN" "${codesign_args[@]}" "$path"
    fi
}

sign_app_bundle() {
    local app_path="$1"
    local sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
    local sparkle_current="$sparkle_framework/Versions/Current"

    sign_code "$sparkle_current/Autoupdate"
    sign_code "$sparkle_current/Updater.app"
    sign_code "$sparkle_current/XPCServices/Downloader.xpc"
    sign_code "$sparkle_current/XPCServices/Installer.xpc"
    sign_code "$sparkle_framework"
    sign_code "$app_path"

    "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$app_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prepare-only)
            PREPARE_ONLY=1
            shift
            ;;
        --release)
            RELEASE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

require_env "SPARKLE_PUBLIC_ED_KEY" "$SPARKLE_PUBLIC_ED_KEY"

if [[ ! "$SPARKLE_PACKAGE_REVISION" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "SPARKLE_PACKAGE_REVISION must be a 40-character git revision" >&2
    exit 64
fi

if [[ ! "$SWITCHTAB_UPDATE_FEED_URL" == https://* ]]; then
    echo "SWITCHTAB_UPDATE_FEED_URL must start with https://" >&2
    exit 64
fi

if [[ "$PREPARE_ONLY" == "1" && "$RELEASE" == "1" ]]; then
    echo "--prepare-only and --release cannot be used together" >&2
    exit 64
fi

if [[ "$RELEASE" == "1" ]]; then
    require_env "DEVELOPER_ID_APPLICATION" "$DEVELOPER_ID_APPLICATION"
    require_env "NOTARYTOOL_KEYCHAIN_PROFILE" "$NOTARYTOOL_KEYCHAIN_PROFILE"
fi

rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR" "$DERIVED_DATA_DIR"

rsync -a \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    "$PROJECT_ROOT/" \
    "$WORKSPACE_DIR/"

DIRECT_INFO_PLIST="$WORKSPACE_DIR/SwitchTab/Resources/Info.direct.plist"
cp "$WORKSPACE_DIR/SwitchTab/Resources/Info.plist" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUFeedURL -string "$SWITCHTAB_UPDATE_FEED_URL" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUEnableAutomaticChecks -bool NO "$DIRECT_INFO_PLIST"

PBXPROJ_PATH="$WORKSPACE_DIR/SwitchTab.xcodeproj/project.pbxproj"
/usr/bin/ruby - "$PBXPROJ_PATH" "$SPARKLE_PACKAGE_REVISION" <<'RUBY'
path = ARGV.fetch(0)
sparkle_revision = ARGV.fetch(1)
project = File.read(path)

build_file_id = "F10000000000000000000001"
package_ref_id = "F10000000000000000000002"
product_dep_id = "F10000000000000000000003"

def replace_once!(project, before, after, label)
  unless project.include?(before)
    raise "Could not patch #{label}"
  end
  project.sub!(before, after)
end

replace_once!(
  project,
  "/* Begin PBXBuildFile section */\n",
  "/* Begin PBXBuildFile section */\n\t\t#{build_file_id} /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = #{product_dep_id} /* Sparkle */; };\n",
  "Sparkle framework build file"
)

replace_once!(
  project,
  "\t\tF00000000000000000000001 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
  "\t\tF00000000000000000000001 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t#{build_file_id} /* Sparkle in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
  "app framework build phase"
)

replace_once!(
  project,
  "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = SwitchTab;\n\t\t\tproductName = SwitchTab;\n",
  "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = SwitchTab;\n\t\t\tpackageProductDependencies = (\n\t\t\t\t#{product_dep_id} /* Sparkle */,\n\t\t\t);\n\t\t\tproductName = SwitchTab;\n",
  "app target package product dependency"
)

replace_once!(
  project,
  "\t\t\tmainGroup = G00000000000000000000001;\n\t\t\tproductRefGroup = G00000000000000000000015 /* Products */;\n",
  "\t\t\tmainGroup = G00000000000000000000001;\n\t\t\tpackageReferences = (\n\t\t\t\t#{package_ref_id} /* XCRemoteSwiftPackageReference \"Sparkle\" */,\n\t\t\t);\n\t\t\tproductRefGroup = G00000000000000000000015 /* Products */;\n",
  "project package reference"
)

package_sections = <<~SECTIONS
/* Begin XCRemoteSwiftPackageReference section */
\t\t#{package_ref_id} /* XCRemoteSwiftPackageReference "Sparkle" */ = {
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/sparkle-project/Sparkle";
\t\t\trequirement = {
\t\t\t\tkind = revision;
\t\t\t\trevision = #{sparkle_revision};
\t\t\t};
\t\t};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t#{product_dep_id} /* Sparkle */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = #{package_ref_id} /* XCRemoteSwiftPackageReference "Sparkle" */;
\t\t\tproductName = Sparkle;
\t\t};
/* End XCSwiftPackageProductDependency section */

SECTIONS

replace_once!(
  project,
  "/* Begin XCBuildConfiguration section */\n",
  package_sections + "/* Begin XCBuildConfiguration section */\n",
  "Swift package sections"
)

project.gsub!("INFOPLIST_FILE = SwitchTab/Resources/Info.plist;", "INFOPLIST_FILE = SwitchTab/Resources/Info.direct.plist;")

count = 0
project.gsub!("PRODUCT_NAME = SwitchTab;\n\t\t\t\tSWIFT_VERSION = 5.0;") do
  count += 1
  condition = count == 1 ? '"$(inherited) DEBUG DIRECT_DISTRIBUTION"' : '"$(inherited) DIRECT_DISTRIBUTION"'
  "PRODUCT_NAME = SwitchTab;\n\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = #{condition};\n\t\t\t\tSWIFT_VERSION = 5.0;"
end

unless count == 2
  raise "Expected to patch two app build configurations, patched #{count}"
end

File.write(path, project)
RUBY

/usr/bin/plutil -lint "$PBXPROJ_PATH" >/dev/null
/usr/bin/plutil -lint "$DIRECT_INFO_PLIST" >/dev/null

if [[ "$PREPARE_ONLY" == "1" ]]; then
    echo "Prepared direct distribution workspace: $WORKSPACE_DIR"
    exit 0
fi

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild \
    -project "$WORKSPACE_DIR/SwitchTab.xcodeproj" \
    -scheme SwitchTab \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    build

echo "Built direct distribution app:"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/SwitchTab.app"
echo "$APP_PATH"

if [[ "$RELEASE" != "1" ]]; then
    sign_app_bundle "$APP_PATH"
    exit 0
fi

mkdir -p "$DIRECT_RELEASE_OUTPUT_DIR"
DMG_PATH="$DIRECT_RELEASE_OUTPUT_DIR/SwitchTab.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

sign_app_bundle "$APP_PATH"

/usr/bin/hdiutil create \
    -volname "SwitchTab" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$DMG_PATH"

/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

NOTARYTOOL_ARGS=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
if [[ -n "$NOTARYTOOL_KEYCHAIN_PATH" ]]; then
    NOTARYTOOL_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN_PATH")
fi

xcrun notarytool submit \
    "$DMG_PATH" \
    "${NOTARYTOOL_ARGS[@]}" \
    --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

/usr/sbin/spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
/usr/sbin/spctl -a -vv -t exec "$APP_PATH"

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

echo "Built notarized direct distribution DMG:"
echo "$DMG_PATH"
echo "Wrote checksum:"
echo "$CHECKSUM_PATH"
