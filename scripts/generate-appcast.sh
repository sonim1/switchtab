#!/usr/bin/env bash
set -euo pipefail
set +x

export LC_ALL=C

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/generate-appcast.sh

Generates and validates a signed Sparkle appcast from the current notarized DMG.
Configuration is read from RELEASE_CONFIG_PATH when that file exists; CI may
provide the same settings through the environment.
EOF
}

if [[ $# -ne 0 ]]; then
    echo "Unexpected arguments" >&2
    usage >&2
    exit 64
fi

RELEASE_CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
if [[ -f "$RELEASE_CONFIG_PATH" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$RELEASE_CONFIG_PATH"
    set +a
fi
set +x

BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
RELEASE_DIR="${DIRECT_RELEASE_OUTPUT_DIR:-$BUILD_ROOT/release}"
UPDATE_OUTPUT_DIR="${UPDATE_OUTPUT_DIR:-$BUILD_ROOT/updates}"
CONFIGURATION="${CONFIGURATION:-Release}"
DIRECT_APP_PATH="${DIRECT_APP_PATH:-$BUILD_ROOT/DerivedData/Build/Products/$CONFIGURATION/SwitchTab.app}"
DMG_PATH="${DMG_PATH:-${DMG:-$RELEASE_DIR/SwitchTab.dmg}}"
CHECKSUM_PATH="${CHECKSUM_PATH:-$DMG_PATH.sha256}"
APP_INFO_PLIST="${APP_INFO_PLIST:-$DIRECT_APP_PATH/Contents/Info.plist}"

SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
APPCAST_PRIVATE_KEY="${SPARKLE_PRIVATE_ED_KEY:-}"
unset SPARKLE_PRIVATE_ED_KEY PRIVATE_ED_KEY
export -n APPCAST_PRIVATE_KEY 2>/dev/null || :
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.royjen.com}"
DOWNLOAD_URL_PREFIX="https://$UPDATE_DOMAIN/"

CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
XCRUN_BIN="${XCRUN_BIN:-/usr/bin/xcrun}"
SPCTL_BIN="${SPCTL_BIN:-/usr/sbin/spctl}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
SPARKLE_APPCAST_BIN="${SPARKLE_APPCAST_BIN:-$BUILD_ROOT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast}"

fail() {
    local message="$1"
    local code="${2:-66}"

    echo "$message" >&2
    exit "$code"
}

command_available() {
    local command_path="$1"

    if [[ "$command_path" == */* ]]; then
        [[ -x "$command_path" ]]
    else
        command -v "$command_path" >/dev/null 2>&1
    fi
}

require_command() {
    local label="$1"
    local command_path="$2"

    if ! command_available "$command_path"; then
        fail "$label command is unavailable: $command_path" 66
    fi
}

require_file() {
    local label="$1"
    local path="$2"

    if [[ ! -f "$path" ]]; then
        fail "Required $label is missing: $path" 66
    fi
}

run_external() {
    local label="$1"
    shift

    local result
    if "$@"; then
        return 0
    else
        result=$?
        echo "$label failed" >&2
        return "$result"
    fi
}

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "SPARKLE_PUBLIC_ED_KEY is required" 64
fi
if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    fail "SPARKLE_PUBLIC_ED_KEY must be a 44-character standard base64 Ed25519 public key" 64
fi

require_file "DMG" "$DMG_PATH"
require_file "DMG checksum" "$CHECKSUM_PATH"
require_file "app Info.plist" "$APP_INFO_PLIST"

require_command "codesign" "$CODESIGN_BIN"
require_command "xcrun" "$XCRUN_BIN"
require_command "Gatekeeper" "$SPCTL_BIN"
require_command "plutil" "$PLUTIL_BIN"
require_command "shasum" "$SHASUM_BIN"
require_command "xmllint" "$XMLLINT_BIN"
require_command "Sparkle generate_appcast" "$SPARKLE_APPCAST_BIN"

CHECKSUM_LINE_COUNT=0
CHECKSUM_LINE=''
while IFS= read -r checksum_line || [[ -n "$checksum_line" ]]; do
    CHECKSUM_LINE_COUNT=$((CHECKSUM_LINE_COUNT + 1))
    if [[ "$CHECKSUM_LINE_COUNT" -gt 1 ]]; then
        fail "DMG checksum manifest must contain exactly one entry"
    fi
    CHECKSUM_LINE="$checksum_line"
done < "$CHECKSUM_PATH"

if [[ "$CHECKSUM_LINE_COUNT" -ne 1 ]]; then
    fail "DMG checksum manifest must contain exactly one entry"
fi
if [[ ! "$CHECKSUM_LINE" =~ ^([A-Fa-f0-9]{64})[[:space:]]+[^[:space:]].*$ ]]; then
    fail "DMG checksum manifest is malformed"
fi
EXPECTED_CHECKSUM="${BASH_REMATCH[1]}"

if ACTUAL_CHECKSUM_OUTPUT="$("$SHASUM_BIN" -a 256 "$DMG_PATH")"; then
    :
else
    checksum_status=$?
    echo "DMG checksum computation failed" >&2
    exit "$checksum_status"
fi
if [[ ! "$ACTUAL_CHECKSUM_OUTPUT" =~ ^([A-Fa-f0-9]{64})[[:space:]] ]]; then
    fail "DMG checksum command returned a malformed digest"
fi
ACTUAL_CHECKSUM="${BASH_REMATCH[1]}"
EXPECTED_CHECKSUM="$(printf '%s' "$EXPECTED_CHECKSUM" | tr '[:upper:]' '[:lower:]')"
ACTUAL_CHECKSUM="$(printf '%s' "$ACTUAL_CHECKSUM" | tr '[:upper:]' '[:lower:]')"
if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
    fail "DMG checksum mismatch: $DMG_PATH"
fi

run_external "DMG codesign verification" "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$DMG_PATH"
run_external "DMG stapler validation" "$XCRUN_BIN" stapler validate "$DMG_PATH"
run_external "Gatekeeper open assessment" "$SPCTL_BIN" -a -vv -t open --context context:primary-signature "$DMG_PATH"

plist_value() {
    local key="$1"
    local value
    local result

    if value="$("$PLUTIL_BIN" -extract "$key" raw -o - "$APP_INFO_PLIST")"; then
        printf '%s' "$value"
        return 0
    else
        result=$?
        echo "Failed to read $key from app Info.plist: $APP_INFO_PLIST" >&2
        return "$result"
    fi
}

MARKETING_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_value CFBundleVersion)"
EMBEDDED_PUBLIC_ED_KEY="$(plist_value SUPublicEDKey)"

if [[ -z "$MARKETING_VERSION" || ! "$MARKETING_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "CFBundleShortVersionString is not a safe version component: $MARKETING_VERSION"
fi
if [[ -z "$BUILD_NUMBER" || ! "$BUILD_NUMBER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "CFBundleVersion is not a safe version component: $BUILD_NUMBER"
fi
if [[ "$EMBEDDED_PUBLIC_ED_KEY" != "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "Built app SUPublicEDKey public key mismatch"
fi

VERSIONED_DMG_NAME="SwitchTab-${MARKETING_VERSION}-${BUILD_NUMBER}.dmg"
VERSIONED_CHECKSUM_NAME="$VERSIONED_DMG_NAME.sha256"
APPCAST_WORK_DIR=""
FINAL_TEMP_DIR=""
cleanup() {
    if [[ -n "$APPCAST_WORK_DIR" && -d "$APPCAST_WORK_DIR" ]]; then
        rm -rf "$APPCAST_WORK_DIR"
    fi
    if [[ -n "$FINAL_TEMP_DIR" && -d "$FINAL_TEMP_DIR" ]]; then
        rm -rf "$FINAL_TEMP_DIR"
    fi
}
trap cleanup EXIT

if ! APPCAST_WORK_DIR="$(mktemp -d "$BUILD_ROOT/generate-appcast.XXXXXX")"; then
    fail "Unable to create temporary appcast directory under $BUILD_ROOT"
fi

STAGED_DMG_PATH="$APPCAST_WORK_DIR/$VERSIONED_DMG_NAME"
STAGED_CHECKSUM_PATH="$APPCAST_WORK_DIR/$VERSIONED_CHECKSUM_NAME"
APPCAST_PATH="$APPCAST_WORK_DIR/appcast.xml"
run_external "Staging DMG" cp "$DMG_PATH" "$STAGED_DMG_PATH"

generate_appcast() {
    local result

    if [[ -n "$APPCAST_PRIVATE_KEY" ]]; then
        if printf '%s\n' "$APPCAST_PRIVATE_KEY" | "$SPARKLE_APPCAST_BIN" \
            --ed-key-file - \
            --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
            -o "$APPCAST_PATH" \
            "$APPCAST_WORK_DIR"; then
            return 0
        else
            result=$?
            echo "Sparkle generate_appcast failed" >&2
            return "$result"
        fi
    fi

    if "$SPARKLE_APPCAST_BIN" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
        -o "$APPCAST_PATH" \
        "$APPCAST_WORK_DIR"; then
        return 0
    else
        result=$?
        echo "Sparkle generate_appcast failed" >&2
        return "$result"
    fi
}

generate_appcast
if [[ ! -s "$APPCAST_PATH" ]]; then
    fail "Sparkle generate_appcast produced no appcast.xml"
fi
run_external "Generated appcast XML validation" "$XMLLINT_BIN" --noout "$APPCAST_PATH"

xml_value() {
    local expression="$1"
    local value
    local result

    if value="$("$XMLLINT_BIN" --xpath "$expression" "$APPCAST_PATH")"; then
        printf '%s' "$value"
        return 0
    else
        result=$?
        echo "Unable to inspect generated appcast XML" >&2
        return "$result"
    fi
}

ENCLOSURE_COUNT="$(xml_value 'count(//*[local-name()="enclosure"])')"
if [[ "$ENCLOSURE_COUNT" != "1" ]]; then
    fail "Generated appcast must contain exactly one enclosure"
fi

EXPECTED_DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX}${VERSIONED_DMG_NAME}"
ENCLOSURE_URL="$(xml_value 'string((//*[local-name()="enclosure"]/@url)[1])')"
if [[ "$ENCLOSURE_URL" != "$EXPECTED_DOWNLOAD_URL" ]]; then
    fail "Generated appcast enclosure URL mismatch: expected $EXPECTED_DOWNLOAD_URL, got $ENCLOSURE_URL"
fi

ED_SIGNATURE="$(xml_value 'string((//*[local-name()="enclosure"]/@*[local-name()="edSignature"])[1])')"
if [[ -z "$ED_SIGNATURE" ]]; then
    fail "Generated appcast enclosure has empty sparkle:edSignature"
fi

APPCAST_BUILD_NUMBER="$(xml_value 'string((//*[local-name()="item"]/*[local-name()="version"] | //*[local-name()="enclosure"]/@*[local-name()="version"])[1])')"
if [[ -z "$APPCAST_BUILD_NUMBER" ]]; then
    fail "Generated appcast is missing sparkle:version"
fi
if [[ "$APPCAST_BUILD_NUMBER" != "$BUILD_NUMBER" ]]; then
    fail "Generated appcast sparkle:version mismatch: expected $BUILD_NUMBER, got $APPCAST_BUILD_NUMBER"
fi
APPCAST_MARKETING_VERSION="$(xml_value 'string((//*[local-name()="item"]/*[local-name()="shortVersionString"] | //*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])[1])')"
if [[ -z "$APPCAST_MARKETING_VERSION" ]]; then
    fail "Generated appcast is missing sparkle:shortVersionString"
fi
if [[ "$APPCAST_MARKETING_VERSION" != "$MARKETING_VERSION" ]]; then
    fail "Generated appcast sparkle:shortVersionString mismatch: expected $MARKETING_VERSION, got $APPCAST_MARKETING_VERSION"
fi

if (cd -- "$APPCAST_WORK_DIR" && run_external "Staged DMG checksum generation" "$SHASUM_BIN" -a 256 "$VERSIONED_DMG_NAME" > "$STAGED_CHECKSUM_PATH"); then
    :
else
    staged_checksum_status=$?
    exit "$staged_checksum_status"
fi

if [[ -L "$UPDATE_OUTPUT_DIR" || ( -e "$UPDATE_OUTPUT_DIR" && ! -d "$UPDATE_OUTPUT_DIR" ) ]]; then
    fail "Update output root is not a directory: $UPDATE_OUTPUT_DIR"
fi
if [[ -d "$UPDATE_OUTPUT_DIR" ]]; then
    :
else
    if mkdir -p "$UPDATE_OUTPUT_DIR"; then
        :
    else
        output_root_status=$?
        echo "Unable to create update output root: $UPDATE_OUTPUT_DIR" >&2
        exit "$output_root_status"
    fi
fi

FINAL_DMG_PATH="$UPDATE_OUTPUT_DIR/$VERSIONED_DMG_NAME"
FINAL_CHECKSUM_PATH="$UPDATE_OUTPUT_DIR/$VERSIONED_CHECKSUM_NAME"
FINAL_APPCAST_PATH="$UPDATE_OUTPUT_DIR/appcast.xml"
for destination in "$FINAL_DMG_PATH" "$FINAL_CHECKSUM_PATH" "$FINAL_APPCAST_PATH"; do
    if [[ -L "$destination" || -d "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
        fail "Update output destination conflicts with a non-regular file: $destination"
    fi
done

if FINAL_TEMP_DIR="$(mktemp -d "$UPDATE_OUTPUT_DIR/.generate-appcast.XXXXXX")"; then
    :
else
    temp_dir_status=$?
    echo "Unable to create temporary update output directory: $UPDATE_OUTPUT_DIR" >&2
    exit "$temp_dir_status"
fi
FINAL_TEMP_DMG="$FINAL_TEMP_DIR/$VERSIONED_DMG_NAME"
FINAL_TEMP_CHECKSUM="$FINAL_TEMP_DIR/$VERSIONED_CHECKSUM_NAME"
FINAL_TEMP_APPCAST="$FINAL_TEMP_DIR/appcast.xml"
run_external "Preparing versioned DMG" cp "$STAGED_DMG_PATH" "$FINAL_TEMP_DMG"
run_external "Preparing versioned checksum" cp "$STAGED_CHECKSUM_PATH" "$FINAL_TEMP_CHECKSUM"
run_external "Preparing appcast" cp "$APPCAST_PATH" "$FINAL_TEMP_APPCAST"

run_external "Finalizing versioned DMG" mv "$FINAL_TEMP_DMG" "$FINAL_DMG_PATH"
run_external "Finalizing versioned checksum" mv "$FINAL_TEMP_CHECKSUM" "$FINAL_CHECKSUM_PATH"
run_external "Finalizing appcast" mv "$FINAL_TEMP_APPCAST" "$FINAL_APPCAST_PATH"

echo "Generated Sparkle appcast: $FINAL_APPCAST_PATH"
