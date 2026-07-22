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
      <enclosure url="$url" sparkle:version="7" sparkle:shortVersionString="$version" />
EOF
    if [[ "$enclosure_count" -eq 2 ]]; then
        cat >> "$UPDATE_DIR/appcast.xml" <<EOF
      <enclosure url="$url" sparkle:version="7" sparkle:shortVersionString="$version" />
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
        FAKE_COMMIT="$FAKE_COMMIT" \
        FAKE_SHASUM_DIGEST="$FAKE_SHASUM_DIGEST" \
        "$SCRIPT_SOURCE" "$GENERATOR_TAG" 2>&1
    )"
    status=$?
    set -e
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
run_generator
[[ "$status" -eq 0 ]] || fail "success returned $status; output: $output"
MANIFEST="$UPDATE_DIR/release-manifest.json"
[[ -f "$MANIFEST" ]] || fail "success did not write release-manifest.json"

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
