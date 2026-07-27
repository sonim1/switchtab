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

R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.royjen.com}"
UPDATE_ARTIFACT_DIR="${UPDATE_ARTIFACT_DIR:-$PROJECT_ROOT/.build/direct-distribution/updates}"
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
R2_ACCESS_KEY_VALUE="${R2_ACCESS_KEY_ID:-}"
R2_SECRET_ACCESS_KEY_VALUE="${R2_SECRET_ACCESS_KEY:-}"
unset R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY

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
if [[ -z "$CLOUDFLARE_ACCOUNT_ID" || ! "$CLOUDFLARE_ACCOUNT_ID" =~ ^[A-Za-z0-9]+$ ]]; then
    fail "CLOUDFLARE_ACCOUNT_ID is required and must be alphanumeric" 64
fi
if [[ -z "$R2_ACCESS_KEY_VALUE" || ! "$R2_ACCESS_KEY_VALUE" =~ ^[A-Za-z0-9]+$ ]]; then
    fail "R2_ACCESS_KEY_ID is required and must be alphanumeric" 64
fi
if [[ -z "$R2_SECRET_ACCESS_KEY_VALUE" || "$R2_SECRET_ACCESS_KEY_VALUE" =~ [[:cntrl:]] ]]; then
    fail "R2_SECRET_ACCESS_KEY is required and must not contain control characters" 64
fi

curl_config_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

R2_CURL_USER_CONFIG="user = \"$(curl_config_escape "$R2_ACCESS_KEY_VALUE"):$(curl_config_escape "$R2_SECRET_ACCESS_KEY_VALUE")\""
R2_ACCESS_KEY_VALUE=''
R2_SECRET_ACCESS_KEY_VALUE=''
R2_ORIGIN_PREFIX="https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com/$R2_BUCKET_NAME/"

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

appcast_build_version() {
    local path="$1"
    local version_expression count namespaced_count version result

    version_expression='(//*[local-name()="item"])[1]/*[local-name()="version" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"] | (//*[local-name()="enclosure"])[1]/@*[local-name()="version" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"]'

    if validate_xml "$path"; then
        :
    else
        result=$?
        return "$result"
    fi
    if count="$(xml_value "$path" 'count((//*[local-name()="item"])[1]/*[local-name()="version"] | (//*[local-name()="enclosure"])[1]/@*[local-name()="version"])')"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ "$count" != 1 ]]; then
        fail "Appcast must contain exactly one sparkle:version"
    fi
    if namespaced_count="$(xml_value "$path" "count($version_expression)")"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ "$namespaced_count" != 1 ]]; then
        fail "Appcast must contain exactly one correctly namespaced sparkle:version"
    fi
    if version="$(xml_value "$path" "string(($version_expression)[1])")"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ ! "$version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
        fail "Appcast sparkle:version must contain one to three numeric components"
    fi
    printf '%s' "$version"
}

compare_appcast_versions() {
    local left="$1"
    local right="$2"
    local left_parts right_parts left_part right_part index

    IFS=. read -r -a left_parts <<< "$left"
    IFS=. read -r -a right_parts <<< "$right"
    for index in 0 1 2; do
        left_part="${left_parts[$index]:-0}"
        right_part="${right_parts[$index]:-0}"
        while [[ "${#left_part}" -gt 1 && "$left_part" == 0* ]]; do
            left_part="${left_part#0}"
        done
        while [[ "${#right_part}" -gt 1 && "$right_part" == 0* ]]; do
            right_part="${right_part#0}"
        done
        if [[ "${#left_part}" -lt "${#right_part}" ]]; then
            printf '%s' -1
            return 0
        fi
        if [[ "${#left_part}" -gt "${#right_part}" ]]; then
            printf '%s' 1
            return 0
        fi
        if [[ "$left_part" < "$right_part" ]]; then
            printf '%s' -1
            return 0
        fi
        if [[ "$left_part" > "$right_part" ]]; then
            printf '%s' 1
            return 0
        fi
    done
    printf '%s' 0
}

