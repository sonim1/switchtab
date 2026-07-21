#!/usr/bin/env bash
set -euo pipefail
set +x

export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/publish-update.sh

Publishes generated Sparkle update artifacts to Cloudflare R2.
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

R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab-updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.app}"
UPDATE_ARTIFACT_DIR="${UPDATE_ARTIFACT_DIR:-$PROJECT_ROOT/.build/direct-distribution/updates}"
WRANGLER_BIN="${WRANGLER_BIN:-$PROJECT_ROOT/node_modules/.bin/wrangler}"
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"

APPCAST_PATH="$UPDATE_ARTIFACT_DIR/appcast.xml"
IMMUTABLE_CACHE='public, max-age=31536000, immutable'
APPCAST_CACHE='public, max-age=60'
TEMP_DIR=''

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

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

require_command "Wrangler" "$WRANGLER_BIN"
require_command "curl" "$CURL_BIN"
require_command "shasum" "$SHASUM_BIN"
require_command "xmllint" "$XMLLINT_BIN"
require_command "cmp" "$CMP_BIN"
require_file "appcast" "$APPCAST_PATH"

if [[ ! "$R2_BUCKET_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    fail "R2_BUCKET_NAME is not a safe bucket name" 64
fi
if [[ ! "$UPDATE_DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ || "$UPDATE_DOMAIN" == *..* ]]; then
    fail "UPDATE_DOMAIN is not a safe domain name" 64
fi

validate_xml() {
    local path="$1"
    run_external "XML validation" "$XMLLINT_BIN" --noout "$path"
}

xml_value() {
    local path="$1"
    local expression="$2"
    local value result

    if value="$("$XMLLINT_BIN" --xpath "$expression" "$path")"; then
        printf '%s' "$value"
        return 0
    else
        result=$?
        echo "Unable to inspect appcast XML" >&2
        return "$result"
    fi
}

appcast_enclosure_url() {
    local path="$1"
    local count url result

    if validate_xml "$path"; then
        :
    else
        result=$?
        return "$result"
    fi
    if count="$(xml_value "$path" 'count(//*[local-name()="enclosure"])')"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ "$count" != 1 ]]; then
        fail "Appcast must contain exactly one enclosure"
    fi
    if url="$(xml_value "$path" 'string((//*[local-name()="enclosure"]/@url)[1])')"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ -z "$url" ]]; then
        fail "Appcast enclosure URL is missing"
    fi
    printf '%s' "$url"
}

if ENCLOSURE_URL="$(appcast_enclosure_url "$APPCAST_PATH")"; then
    :
else
    enclosure_status=$?
    exit "$enclosure_status"
fi

DOWNLOAD_PREFIX="https://$UPDATE_DOMAIN/"
case "$ENCLOSURE_URL" in
    "$DOWNLOAD_PREFIX"*)
        DMG_NAME="${ENCLOSURE_URL#"$DOWNLOAD_PREFIX"}"
        ;;
    *)
        fail "Appcast enclosure URL must be under $DOWNLOAD_PREFIX"
        ;;
esac
if [[ ! "$DMG_NAME" =~ ^SwitchTab-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$ ]]; then
    fail "Appcast enclosure URL must contain one safe versioned DMG basename"
fi
EXPECTED_DMG_URL="$DOWNLOAD_PREFIX$DMG_NAME"
if [[ "$ENCLOSURE_URL" != "$EXPECTED_DMG_URL" ]]; then
    fail "Appcast enclosure URL is not canonical"
fi

DMG_PATH="$UPDATE_ARTIFACT_DIR/$DMG_NAME"
CHECKSUM_NAME="$DMG_NAME.sha256"
CHECKSUM_PATH="$UPDATE_ARTIFACT_DIR/$CHECKSUM_NAME"
CHECKSUM_URL="$DOWNLOAD_PREFIX$CHECKSUM_NAME"
APPCAST_URL="${DOWNLOAD_PREFIX}appcast.xml"
require_file "versioned DMG" "$DMG_PATH"
require_file "versioned DMG checksum" "$CHECKSUM_PATH"

checksum_line_count=0
checksum_line=''
while IFS= read -r line || [[ -n "$line" ]]; do
    checksum_line_count=$((checksum_line_count + 1))
    checksum_line="$line"
done < "$CHECKSUM_PATH"
if [[ "$checksum_line_count" -ne 1 ]]; then
    fail "DMG checksum manifest must contain exactly one checksum record"
fi
if [[ ! "$checksum_line" =~ ^([A-Fa-f0-9]{64})[[:space:]]+[*]?([^[:space:]]+)[[:space:]]*$ ]]; then
    fail "DMG checksum manifest is malformed"
fi
EXPECTED_DMG_HASH="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
CHECKSUM_FILE_NAME="${BASH_REMATCH[2]}"
if [[ "$CHECKSUM_FILE_NAME" != "$DMG_NAME" ]]; then
    fail "DMG checksum record is not bound to $DMG_NAME"
fi

sha256_file() {
    local path="$1"
    local hash_output result

    if hash_output="$("$SHASUM_BIN" -a 256 "$path")"; then
        :
    else
        result=$?
        echo "SHA-256 computation failed: $path" >&2
        return "$result"
    fi
    if [[ ! "$hash_output" =~ ^([A-Fa-f0-9]{64})[[:space:]] ]]; then
        echo "SHA-256 command returned malformed output: $path" >&2
        return 66
    fi
    printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]'
}

