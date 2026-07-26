#!/usr/bin/env bash
set -euo pipefail
set +x

export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo 'Usage: scripts/publish-release.sh v<version>'
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 64
fi

TAG="$1"
if [[ ! "$TAG" =~ ^v[0-9]+([.][0-9]+)*$ ]]; then
    echo "Release tag must match v<version>" >&2
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

RELEASE_REPOSITORY='sonim1/switchtab'
GH_REPO="$RELEASE_REPOSITORY"
GH_HOST='github.com'
export GH_REPO GH_HOST
DIRECT_BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
UPDATE_OUTPUT_DIR="${UPDATE_OUTPUT_DIR:-$DIRECT_BUILD_ROOT/updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.royjen.com}"
GIT_BIN="${GIT_BIN:-git}"
GH_BIN="${GH_BIN:-gh}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"
RUBY_BIN="${RUBY_BIN:-/usr/bin/ruby}"
PUBLISH_UPDATE_SCRIPT="${PUBLISH_UPDATE_SCRIPT:-$PROJECT_ROOT/scripts/publish-update.sh}"
APPCAST_PATH="$UPDATE_OUTPUT_DIR/appcast.xml"
MANIFEST_NAME='release-manifest.json'
MANIFEST_PATH="$UPDATE_OUTPUT_DIR/$MANIFEST_NAME"
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

    command_available "$command_path" || fail "$label command is unavailable: $command_path" 66
}

require_file() {
    local label="$1"
    local path="$2"

    [[ -f "$path" ]] || fail "Required $label is missing: $path" 66
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

require_command "git" "$GIT_BIN"
require_command "GitHub CLI" "$GH_BIN"
require_command "shasum" "$SHASUM_BIN"
require_command "xmllint" "$XMLLINT_BIN"
require_command "cmp" "$CMP_BIN"
require_command "Ruby" "$RUBY_BIN"
if [[ ! -x "$PUBLISH_UPDATE_SCRIPT" ]]; then
    fail "Publish-update script is unavailable: $PUBLISH_UPDATE_SCRIPT" 66
fi
require_file "appcast" "$APPCAST_PATH"
require_file "release manifest" "$MANIFEST_PATH"

if [[ ! "$UPDATE_DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ || "$UPDATE_DOMAIN" == *..* ]]; then
    fail "UPDATE_DOMAIN is not a safe domain name" 64
fi

if run_external "Appcast XML validation" "$XMLLINT_BIN" --nonet --noout "$APPCAST_PATH"; then
    :
else
    exit $?
fi

xml_value() {
    local expression="$1"
    local value result

    if value="$("$XMLLINT_BIN" --nonet --xpath "$expression" "$APPCAST_PATH")"; then
        printf '%s' "$value"
    else
        result=$?
        echo "Unable to inspect appcast XML" >&2
        return "$result"
    fi
}

if ENCLOSURE_COUNT="$(xml_value 'count(//*[local-name()="enclosure"])')"; then
    :
else
    exit $?
fi
if [[ "$ENCLOSURE_COUNT" != 1 ]]; then
    fail "Appcast must contain exactly one enclosure"
fi
if ENCLOSURE_URL="$(xml_value 'string((//*[local-name()="enclosure"]/@url)[1])')"; then
    :
else
    exit $?
fi
if SHORT_VERSION_COUNT="$(xml_value 'count(//*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])')"; then
    :
else
    exit $?
fi
if [[ "$SHORT_VERSION_COUNT" != 1 ]]; then
    fail "Appcast must contain exactly one Sparkle short version"
fi
if SPARKLE_SHORT_VERSION_COUNT="$(xml_value 'count(//*[local-name()="enclosure"]/@*[local-name()="shortVersionString" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"])')"; then
    :
else
    exit $?
fi
if [[ "$SPARKLE_SHORT_VERSION_COUNT" != 1 ]]; then
    fail "Appcast must contain exactly one correctly namespaced Sparkle short version"
fi
if SHORT_VERSION="$(xml_value 'string((//*[local-name()="enclosure"]/@*[local-name()="shortVersionString" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"])[1])')"; then
    :
else
    exit $?
fi
if [[ -z "$SHORT_VERSION" || ! "$SHORT_VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    fail "Appcast Sparkle short version is missing or invalid" 64
fi
if [[ "$TAG" != "v$SHORT_VERSION" ]]; then
    fail "Tag $TAG does not match appcast version $SHORT_VERSION" 64
fi

DOWNLOAD_PREFIX="https://$UPDATE_DOMAIN/"
case "$ENCLOSURE_URL" in
    "$DOWNLOAD_PREFIX"*)
        DMG_NAME="${ENCLOSURE_URL#"$DOWNLOAD_PREFIX"}"
        ;;
    *)
        fail "Appcast enclosure URL must be under $DOWNLOAD_PREFIX" 64
        ;;
esac
if [[ ! "$DMG_NAME" =~ ^SwitchTab-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$ ]]; then
    fail "Appcast enclosure must name one safe SwitchTab DMG" 64
fi
if [[ "$ENCLOSURE_URL" != "$DOWNLOAD_PREFIX$DMG_NAME" ]]; then
    fail "Appcast enclosure URL is not canonical" 64
