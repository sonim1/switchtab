#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_DIR="${UPDATE_OUTPUT_DIR:-$PROJECT_ROOT/.build/direct-distribution/updates}"
GIT_BIN="${GIT_BIN:-git}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
RENAME_BIN="${RENAME_BIN:-ruby}"

fail() {
    local message="$1"
    local code="${2:-64}"

    echo "$message" >&2
    exit "$code"
}

if [[ $# -ne 1 ]]; then
    fail "Usage: scripts/generate-release-manifest.sh v<version>" 64
fi

tag="$1"
tag_pattern='^v[0-9]+([.][0-9]+)*$'
if [[ ! "$tag" =~ $tag_pattern ]]; then
    fail "Tag must match v<version>" 64
fi
version="${tag#v}"

appcast="$UPDATE_DIR/appcast.xml"
manifest="$UPDATE_DIR/release-manifest.json"
if [[ ! -f "$appcast" ]]; then
    fail "Missing appcast: $appcast" 66
fi

xml_value() {
    local expression="$1"
    local value

    if value="$("$XMLLINT_BIN" --xpath "$expression" "$appcast")"; then
        printf '%s' "$value"
    else
        fail "Unable to inspect appcast XML" 64
    fi
}

enclosure_count="$(xml_value 'count(//*[local-name()="enclosure"])')"
if [[ "$enclosure_count" != '1' ]]; then
    fail "Appcast must contain exactly one enclosure" 64
fi

short_version_expression='(//*[local-name()="item"])[1]/*[local-name()="shortVersionString" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"] | (//*[local-name()="enclosure"])[1]/@*[local-name()="shortVersionString" and namespace-uri()="http://www.andymatuschak.org/xml-namespaces/sparkle"]'
short_version_count="$(xml_value "count($short_version_expression)")"
if [[ "$short_version_count" != '1' ]]; then
    fail "Appcast must contain one Sparkle shortVersionString" 64
fi

appcast_version="$(xml_value "string(($short_version_expression)[1])")"
if [[ "$tag" != "v$appcast_version" ]]; then
    fail "Tag/appcast version mismatch" 64
fi

url="$(xml_value 'string((//*[local-name()="enclosure"])[1]/@url)')"
safe_url_pattern='^https://[^/?#]+/([^/?#]+)$'
if [[ ! "$url" =~ $safe_url_pattern ]]; then
    fail "Invalid SwitchTab DMG URL" 64
fi
asset="${BASH_REMATCH[1]}"

asset_prefix="SwitchTab-${version}-"
if [[ "$asset" != "$asset_prefix"* ]]; then
    fail "Invalid SwitchTab DMG name" 64
fi
build_and_extension="${asset#"$asset_prefix"}"
build_pattern='^[0-9]+([.][0-9]+){0,2}[.]dmg$'
if [[ ! "$build_and_extension" =~ $build_pattern ]]; then
    fail "Invalid SwitchTab DMG name" 64
fi

dmg="$UPDATE_DIR/$asset"
checksum_file="$dmg.sha256"
if [[ ! -f "$dmg" ]]; then
    fail "Missing DMG: $dmg" 66
fi
if [[ ! -f "$checksum_file" ]]; then
    fail "Missing DMG checksum: $checksum_file" 66
fi

checksum_line=''
checksum_line_count=0
while IFS= read -r line || [[ -n "$line" ]]; do
    checksum_line_count=$((checksum_line_count + 1))
    checksum_line="$line"
done < "$checksum_file"

checksum_pattern='^([0-9a-f]{64})[[:space:]]+(.+)$'
if [[ "$checksum_line_count" -ne 1 || ! "$checksum_line" =~ $checksum_pattern ]]; then
    fail "DMG checksum mismatch" 1
fi
recorded="${BASH_REMATCH[1]}"
recorded_name="${BASH_REMATCH[2]}"
if [[ "$recorded_name" != "$asset" ]]; then
    fail "DMG checksum mismatch" 1
fi

if computed_output="$("$SHASUM_BIN" -a 256 "$dmg")"; then
    :
else
    checksum_status=$?
    echo "DMG checksum computation failed" >&2
    exit "$checksum_status"
fi

computed_pattern='^([0-9a-f]{64})[[:space:]]+.+$'
if [[ ! "$computed_output" =~ $computed_pattern ]]; then
    fail "DMG checksum mismatch" 1
fi
computed="${BASH_REMATCH[1]}"
if [[ "$computed" != "$recorded" ]]; then
    fail "DMG checksum mismatch" 1
fi

if commit="$("$GIT_BIN" -C "$PROJECT_ROOT" rev-parse HEAD)"; then
    :
else
    fail "Invalid release commit" 64
fi
commit_pattern='^[0-9a-f]{40}$'
if [[ ! "$commit" =~ $commit_pattern ]]; then
    fail "Invalid release commit" 64
fi

if [[ -L "$manifest" || ( -e "$manifest" && ! -f "$manifest" ) ]]; then
    fail "Release manifest destination is not a regular file: $manifest" 66
fi

temp_manifest=''
cleanup() {
    if [[ -n "$temp_manifest" ]]; then
        rm -f "$temp_manifest"
    fi
}
trap cleanup EXIT

if temp_manifest="$(mktemp "$UPDATE_DIR/.release-manifest.XXXXXX")"; then
    :
else
    fail "Unable to create temporary release manifest" 66
fi

ruby -rjson -e '
  document = {
    schemaVersion: 1,
    repository: "sonim1/switchtab",
    tag: ARGV.fetch(1),
    version: ARGV.fetch(2),
    commit: ARGV.fetch(3),
    packages: [{
      type: "cask",
      token: "switchtab",
      source: {
        kind: "release-asset",
        name: ARGV.fetch(4),
        sha256: ARGV.fetch(5)
      }
    }]
  }
  File.write(ARGV.fetch(0), JSON.pretty_generate(document) + "\n")
' "$temp_manifest" "$tag" "$version" "$commit" "$asset" "$computed"

if "$RENAME_BIN" -e '
  destination = ARGV.fetch(1)
  begin
    abort "Release manifest destination is not a regular file" unless File.lstat(destination).file?
  rescue Errno::ENOENT
  end
  File.rename(ARGV.fetch(0), destination)
' "$temp_manifest" "$manifest"; then
    :
else
    rename_status=$?
    echo "Unable to finalize release manifest" >&2
    exit "$rename_status"
fi
temp_manifest=''

echo "$manifest"
