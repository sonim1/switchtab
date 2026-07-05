#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
WORKSPACE_DIR="$BUILD_ROOT/workspace"
DERIVED_DATA_DIR="$BUILD_ROOT/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"
SWITCHTAB_UPDATE_FEED_URL="${SWITCHTAB_UPDATE_FEED_URL:-https://updates.switchtab.app/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PACKAGE_VERSION="${SPARKLE_PACKAGE_VERSION:-2.9.3}"
PREPARE_ONLY=0

usage() {
    cat <<'EOF'
Usage: scripts/build-direct-distribution.sh [--prepare-only]

Environment:
  SPARKLE_PUBLIC_ED_KEY       Required Sparkle EdDSA public key.
  SWITCHTAB_UPDATE_FEED_URL   Optional appcast URL. Defaults to https://updates.switchtab.app/appcast.xml
  SPARKLE_PACKAGE_VERSION     Optional Sparkle package minimum version. Defaults to 2.9.3
  CONFIGURATION               Optional Xcode configuration. Defaults to Release
  DIRECT_BUILD_ROOT           Optional generated workspace root. Defaults to .build/direct-distribution
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prepare-only)
            PREPARE_ONLY=1
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

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required" >&2
    exit 64
fi

rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR" "$DERIVED_DATA_DIR"

rsync -a \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    "$PROJECT_ROOT/" \
    "$WORKSPACE_DIR/"

DIRECT_INFO_PLIST="$WORKSPACE_DIR/WindowSwitcher/Resources/Info.direct.plist"
cp "$WORKSPACE_DIR/WindowSwitcher/Resources/Info.plist" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUFeedURL -string "$SWITCHTAB_UPDATE_FEED_URL" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$DIRECT_INFO_PLIST"
/usr/bin/plutil -replace SUEnableAutomaticChecks -bool YES "$DIRECT_INFO_PLIST"

PBXPROJ_PATH="$WORKSPACE_DIR/WindowSwitcher.xcodeproj/project.pbxproj"
/usr/bin/ruby - "$PBXPROJ_PATH" "$SPARKLE_PACKAGE_VERSION" <<'RUBY'
path = ARGV.fetch(0)
sparkle_version = ARGV.fetch(1)
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
  "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = WindowSwitcher;\n\t\t\tproductName = WindowSwitcher;\n",
  "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = WindowSwitcher;\n\t\t\tpackageProductDependencies = (\n\t\t\t\t#{product_dep_id} /* Sparkle */,\n\t\t\t);\n\t\t\tproductName = WindowSwitcher;\n",
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
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = #{sparkle_version};
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

project.gsub!("INFOPLIST_FILE = WindowSwitcher/Resources/Info.plist;", "INFOPLIST_FILE = WindowSwitcher/Resources/Info.direct.plist;")

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
    -project "$WORKSPACE_DIR/WindowSwitcher.xcodeproj" \
    -scheme WindowSwitcher \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    build

echo "Built direct distribution app:"
echo "$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/SwitchTab.app"