fi

DMG_PATH="$UPDATE_OUTPUT_DIR/$DMG_NAME"
CHECKSUM_NAME="$DMG_NAME.sha256"
CHECKSUM_PATH="$UPDATE_OUTPUT_DIR/$CHECKSUM_NAME"
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
if [[ "${BASH_REMATCH[2]}" != "$DMG_NAME" ]]; then
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
    exit $?
fi
if [[ "$LOCAL_DMG_HASH" != "$EXPECTED_DMG_HASH" ]]; then
    fail "Local DMG checksum mismatch"
fi

if ORIGIN_URL="$("$GIT_BIN" remote get-url origin)"; then
    :
else
    git_status=$?
    echo "Unable to resolve the origin repository" >&2
    exit "$git_status"
fi
case "$ORIGIN_URL" in
    "https://github.com/$RELEASE_REPOSITORY"|\
    "https://github.com/$RELEASE_REPOSITORY.git"|\
    "git@github.com:$RELEASE_REPOSITORY.git"|\
    "ssh://git@github.com/$RELEASE_REPOSITORY"|\
    "ssh://git@github.com/$RELEASE_REPOSITORY.git")
        ;;
    *)
        fail "Release checkout origin is not the official repository: $RELEASE_REPOSITORY" 64
        ;;
esac

if HEAD_COMMIT="$("$GIT_BIN" rev-parse HEAD)"; then
    :
else
    git_status=$?
    echo "Unable to resolve HEAD" >&2
    exit "$git_status"
fi
if [[ ! "$HEAD_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    fail "Git returned an invalid commit for HEAD" 64
fi
if TAG_COMMIT="$("$GIT_BIN" rev-parse "$TAG^{commit}")"; then
    :
else
    git_status=$?
    echo "Unable to resolve release tag: $TAG" >&2
    exit "$git_status"
fi
if [[ "$HEAD_COMMIT" != "$TAG_COMMIT" ]]; then
    fail "Release tag does not point to HEAD" 64
fi
if "$GIT_BIN" merge-base --is-ancestor "$TAG_COMMIT" origin/main; then
    :
else
    git_status=$?
    if [[ "$git_status" -eq 1 ]]; then
        fail "Release tag commit is not on origin/main" 64
    fi
    echo "Unable to validate release tag ancestry" >&2
    exit "$git_status"
fi

set +e
"$RUBY_BIN" -rjson -e '
  class DuplicateJSONKeyError < StandardError; end
  class UniqueJSONObject < Hash
    def []=(key, value)
      raise DuplicateJSONKeyError, key if key?(key)
      super
    end
  end

  path, expected_repository, expected_tag, expected_version, expected_commit, expected_name, expected_sha = ARGV

  begin
    data = JSON.parse(File.read(path), object_class: UniqueJSONObject)
  rescue JSON::ParserError, DuplicateJSONKeyError => error
    warn "Release manifest JSON is malformed: #{error.message}"
    exit 64
  rescue SystemCallError => error
    warn "Unable to read release manifest: #{error.message}"
    exit 66
  end

  exact_keys = lambda do |value, keys|
    value.is_a?(Hash) && value.keys.sort == keys.sort
  end
  package = data.is_a?(Hash) && data["packages"].is_a?(Array) && data["packages"].length == 1 ? data["packages"][0] : nil
  source = package.is_a?(Hash) ? package["source"] : nil

  valid =
    exact_keys.call(data, %w[commit packages repository schemaVersion tag version]) &&
    data["schemaVersion"].is_a?(Integer) && data["schemaVersion"] == 1 &&
    data["repository"] == expected_repository &&
    data["tag"] == expected_tag &&
    data["version"] == expected_version &&
    data["commit"] == expected_commit &&
    exact_keys.call(package, %w[source token type]) &&
    package["type"] == "cask" &&
    package["token"] == "switchtab" &&
    exact_keys.call(source, %w[kind name sha256]) &&
    source["kind"] == "release-asset" &&
    source["name"] == expected_name &&
    source["sha256"] == expected_sha

  exit(valid ? 0 : 64)
' "$MANIFEST_PATH" "$RELEASE_REPOSITORY" "$TAG" "$SHORT_VERSION" "$HEAD_COMMIT" "$DMG_NAME" "$LOCAL_DMG_HASH"
manifest_status=$?
set -e
if [[ "$manifest_status" -ne 0 ]]; then
    if [[ "$manifest_status" -eq 64 ]]; then
        echo "Release manifest is invalid for $TAG" >&2
    else
        echo "Release manifest validation failed" >&2
    fi
    exit "$manifest_status"
fi

if TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-release.XXXXXX")"; then
    :
else
    temp_status=$?
    echo "Unable to create temporary release directory" >&2
    exit "$temp_status"
fi

probe_output=''
set +e
probe_output="$("$GH_BIN" api --include --silent "repos/{owner}/{repo}/releases/tags/$TAG" 2>&1)"
probe_status=$?
set -e
probe_http_status=''
probe_http_count=0
while IFS= read -r probe_line; do
    if [[ "$probe_line" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]{3})([[:space:]]|$) ]]; then
        probe_http_count=$((probe_http_count + 1))
        probe_http_status="${BASH_REMATCH[1]}"
    fi
