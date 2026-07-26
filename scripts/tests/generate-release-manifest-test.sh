#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/generate-release-manifest.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-release-manifest.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
UPDATE_DIR="$FIXTURE_ROOT/.build/direct-distribution/updates"
BIN_DIR="$TEMP_ROOT/bin"
DMG_NAME='SwitchTab-1.2.0-7.dmg'
VALID_COMMIT='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
EXPECTED_SHA=''
GENERATOR_TAG='v1.2.0'
FAKE_COMMIT="$VALID_COMMIT"
FAKE_SHASUM_DIGEST=''
FAKE_RENAME_EXIT=''
FAKE_SWAP_MANIFEST_DESTINATION=''

mkdir -p "$FIXTURE_ROOT/scripts" "$BIN_DIR"

cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '-C' ]]; then
    shift 2
fi
[[ "$*" == 'rev-parse HEAD' ]] || exit 92
printf '%s\n' "$FAKE_COMMIT"
EOF

cat > "$BIN_DIR/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_SHASUM_DIGEST:-}" ]]; then
    printf '%s  %s\n' "$FAKE_SHASUM_DIGEST" "${!#}"
else
    /usr/bin/shasum "$@"
fi
EOF

cat > "$BIN_DIR/xmllint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/usr/bin/xmllint "$@"
EOF

cat > "$BIN_DIR/ruby" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/usr/bin/ruby "$@"
case "${FAKE_SWAP_MANIFEST_DESTINATION:-}" in
    directory)
        mkdir "$FAKE_MANIFEST_DESTINATION"
        printf 'preserve me\n' > "$FAKE_MANIFEST_DESTINATION/sentinel"
        ;;
    symlink)
        mkdir "$FAKE_MANIFEST_SYMLINK_TARGET"
        printf 'preserve me\n' > "$FAKE_MANIFEST_SYMLINK_TARGET/sentinel"
        ln -s "$FAKE_MANIFEST_SYMLINK_TARGET" "$FAKE_MANIFEST_DESTINATION"
        ;;
esac
EOF

cat > "$BIN_DIR/rename" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_RENAME_EXIT:-}" ]]; then
    exit "$FAKE_RENAME_EXIT"
fi
exec /usr/bin/ruby "$@"
EOF

