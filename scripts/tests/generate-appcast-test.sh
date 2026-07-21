#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/generate-appcast.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_status() {
    local expected="$1"

    if [[ "$status" -ne "$expected" ]]; then
        fail "expected status $expected, got $status; output: $output"
    fi
}

assert_status_nonzero() {
    if [[ "$status" -eq 0 ]]; then
        fail "expected a failure status; output: $output"
    fi
}

assert_output_contains() {
    local expected="$1"

    if [[ "$output" != *"$expected"* ]]; then
        fail "expected output to contain '$expected'; output: $output"
    fi
}

assert_no_outputs() {
    if [[ -e "$UPDATE_DIR" ]] && [[ -n "$(find "$UPDATE_DIR" -maxdepth 1 -type f -print -quit)" ]]; then
        fail "unexpected update output files exist"
    fi
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "scripts/generate-appcast.sh is missing"
[[ -x "$SCRIPT_SOURCE" ]] || fail "scripts/generate-appcast.sh is not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-generate-appcast.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
BUILD_ROOT="$FIXTURE_ROOT/.build/direct-distribution"
RELEASE_DIR="$BUILD_ROOT/release"
UPDATE_DIR="$BUILD_ROOT/updates"
APP_PATH="$BUILD_ROOT/DerivedData/Build/Products/Release/SwitchTab.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
BIN_DIR="$TEMP_ROOT/bin"
TOOL_LOG="$TEMP_ROOT/tool.log"
PRIVATE_KEY='private-key-secret'
PUBLIC_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
MISMATCH_KEY='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'

mkdir -p "$FIXTURE_ROOT/scripts" "$RELEASE_DIR" "$(dirname -- "$INFO_PLIST")" "$BIN_DIR"
cp "$SCRIPT_SOURCE" "$FIXTURE_ROOT/scripts/generate-appcast.sh"
chmod +x "$FIXTURE_ROOT/scripts/generate-appcast.sh"

printf 'fixture dmg\n' > "$RELEASE_DIR/SwitchTab.dmg"
/usr/bin/shasum -a 256 "$RELEASE_DIR/SwitchTab.dmg" > "$RELEASE_DIR/SwitchTab.dmg.sha256"
cat > "$INFO_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundleVersion</key><string>7</string>
    <key>SUPublicEDKey</key><string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</string>
</dict></plist>
EOF

cat > "$BIN_DIR/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign %s\n' "$*" >> "$TOOL_LOG"
exit "${FAKE_CODESIGN_EXIT:-0}"
EOF

cat > "$BIN_DIR/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >> "$TOOL_LOG"
exit "${FAKE_XCRUN_EXIT:-0}"
EOF

cat > "$BIN_DIR/spctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl %s\n' "$*" >> "$TOOL_LOG"
exit "${FAKE_SPCTL_EXIT:-0}"
EOF

cat > "$BIN_DIR/plutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
key="${2:-}"
case "$key" in
    CFBundleShortVersionString) printf '%s' "${PLIST_MARKETING_VERSION:-1.2}" ;;
    CFBundleVersion) printf '%s' "${PLIST_BUILD_NUMBER:-7}" ;;
    SUPublicEDKey) printf '%s' "${PLIST_PUBLIC_KEY:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA}" ;;
    *) echo "unknown key: $key" >&2; exit 2 ;;
esac
EOF

cat > "$BIN_DIR/generate_appcast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=''
prefix=''
account=''
ed_key_file=''
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    case "$argument" in
        -o)
            ((index += 1))
            output="${!index}"
            ;;
        --download-url-prefix)
            ((index += 1))
            prefix="${!index}"
            ;;
        --account)
            ((index += 1))
            account="${!index}"
            ;;
        --ed-key-file)
            ((index += 1))
            ed_key_file="${!index}"
            ;;
    esac
done

printf 'generate_appcast %s\n' "$*" >> "$TOOL_LOG"
if [[ -n "$ed_key_file" ]]; then
    IFS= read -r private_key || true
    printf 'stdin=%s\n' "$private_key" >> "$TOOL_LOG"
else
    printf 'account=%s\n' "$account" >> "$TOOL_LOG"
fi

if [[ -n "${FAKE_GENERATE_APPCAST_EXIT:-}" ]]; then
    exit "$FAKE_GENERATE_APPCAST_EXIT"
fi