done <<< "$probe_output"

release_exists=0
release_is_draft=true
if [[ "$probe_status" -eq 0 && "$probe_http_count" -eq 1 && "$probe_http_status" == 200 ]]; then
    release_exists=1
elif [[ "$probe_status" -ne 0 && "$probe_http_count" -eq 1 && "$probe_http_status" == 404 ]]; then
    if run_external "GitHub draft creation" "$GH_BIN" release create "$TAG" \
        --draft --verify-tag --generate-notes --title "SwitchTab $SHORT_VERSION"; then
        :
    else
        exit $?
    fi
else
    echo "GitHub release lookup failed" >&2
    if [[ "$probe_status" -ne 0 ]]; then
        exit "$probe_status"
    fi
    exit 66
fi

if [[ "$release_exists" -eq 1 ]]; then
    if release_is_draft="$("$GH_BIN" release view "$TAG" --json isDraft --jq .isDraft)"; then
        :
    else
        gh_status=$?
        echo "Unable to inspect GitHub release state" >&2
        exit "$gh_status"
    fi
    if [[ "$release_is_draft" != true && "$release_is_draft" != false ]]; then
        fail "GitHub release returned an invalid draft state"
    fi
fi

if ASSET_NAMES="$("$GH_BIN" release view "$TAG" --json assets --jq '.assets[].name')"; then
    :
else
    gh_status=$?
    echo "Unable to inspect GitHub release assets" >&2
    exit "$gh_status"
fi

asset_name_count() {
    local wanted="$1"
    local name count=0

    while IFS= read -r name; do
        [[ "$name" == "$wanted" ]] || continue
        count=$((count + 1))
    done <<< "$ASSET_NAMES"
    printf '%s' "$count"
}

prepare_asset() {
    local asset_path="$1"
    local asset_name="$2"
    local count asset_dir downloaded_path compare_status result

    count="$(asset_name_count "$asset_name")"
    if [[ "$count" -gt 1 ]]; then
        echo "GitHub release asset name is ambiguous: $asset_name" >&2
        return 66
    fi
    if [[ "$count" -eq 0 ]]; then
        run_external "GitHub asset upload for $asset_name" "$GH_BIN" release upload "$TAG" "$asset_path"
        return $?
    fi

    asset_dir="$TEMP_DIR/$asset_name.download"
    if mkdir "$asset_dir"; then
        :
    else
        result=$?
        echo "Unable to create GitHub asset download directory: $asset_name" >&2
        return "$result"
    fi
    if run_external "GitHub asset download for $asset_name" "$GH_BIN" release download "$TAG" \
        --pattern "$asset_name" --dir "$asset_dir"; then
        :
    else
        result=$?
        return "$result"
    fi
    downloaded_path="$asset_dir/$asset_name"
    if [[ ! -f "$downloaded_path" ]]; then
        echo "GitHub asset download is missing: $asset_name" >&2
        return 66
    fi
    if "$CMP_BIN" -s "$asset_path" "$downloaded_path"; then
        return 0
    else
        compare_status=$?
    fi
    if [[ "$compare_status" -eq 1 ]]; then
        echo "GitHub asset checksum conflict: $asset_name" >&2
        return 66
    fi
    echo "GitHub asset byte comparison failed: $asset_name" >&2
    return "$compare_status"
}

DMG_ASSET_COUNT="$(asset_name_count "$DMG_NAME")"
CHECKSUM_ASSET_COUNT="$(asset_name_count "$CHECKSUM_NAME")"
MANIFEST_ASSET_COUNT="$(asset_name_count "$MANIFEST_NAME")"
if [[ "$release_is_draft" == false ]]; then
    if [[ "$DMG_ASSET_COUNT" -ne 1 ]]; then
        fail "GitHub published release is missing one exact required asset: $DMG_NAME"
    fi
    if [[ "$CHECKSUM_ASSET_COUNT" -ne 1 ]]; then
        fail "GitHub published release is missing one exact required asset: $CHECKSUM_NAME"
    fi
    if [[ "$MANIFEST_ASSET_COUNT" -ne 1 ]]; then
        fail "GitHub published release is missing one exact required asset: $MANIFEST_NAME"
    fi
fi

if prepare_asset "$DMG_PATH" "$DMG_NAME"; then
    :
else
    exit $?
fi
if prepare_asset "$CHECKSUM_PATH" "$CHECKSUM_NAME"; then
    :
else
    exit $?
fi
if prepare_asset "$MANIFEST_PATH" "$MANIFEST_NAME"; then
    :
else
    exit $?
fi

if run_external "R2 update publication" "$PUBLISH_UPDATE_SCRIPT"; then
    :
else
    exit $?
fi

if [[ "$release_is_draft" == true ]]; then
    if run_external "GitHub release publication" "$GH_BIN" release edit "$TAG" --draft=false; then
        :
    else
        exit $?
    fi
fi

printf 'Published GitHub Release: %s\n' "$TAG"