chmod +x "$BIN_DIR"/*

write_appcast() {
    local version="${1:-1.2.0}"
    local url="${2:-https://updates.switchtab.app/$DMG_NAME}"
    local enclosure_count="${3:-1}"

    cat > "$UPDATE_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>7</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <enclosure url="$url" />
EOF
    if [[ "$enclosure_count" -eq 2 ]]; then
        cat >> "$UPDATE_DIR/appcast.xml" <<EOF
      <enclosure url="$url" />
EOF
    fi
    cat >> "$UPDATE_DIR/appcast.xml" <<'EOF'
    </item>
  </channel>
</rss>
EOF
}

prepare_fixture() {
    local scenario="$1"

    rm -rf "$UPDATE_DIR"
    mkdir -p "$UPDATE_DIR"
    printf 'fixture dmg\n' > "$UPDATE_DIR/$DMG_NAME"
    EXPECTED_SHA="$(/usr/bin/shasum -a 256 "$UPDATE_DIR/$DMG_NAME")"
    EXPECTED_SHA="${EXPECTED_SHA%% *}"
    printf '%s  %s\n' "$EXPECTED_SHA" "$DMG_NAME" > "$UPDATE_DIR/$DMG_NAME.sha256"
    write_appcast

    GENERATOR_TAG='v1.2.0'
    FAKE_COMMIT="$VALID_COMMIT"
    FAKE_SHASUM_DIGEST=''
    FAKE_RENAME_EXIT=''
    FAKE_SWAP_MANIFEST_DESTINATION=''

    case "$scenario" in
        success) ;;
        missing-appcast)
            rm "$UPDATE_DIR/appcast.xml"
            ;;
        malformed-tag)
            GENERATOR_TAG='1.2.0'
            ;;
        tag-version-mismatch)
            write_appcast '1.2.1'
            ;;
        wrong-short-version-namespace)
            sed -i '' \
                's#http://www.andymatuschak.org/xml-namespaces/sparkle#https://example.invalid/not-sparkle#' \
                "$UPDATE_DIR/appcast.xml"
            ;;
        invalid-commit)
            FAKE_COMMIT='NOT-A-RELEASE-COMMIT'
            ;;
        multiple-enclosures)
            write_appcast '1.2.0' "https://updates.switchtab.app/$DMG_NAME" 2
            ;;
        foreign-asset-name)
            write_appcast '1.2.0' 'https://updates.switchtab.app/Other-1.2.0-7.dmg'
            ;;
        path-asset-name)
            write_appcast '1.2.0' "https://updates.switchtab.app/subdir/$DMG_NAME"
            ;;
        missing-checksum)
            rm "$UPDATE_DIR/$DMG_NAME.sha256"
            ;;
        recorded-checksum-mismatch)
            printf '%064d  %s\n' 0 "$DMG_NAME" > "$UPDATE_DIR/$DMG_NAME.sha256"
            ;;
        computed-checksum-mismatch)
            FAKE_SHASUM_DIGEST='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            ;;
        *)
            fail "unknown fixture scenario: $scenario"
            ;;
    esac
}

run_generator() {
    set +e
    output="$(
        UPDATE_OUTPUT_DIR="$UPDATE_DIR" \
        GIT_BIN="$BIN_DIR/git" \
        SHASUM_BIN="$BIN_DIR/shasum" \
        XMLLINT_BIN="$BIN_DIR/xmllint" \
        RENAME_BIN="$BIN_DIR/rename" \
        PATH="$BIN_DIR:/usr/bin:/bin" \
        FAKE_COMMIT="$FAKE_COMMIT" \
        FAKE_SHASUM_DIGEST="$FAKE_SHASUM_DIGEST" \
        FAKE_RENAME_EXIT="$FAKE_RENAME_EXIT" \
        FAKE_SWAP_MANIFEST_DESTINATION="$FAKE_SWAP_MANIFEST_DESTINATION" \
        FAKE_MANIFEST_DESTINATION="$UPDATE_DIR/release-manifest.json" \
        FAKE_MANIFEST_SYMLINK_TARGET="$TEMP_ROOT/finalization-symlink-target" \
        "$SCRIPT_SOURCE" "$GENERATOR_TAG" 2>&1
    )"
    status=$?
    set -e
}

assert_no_manifest_temps() {
    if [[ -n "$(find "$UPDATE_DIR" -maxdepth 1 -name '.release-manifest.*' -print -quit)" ]]; then
        fail "generator left a temporary manifest in the update directory"
    fi
}

assert_only_sentinel() {
    local directory="$1"

    if [[ -n "$(find "$directory" -mindepth 1 ! -name sentinel -print -quit)" ]]; then
        fail "generator moved a temporary or generated file inside $directory"
    fi
    [[ "$(<"$directory/sentinel")" == 'preserve me' ]] \
        || fail "generator changed the destination sentinel in $directory"
}

assert_no_success_path() {
    local success_path="$1"

    if printf '%s\n' "$output" | grep -Fxq "$success_path"; then
        fail "generator printed its success path after finalization failed"
    fi
}

failure_cases=(
    'missing-appcast:66'
    'malformed-tag:64'
    'tag-version-mismatch:64'
    'wrong-short-version-namespace:64'
    'invalid-commit:64'
    'multiple-enclosures:64'
    'foreign-asset-name:64'
    'path-asset-name:64'
    'missing-checksum:66'
    'recorded-checksum-mismatch:1'
    'computed-checksum-mismatch:1'
)

for entry in "${failure_cases[@]}"; do
    scenario="${entry%%:*}"
    expected_status="${entry##*:}"
    prepare_fixture "$scenario"
    run_generator
    [[ "$status" -eq "$expected_status" ]] \
        || fail "$scenario returned $status, expected $expected_status; output: $output"
    [[ ! -e "$UPDATE_DIR/release-manifest.json" ]] \
        || fail "$scenario wrote a manifest"
done

prepare_fixture success
MANIFEST="$UPDATE_DIR/release-manifest.json"
mkdir "$MANIFEST"
printf 'preserve me\n' > "$MANIFEST/sentinel"
run_generator
[[ "$status" -ne 0 ]] \
    || fail "manifest directory destination returned success; output: $output"
[[ -d "$MANIFEST" && ! -L "$MANIFEST" ]] \
    || fail "manifest directory destination was changed"
assert_only_sentinel "$MANIFEST"
assert_no_manifest_temps

prepare_fixture success
SYMLINK_TARGET="$TEMP_ROOT/manifest-symlink-target"
rm -rf "$SYMLINK_TARGET"
mkdir "$SYMLINK_TARGET"
printf 'preserve me\n' > "$SYMLINK_TARGET/sentinel"
ln -s "$SYMLINK_TARGET" "$MANIFEST"
run_generator
[[ "$status" -ne 0 ]] \
    || fail "manifest symlink-to-directory destination returned success; output: $output"
[[ -L "$MANIFEST" && "$(readlink "$MANIFEST")" == "$SYMLINK_TARGET" ]] \
    || fail "manifest symlink destination was changed"
assert_only_sentinel "$SYMLINK_TARGET"
assert_no_manifest_temps

prepare_fixture success
FAKE_SWAP_MANIFEST_DESTINATION='directory'
run_generator
[[ "$status" -ne 0 ]] \
    || fail "destination substitution during finalization returned success; output: $output"
[[ -d "$MANIFEST" && ! -L "$MANIFEST" ]] \
    || fail "substituted manifest directory was changed"
assert_only_sentinel "$MANIFEST"
assert_no_manifest_temps
assert_no_success_path "$MANIFEST"

prepare_fixture success
FINALIZATION_SYMLINK_TARGET="$TEMP_ROOT/finalization-symlink-target"
rm -rf "$FINALIZATION_SYMLINK_TARGET"
FAKE_SWAP_MANIFEST_DESTINATION='symlink'
run_generator
[[ "$status" -ne 0 ]] \
    || fail "symlink substitution during finalization returned success; output: $output"
[[ -L "$MANIFEST" && "$(readlink "$MANIFEST")" == "$FINALIZATION_SYMLINK_TARGET" ]] \
    || fail "substituted manifest symlink was changed"
assert_only_sentinel "$FINALIZATION_SYMLINK_TARGET"
assert_no_manifest_temps
assert_no_success_path "$MANIFEST"

prepare_fixture success
printf 'old manifest\n' > "$MANIFEST"
FAKE_RENAME_EXIT='37'
run_generator
[[ "$status" -eq 37 ]] \
    || fail "rename failure returned $status, expected 37; output: $output"
[[ -f "$MANIFEST" && "$(<"$MANIFEST")" == 'old manifest' ]] \
    || fail "rename failure changed the existing manifest"
assert_no_manifest_temps
assert_no_success_path "$MANIFEST"

prepare_fixture success
printf 'old manifest\n' > "$MANIFEST"
run_generator
[[ "$status" -eq 0 ]] || fail "success returned $status; output: $output"
[[ -f "$MANIFEST" ]] || fail "success did not write release-manifest.json"
assert_no_manifest_temps

EXPECTED_SHA="$EXPECTED_SHA" VALID_COMMIT="$VALID_COMMIT" ruby -rjson -e '
  actual = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "schemaVersion" => 1,
    "repository" => "sonim1/switchtab",
    "tag" => "v1.2.0",
    "version" => "1.2.0",
    "commit" => ENV.fetch("VALID_COMMIT"),
    "packages" => [{
      "type" => "cask",
      "token" => "switchtab",
      "source" => {
        "kind" => "release-asset",
        "name" => "SwitchTab-1.2.0-7.dmg",
        "sha256" => ENV.fetch("EXPECTED_SHA")
      }
    }]
  }
  abort "manifest mismatch:\n#{JSON.pretty_generate(actual)}" unless actual == expected
  abort "manifest must end with a newline" unless File.binread(ARGV.fetch(0)).end_with?("\n")
' "$MANIFEST"

bash -n "$SCRIPT_SOURCE"
bash -n "$PROJECT_ROOT/scripts/tests/generate-release-manifest-test.sh"

echo "generate-release-manifest contract tests passed"