if ENCLOSURE_URL="$(appcast_enclosure_url "$APPCAST_PATH")"; then
    :
else
    enclosure_status=$?
    exit "$enclosure_status"
fi
if LOCAL_APPCAST_VERSION="$(appcast_build_version "$APPCAST_PATH")"; then
    :
else
    appcast_version_status=$?
    exit "$appcast_version_status"
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
PUBLIC_CACHE_TOKEN="${TEMP_DIR##*.}"
if [[ ! "$PUBLIC_CACHE_TOKEN" =~ ^[A-Za-z0-9]+$ ]]; then
    fail "Unable to create a safe public cache-bypass token"
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

signed_origin_http() {
    local method="$1"
    local url="$2"
    local destination="$3"
    local upload_path="${4:-}"
    local content_type="${5:-}"
    local cache_control="${6:-}"
    local condition_header="${7:-}"
    local response_headers="${8:-}"
    local curl_arguments
    local http_code result

    if [[ "$url" != "$R2_ORIGIN_PREFIX"* ]]; then
        echo "Refusing a signed R2 request outside the configured origin" >&2
        return 64
    fi

    if [[ "$method" == PUT ]]; then
        if [[ "$condition_header" != 'If-None-Match: *' \
            && ! "$condition_header" =~ ^If-Match:[[:space:]]\"[A-Za-z0-9._:-]+\"$ ]]; then
            echo "Refusing an unsafe R2 conditional header" >&2
            return 64
        fi
        if http_code="$(
            printf '%s\n' "$R2_CURL_USER_CONFIG" | "$CURL_BIN" \
                --config - \
                --silent \
                --show-error \
                --aws-sigv4 'aws:amz:auto:s3' \
                --request PUT \
                --header "$condition_header" \
                --header "Content-Type: $content_type" \
                --header "Cache-Control: $cache_control" \
                --upload-file "$upload_path" \
                --output "$destination" \
                --write-out '%{http_code}' \
                "$url"
        )"; then
            printf '%s' "$http_code"
            return 0
        else
            result=$?
            echo "Signed R2 conditional PUT failed" >&2
            return "$result"
        fi
    fi

    if [[ "$method" == GET ]]; then
        curl_arguments=(
            --config -
            --silent
            --show-error
            --aws-sigv4 'aws:amz:auto:s3'
            --request GET
            --output "$destination"
            --write-out '%{http_code}'
        )
        if [[ -n "$response_headers" ]]; then
            curl_arguments+=(--dump-header "$response_headers")
        fi
        if http_code="$(printf '%s\n' "$R2_CURL_USER_CONFIG" | "$CURL_BIN" "${curl_arguments[@]}" "$url")"; then
            printf '%s' "$http_code"
            return 0
        else
            result=$?
            echo "Signed R2 origin GET failed" >&2
            return "$result"
        fi
    fi

    echo "Unsupported signed R2 method" >&2
    return 64
}

conditional_put_and_verify_origin() {
    local key="$1"
    local path="$2"
    local content_type="$3"
    local cache_control="$4"
    local artifact_kind="$5"
    local origin_url="$R2_ORIGIN_PREFIX$key"
    local response_path="$TEMP_DIR/origin-put-response-$key"
    local origin_copy="$TEMP_DIR/origin-copy-$key"
    local http_code origin_status origin_hash compare_status result

    if [[ ! "$key" =~ ^SwitchTab-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg([.]sha256)?$ ]]; then
        echo "Refusing an unsafe immutable R2 object key" >&2
        return 64
    fi

    if http_code="$(signed_origin_http PUT "$origin_url" "$response_path" "$path" "$content_type" "$cache_control" 'If-None-Match: *')"; then
        :
    else
        result=$?
        return "$result"
    fi
    case "$http_code" in
        200|201|204|412)
            ;;
        *)
            echo "Conditional R2 PUT returned HTTP $http_code for $key" >&2
            return 66
            ;;
    esac

    if origin_status="$(signed_origin_http GET "$origin_url" "$origin_copy")"; then
        :
    else
        result=$?
        return "$result"
    fi
    if [[ "$origin_status" != 200 ]]; then
        echo "Authoritative R2 origin GET returned HTTP $origin_status for $key" >&2
        return 66
    fi

    if [[ "$artifact_kind" == dmg ]]; then
        if origin_hash="$(sha256_file "$origin_copy")"; then
            :
        else
            result=$?
            return "$result"
        fi
        if [[ "$origin_hash" != "$LOCAL_DMG_HASH" ]]; then
            echo "Authoritative R2 origin DMG differs from the local artifact" >&2
            return 66
        fi
        return 0
    fi

    if "$CMP_BIN" -s "$path" "$origin_copy"; then
        return 0
    else
        compare_status=$?
        if [[ "$compare_status" -ne 1 ]]; then
            echo "Authoritative R2 origin checksum comparison failed" >&2
            return "$compare_status"
        fi
        echo "Authoritative R2 origin checksum differs from the local artifact" >&2
        return 66
    fi
}