if LOCAL_DMG_HASH="$(sha256_file "$DMG_PATH")"; then
    :
else
    hash_status=$?
    exit "$hash_status"
fi
if [[ "$LOCAL_DMG_HASH" != "$EXPECTED_DMG_HASH" ]]; then
    fail "Local DMG checksum mismatch: $DMG_PATH"
fi

if TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-update.XXXXXX")"; then
    :
else
    temp_status=$?
    echo "Unable to create temporary publish directory" >&2
    exit "$temp_status"
fi

fetch_http() {
    local url="$1"
    local destination="$2"
    local http_code result

    if http_code="$("$CURL_BIN" --silent --show-error --output "$destination" --write-out '%{http_code}' "$url")"; then
        printf '%s' "$http_code"
        return 0
    else
        result=$?
        echo "Public fetch failed: $url" >&2
        return "$result"
    fi
}

upload_object() {
    local key="$1"
    local path="$2"
    local content_type="$3"
    local cache_control="$4"

    run_external "R2 upload for $key" "$WRANGLER_BIN" r2 object put "$R2_BUCKET_NAME/$key" \
        --remote \
        --file "$path" \
        --content-type "$content_type" \
        --cache-control "$cache_control"
}

publish_immutable_dmg() {
    local public_copy="$TEMP_DIR/probe-$DMG_NAME"
    local http_code remote_hash

    http_code="$(fetch_http "$EXPECTED_DMG_URL" "$public_copy")"
    case "$http_code" in
        200)
            remote_hash="$(sha256_file "$public_copy")"
            if [[ "$remote_hash" != "$LOCAL_DMG_HASH" ]]; then
                fail "Public immutable DMG differs from the local artifact"
            fi
            ;;
        404)
            upload_object "$DMG_NAME" "$DMG_PATH" 'application/x-apple-diskimage' "$IMMUTABLE_CACHE"
            ;;
        *)
            fail "Unexpected HTTP status $http_code for $EXPECTED_DMG_URL"
            ;;
    esac
}

publish_immutable_checksum() {
    local public_copy="$TEMP_DIR/probe-$CHECKSUM_NAME"
    local http_code compare_status

    http_code="$(fetch_http "$CHECKSUM_URL" "$public_copy")"
    case "$http_code" in
        200)
            if "$CMP_BIN" -s "$CHECKSUM_PATH" "$public_copy"; then
                :
            else
                compare_status=$?
                if [[ "$compare_status" -ne 1 ]]; then
                    echo "Public checksum comparison failed" >&2
                    return "$compare_status"
                fi
                fail "Public immutable checksum differs from the local artifact"
            fi
            ;;
        404)
            upload_object "$CHECKSUM_NAME" "$CHECKSUM_PATH" 'text/plain' "$IMMUTABLE_CACHE"
            ;;
        *)
            fail "Unexpected HTTP status $http_code for $CHECKSUM_URL"
            ;;
    esac
}

verify_public_immutable_artifacts() {
    local public_dmg="$TEMP_DIR/verify-$DMG_NAME"
    local public_checksum="$TEMP_DIR/verify-$CHECKSUM_NAME"
    local http_code public_hash compare_status

    http_code="$(fetch_http "$EXPECTED_DMG_URL" "$public_dmg")"
    if [[ "$http_code" != 200 ]]; then
        fail "Public DMG verification returned HTTP $http_code"
    fi
    public_hash="$(sha256_file "$public_dmg")"
    if [[ "$public_hash" != "$LOCAL_DMG_HASH" ]]; then
        fail "Public DMG verification checksum mismatch"
    fi

    http_code="$(fetch_http "$CHECKSUM_URL" "$public_checksum")"
    if [[ "$http_code" != 200 ]]; then
        fail "Public checksum verification returned HTTP $http_code"
    fi
    if "$CMP_BIN" -s "$CHECKSUM_PATH" "$public_checksum"; then
        :
    else
        compare_status=$?
        if [[ "$compare_status" -ne 1 ]]; then
            echo "Public checksum verification comparison failed" >&2
            return "$compare_status"
        fi
        fail "Public checksum verification content mismatch"
    fi
}

publish_immutable_dmg
publish_immutable_checksum
verify_public_immutable_artifacts

# The mutable appcast is deliberately the final upload.
upload_object 'appcast.xml' "$APPCAST_PATH" 'application/xml' "$APPCAST_CACHE"

PUBLIC_APPCAST_PATH="$TEMP_DIR/public-appcast.xml"
PUBLIC_APPCAST_STATUS="$(fetch_http "$APPCAST_URL" "$PUBLIC_APPCAST_PATH")"
if [[ "$PUBLIC_APPCAST_STATUS" != 200 ]]; then
    fail "Public appcast verification returned HTTP $PUBLIC_APPCAST_STATUS"
fi
if PUBLIC_ENCLOSURE_URL="$(appcast_enclosure_url "$PUBLIC_APPCAST_PATH")"; then
    :
else
    public_appcast_status=$?
    exit "$public_appcast_status"
fi
if [[ "$PUBLIC_ENCLOSURE_URL" != "$EXPECTED_DMG_URL" ]]; then
    fail "Public appcast enclosure URL mismatch"
fi

printf '%s\n' "$APPCAST_URL"