dmg_path="$(find "${!#}" -maxdepth 1 -type f -name '*.dmg' -print -quit)"
dmg_name="$(basename -- "$dmg_path")"
signature="${FAKE_ED_SIGNATURE-signature-value}"
cat > "$output" <<EOF_XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>SwitchTab</title>
      <enclosure url="${prefix}${dmg_name}" sparkle:version="${FAKE_SPARKLE_VERSION-7}" sparkle:shortVersionString="${FAKE_SPARKLE_SHORT_VERSION-1.2}" sparkle:edSignature="${signature}" length="1" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF_XML

chmod +x "$BIN_DIR"/*

run_script() {
    set +e
    output="$(
        cd /
        env \
            DIRECT_BUILD_ROOT="$BUILD_ROOT" \
            SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY" \
            UPDATE_DOMAIN='updates.test.example' \
            CODESIGN_BIN="$BIN_DIR/codesign" \
            XCRUN_BIN="$BIN_DIR/xcrun" \
            SPCTL_BIN="$BIN_DIR/spctl" \
            PLUTIL_BIN="$BIN_DIR/plutil" \
            SHASUM_BIN='/usr/bin/shasum' \
            XMLLINT_BIN='/usr/bin/xmllint' \
            SPARKLE_APPCAST_BIN="$BIN_DIR/generate_appcast" \
            TOOL_LOG="$TOOL_LOG" \
            "$FIXTURE_ROOT/scripts/generate-appcast.sh" "$@" 2>&1
    )"
    status=$?
    set -e
}

rm -f "$TOOL_LOG"
rm -rf "$UPDATE_DIR"
unset SPARKLE_PRIVATE_ED_KEY FAKE_CODESIGN_EXIT FAKE_XCRUN_EXIT FAKE_SPCTL_EXIT FAKE_GENERATE_APPCAST_EXIT FAKE_ED_SIGNATURE PLIST_PUBLIC_KEY
run_script
assert_status 0
EXPECTED_DMG='SwitchTab-1.2-7.dmg'
[[ -f "$UPDATE_DIR/$EXPECTED_DMG" ]] || fail "versioned DMG was not generated"
[[ -f "$UPDATE_DIR/$EXPECTED_DMG.sha256" ]] || fail "versioned checksum was not generated"
[[ -f "$UPDATE_DIR/appcast.xml" ]] || fail "appcast was not generated"
grep -Fq "  $EXPECTED_DMG" "$UPDATE_DIR/$EXPECTED_DMG.sha256" || fail "staged checksum does not use basename"
grep -Fq "https://updates.test.example/$EXPECTED_DMG" "$UPDATE_DIR/appcast.xml" || fail "appcast has wrong enclosure URL"
grep -Fq -- '--account ed25519' "$TOOL_LOG" || fail "local mode did not pass --account ed25519"
if grep -Fq -- '--ed-key-file' "$TOOL_LOG"; then
    fail "local mode unexpectedly passed --ed-key-file"
fi

rm -rf "$UPDATE_DIR"
rm -f "$TOOL_LOG"
export SPARKLE_PRIVATE_ED_KEY="$PRIVATE_KEY"
run_script
assert_status 0
[[ -f "$UPDATE_DIR/appcast.xml" ]] || fail "CI appcast was not generated"
grep -Fq -- '--ed-key-file -' "$TOOL_LOG" || fail "CI mode did not pass --ed-key-file -"
grep -Fq "stdin=$PRIVATE_KEY" "$TOOL_LOG" || fail "CI private key was not provided via stdin"
if [[ "$output" == *"$PRIVATE_KEY"* ]] || grep -Fq "$PRIVATE_KEY" <(sed -n '1p' "$TOOL_LOG"); then
    fail "private key was logged"
fi
unset SPARKLE_PRIVATE_ED_KEY

printf 'corrupted dmg\n' > "$RELEASE_DIR/SwitchTab.dmg"
rm -rf "$UPDATE_DIR"
rm -f "$TOOL_LOG"
run_script
assert_status_nonzero
assert_output_contains 'checksum'
[[ ! -e "$TOOL_LOG" ]] || fail "corrupted checksum reached external verification tools"
assert_no_outputs

printf 'fixture dmg\n' > "$RELEASE_DIR/SwitchTab.dmg"
rm -rf "$UPDATE_DIR"
/usr/bin/shasum -a 256 "$RELEASE_DIR/SwitchTab.dmg" > "$RELEASE_DIR/SwitchTab.dmg.sha256"
export FAKE_ED_SIGNATURE=''
run_script
assert_status 66
assert_output_contains 'edSignature'
assert_no_outputs
unset FAKE_ED_SIGNATURE

rm -rf "$UPDATE_DIR"
export PLIST_PUBLIC_KEY="$MISMATCH_KEY"
run_script
assert_status 66
assert_output_contains 'public key mismatch'
assert_no_outputs
unset PLIST_PUBLIC_KEY

run_script --unexpected
assert_status 64
assert_output_contains 'Usage: scripts/generate-appcast.sh'

rm -rf "$UPDATE_DIR"
export FAKE_CODESIGN_EXIT=37
run_script
assert_status 37
assert_output_contains 'codesign'
assert_no_outputs
unset FAKE_CODESIGN_EXIT

bash -n "$SCRIPT_SOURCE"
bash -n "$PROJECT_ROOT/scripts/tests/generate-appcast-test.sh"

echo "generate-appcast contract tests passed"