origin_etag() {
    local headers_path="$1"
    local header_line etag='' etag_count=0

    while IFS= read -r header_line || [[ -n "$header_line" ]]; do
        header_line="${header_line%$'\r'}"
        case "$header_line" in
            [Ee][Tt][Aa][Gg]:*)
                etag="${header_line#*:}"
                while [[ "$etag" == ' '* || "$etag" == $'\t'* ]]; do
                    etag="${etag#?}"
                done
                etag_count=$((etag_count + 1))
                ;;
        esac
    done < "$headers_path"
    if [[ "$etag_count" -ne 1 || ! "$etag" =~ ^\"[A-Za-z0-9._:-]+\"$ ]]; then
        echo "Authoritative R2 appcast response has an invalid ETag" >&2
        return 66
    fi
    printf '%s' "$etag"
}

publish_appcast() {
    local origin_url="${R2_ORIGIN_PREFIX}appcast.xml"
    local attempt=1
    local remote_path headers_path put_response verify_path
    local origin_status remote_version comparison etag condition_header put_status verify_status result compare_status

    while [[ "$attempt" -le 4 ]]; do
        remote_path="$TEMP_DIR/origin-appcast-$attempt.xml"
        headers_path="$TEMP_DIR/origin-appcast-$attempt.headers"
        put_response="$TEMP_DIR/origin-appcast-$attempt.put"
        if origin_status="$(signed_origin_http GET "$origin_url" "$remote_path" '' '' '' '' "$headers_path")"; then
            :
        else
            result=$?
            return "$result"
        fi

        case "$origin_status" in
            404)
                condition_header='If-None-Match: *'
                ;;
            200)
                if remote_version="$(appcast_build_version "$remote_path")"; then
                    :
                else
                    result=$?
                    return "$result"
                fi
                comparison="$(compare_appcast_versions "$remote_version" "$LOCAL_APPCAST_VERSION")"
                if [[ "$comparison" -gt 0 ]]; then
                    fail "Authoritative R2 origin already contains a newer appcast ($remote_version > $LOCAL_APPCAST_VERSION)"
                fi
                if [[ "$comparison" -eq 0 ]]; then
                    if "$CMP_BIN" -s "$APPCAST_PATH" "$remote_path"; then
                        return 0
                    else
                        compare_status=$?
                        if [[ "$compare_status" -ne 1 ]]; then
                            echo "Authoritative R2 appcast comparison failed" >&2
                            return "$compare_status"
                        fi
                        fail "Authoritative R2 origin contains different appcast bytes for the same version"
                    fi
                fi
                if etag="$(origin_etag "$headers_path")"; then
                    :
                else
                    result=$?
                    return "$result"
                fi
                condition_header="If-Match: $etag"
                ;;
            *)
                fail "Authoritative R2 appcast GET returned HTTP $origin_status"
                ;;
        esac

        if put_status="$(signed_origin_http PUT "$origin_url" "$put_response" "$APPCAST_PATH" \
            'application/xml' "$APPCAST_CACHE" "$condition_header")"; then
            :
        else
            result=$?
            return "$result"
        fi
        case "$put_status" in
            200|201|204)
                verify_path="$TEMP_DIR/origin-appcast-verified.xml"
                if verify_status="$(signed_origin_http GET "$origin_url" "$verify_path")"; then
                    :
                else
                    result=$?
                    return "$result"
                fi
                if [[ "$verify_status" != 200 ]]; then
                    fail "Authoritative R2 appcast verification returned HTTP $verify_status"
                fi
                if "$CMP_BIN" -s "$APPCAST_PATH" "$verify_path"; then
                    return 0
                else
                    compare_status=$?
                    if [[ "$compare_status" -ne 1 ]]; then
                        echo "Authoritative R2 appcast verification comparison failed" >&2
                        return "$compare_status"
                    fi
                    fail "Authoritative R2 appcast verification content mismatch"
                fi
                ;;
            412)
                attempt=$((attempt + 1))
                ;;
            *)
                fail "Conditional R2 appcast PUT returned HTTP $put_status"
                ;;
        esac
    done
    fail "Appcast changed repeatedly during conditional publication"
}

publish_immutable_dmg() {
    local public_copy="$TEMP_DIR/probe-$DMG_NAME"
    local http_code remote_hash

    http_code="$(fetch_http "$EXPECTED_DMG_URL?switchtab-probe=$PUBLIC_CACHE_TOKEN" "$public_copy")"
    case "$http_code" in
        200)
            remote_hash="$(sha256_file "$public_copy")"
            if [[ "$remote_hash" != "$LOCAL_DMG_HASH" ]]; then
                fail "Public immutable DMG differs from the local artifact"
            fi
            ;;
        404)
            ;;
        *)
            fail "Unexpected HTTP status $http_code for $EXPECTED_DMG_URL"
            ;;
    esac

    conditional_put_and_verify_origin "$DMG_NAME" "$DMG_PATH" \
        'application/x-apple-diskimage' "$IMMUTABLE_CACHE" dmg
}

publish_immutable_checksum() {
    local public_copy="$TEMP_DIR/probe-$CHECKSUM_NAME"
    local http_code compare_status

    http_code="$(fetch_http "$CHECKSUM_URL?switchtab-probe=$PUBLIC_CACHE_TOKEN" "$public_copy")"
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
            ;;
        *)
            fail "Unexpected HTTP status $http_code for $CHECKSUM_URL"
            ;;
    esac

    conditional_put_and_verify_origin "$CHECKSUM_NAME" "$CHECKSUM_PATH" \
        'text/plain' "$IMMUTABLE_CACHE" checksum
}

verify_public_immutable_artifacts() {
    local public_dmg="$TEMP_DIR/verify-$DMG_NAME"
    local public_checksum="$TEMP_DIR/verify-$CHECKSUM_NAME"
    local http_code public_hash compare_status

    http_code="$(fetch_http "$EXPECTED_DMG_URL?switchtab-verify=$PUBLIC_CACHE_TOKEN" "$public_dmg")"
    if [[ "$http_code" != 200 ]]; then
        fail "Public DMG verification returned HTTP $http_code"
    fi
    public_hash="$(sha256_file "$public_dmg")"
    if [[ "$public_hash" != "$LOCAL_DMG_HASH" ]]; then
        fail "Public DMG verification checksum mismatch"
    fi

    http_code="$(fetch_http "$CHECKSUM_URL?switchtab-verify=$PUBLIC_CACHE_TOKEN" "$public_checksum")"
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

# The mutable appcast is deliberately the final upload and uses an ETag guard.
publish_appcast

PUBLIC_APPCAST_PATH="$TEMP_DIR/public-appcast.xml"
PUBLIC_APPCAST_STATUS="$(fetch_http "$APPCAST_URL?switchtab-verify=$PUBLIC_CACHE_TOKEN" "$PUBLIC_APPCAST_PATH")"
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
