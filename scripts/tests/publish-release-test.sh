#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/publish-release.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_status() {
    local expected="$1"
    [[ "$status" -eq "$expected" ]] || fail "expected status $expected, got $status; output: $output"
}

assert_output_contains() {
    local expected="$1"
    [[ "$output" == *"$expected"* ]] || fail "expected output to contain '$expected'; output: $output"
}

assert_no_mutation() {
    [[ ! -s "$MUTATION_LOG" ]] || fail "unexpected mutation(s): $(<"$MUTATION_LOG")"
}

assert_no_publish_or_edit() {
    ! grep -Fq 'publish-update' "$ORDER_LOG" 2>/dev/null || fail "R2 publisher ran unexpectedly"
    ! grep -Fq 'release edit ' "$ORDER_LOG" 2>/dev/null || fail "release was published unexpectedly"
}

assert_before() {
    local first="$1"
    local second="$2"
    local first_line second_line

    first_line="$(grep -nF -- "$first" "$ORDER_LOG" | head -1 | cut -d: -f1 || true)"
    second_line="$(grep -nF -- "$second" "$ORDER_LOG" | head -1 | cut -d: -f1 || true)"
    [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] || \
        fail "'$first' was not before '$second'; order: $(<"$ORDER_LOG")"
}

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-release.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
TEMP_ROOT="$(cd -- "$TEMP_ROOT" && pwd)"

FIXTURE_ROOT="$TEMP_ROOT/project"
FIXTURE_SCRIPT="$FIXTURE_ROOT/scripts/publish-release.sh"
UPDATE_DIR="$FIXTURE_ROOT/.build/direct-distribution/updates"
FAKE_BIN="$TEMP_ROOT/bin"
GH_STATE="$TEMP_ROOT/gh-state"
GH_ASSETS="$TEMP_ROOT/gh-assets"
GH_LOG="$TEMP_ROOT/gh.log"
GIT_LOG="$TEMP_ROOT/git.log"
ORDER_LOG="$TEMP_ROOT/order.log"
MUTATION_LOG="$TEMP_ROOT/mutations.log"
CONFIG_PATH="$TEMP_ROOT/release.env"
DMG_NAME='SwitchTab-1.2-7.dmg'
CHECKSUM_NAME="$DMG_NAME.sha256"

mkdir -p "$FIXTURE_ROOT/scripts" "$UPDATE_DIR" "$FAKE_BIN" "$GH_ASSETS"

cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$GIT_LOG"
case "$1 ${2:-}" in
    'rev-parse HEAD')
        exit_status="${FAKE_GIT_HEAD_STATUS:-0}"
        [[ "$exit_status" -eq 0 ]] || exit "$exit_status"
        printf '%s\n' "${FAKE_HEAD_COMMIT:-head-commit}"
        ;;
    'rev-parse v'*'^{commit}')
        exit_status="${FAKE_GIT_TAG_STATUS:-0}"
        [[ "$exit_status" -eq 0 ]] || exit "$exit_status"
        printf '%s\n' "${FAKE_TAG_COMMIT:-head-commit}"
        ;;
    'merge-base --is-ancestor')
        exit "${FAKE_GIT_ANCESTOR_STATUS:-0}"
        ;;
    *)
        exit 90
        ;;
esac
EOF

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$GH_LOG"
state='absent'
[[ ! -f "$GH_STATE" ]] || state="$(<"$GH_STATE")"

if [[ "$1" == api ]]; then
    if [[ "${FAKE_GH_PROBE_STATUS:-0}" -ne 0 ]]; then
        printf '%s\n' "${FAKE_GH_PROBE_OUTPUT:-network authentication failure}" >&2
        exit "$FAKE_GH_PROBE_STATUS"
    fi
    if [[ "$state" == absent ]]; then
        printf 'HTTP/2.0 404 Not Found\n'
        exit 1
    fi
    printf 'HTTP/2.0 200 OK\n'
    exit 0
fi

[[ "$1" == release ]] || exit 91
case "$2" in
    create)
        printf '%s\n' "$*" >> "$ORDER_LOG"
        printf '%s\n' "$*" >> "$MUTATION_LOG"
        [[ "${FAKE_GH_CREATE_STATUS:-0}" -eq 0 ]] || exit "$FAKE_GH_CREATE_STATUS"
        [[ "$state" == absent ]] || exit 92
        printf 'draft' > "$GH_STATE"
        ;;
    view)
        [[ "$state" != absent ]] || exit 93
        if [[ "${FAKE_GH_VIEW_STATUS:-0}" -ne 0 ]]; then
            exit "$FAKE_GH_VIEW_STATUS"
        fi
        if [[ "$*" == *'--json isDraft --jq .isDraft'* ]]; then
            if [[ "$state" == draft ]]; then printf 'true\n'; else printf 'false\n'; fi
        elif [[ "$*" == *"--json assets --jq .assets[].name"* ]]; then
            for asset in "$GH_ASSETS"/*; do
                [[ -e "$asset" ]] || continue
                basename "$asset"
            done
            if [[ -n "${FAKE_EXTRA_ASSET_NAMES:-}" ]]; then
                printf '%s\n' "$FAKE_EXTRA_ASSET_NAMES"
            fi
        else
            exit 94
        fi
        ;;
    upload)
        printf '%s\n' "$*" >> "$ORDER_LOG"
        printf '%s\n' "$*" >> "$MUTATION_LOG"
        [[ "${FAKE_GH_UPLOAD_STATUS:-0}" -eq 0 ]] || exit "$FAKE_GH_UPLOAD_STATUS"
        [[ $# -eq 4 && -f "$4" ]] || exit 95
        cp "$4" "$GH_ASSETS/$(basename -- "$4")"
        ;;
    download)
        [[ "${FAKE_GH_DOWNLOAD_STATUS:-0}" -eq 0 ]] || exit "$FAKE_GH_DOWNLOAD_STATUS"
        shift 3
        pattern=''
        directory=''
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --pattern) pattern="$2"; shift 2 ;;
                --dir) directory="$2"; shift 2 ;;
                *) exit 96 ;;
            esac
        done
        [[ -f "$GH_ASSETS/$pattern" ]] || exit 97
        cp "$GH_ASSETS/$pattern" "$directory/$pattern"
        ;;
    edit)
        printf '%s\n' "$*" >> "$ORDER_LOG"
        printf '%s\n' "$*" >> "$MUTATION_LOG"
        [[ "${FAKE_GH_EDIT_STATUS:-0}" -eq 0 ]] || exit "$FAKE_GH_EDIT_STATUS"
        [[ "$*" == 'release edit v1.2 --draft=false' ]] || exit 98
        printf 'published' > "$GH_STATE"
        ;;
    *)
        exit 99
        ;;
esac
EOF

cat > "$FIXTURE_ROOT/scripts/publish-update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 0 ]] || exit 89
printf 'publish-update\n' >> "$ORDER_LOG"
exit "${PUBLISH_STATUS:-0}"
EOF

chmod +x "$FAKE_BIN/git" "$FAKE_BIN/gh" "$FIXTURE_ROOT/scripts/publish-update.sh"

write_appcast() {
    local url="${1:-https://updates.test.example/$DMG_NAME}"
    local version="${2:-1.2}"

    cat > "$UPDATE_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<enclosure url="$url" sparkle:shortVersionString="$version" />
</item></channel></rss>
EOF
}

write_valid_artifacts() {
    printf 'fixture dmg payload\n' > "$UPDATE_DIR/$DMG_NAME"
    local hash
    hash="$(/usr/bin/shasum -a 256 "$UPDATE_DIR/$DMG_NAME" | awk '{print $1}')"
    printf '%s  %s\n' "$hash" "$DMG_NAME" > "$UPDATE_DIR/$CHECKSUM_NAME"
    write_appcast
}

reset_scenario() {
    rm -f "$GH_STATE" "$GH_ASSETS"/* "$UPDATE_DIR"/* "$CONFIG_PATH"
    : > "$GH_LOG"
    : > "$GIT_LOG"
    : > "$ORDER_LOG"
    : > "$MUTATION_LOG"
    FAKE_HEAD_COMMIT='head-commit'
    FAKE_TAG_COMMIT='head-commit'
    FAKE_GIT_HEAD_STATUS=0
    FAKE_GIT_TAG_STATUS=0
    FAKE_GIT_ANCESTOR_STATUS=0
    FAKE_GH_PROBE_STATUS=0
    FAKE_GH_PROBE_OUTPUT=''
    FAKE_GH_CREATE_STATUS=0
    FAKE_GH_VIEW_STATUS=0
    FAKE_GH_UPLOAD_STATUS=0
    FAKE_GH_DOWNLOAD_STATUS=0
    FAKE_GH_EDIT_STATUS=0
    FAKE_EXTRA_ASSET_NAMES=''
    PUBLISH_STATUS=0
    write_valid_artifacts
}

run_release() {
    set +e
    output="$(
        RELEASE_CONFIG_PATH="$CONFIG_PATH" \
        UPDATE_DOMAIN='updates.test.example' \
        GIT_BIN="$FAKE_BIN/git" \
        GH_BIN="$FAKE_BIN/gh" \
        PUBLISH_UPDATE_SCRIPT="$FIXTURE_ROOT/scripts/publish-update.sh" \
        GH_STATE="$GH_STATE" \
        GH_ASSETS="$GH_ASSETS" \
        GH_LOG="$GH_LOG" \
        GIT_LOG="$GIT_LOG" \
        ORDER_LOG="$ORDER_LOG" \
        MUTATION_LOG="$MUTATION_LOG" \
        FAKE_HEAD_COMMIT="$FAKE_HEAD_COMMIT" \
        FAKE_TAG_COMMIT="$FAKE_TAG_COMMIT" \
        FAKE_GIT_HEAD_STATUS="$FAKE_GIT_HEAD_STATUS" \
        FAKE_GIT_TAG_STATUS="$FAKE_GIT_TAG_STATUS" \
        FAKE_GIT_ANCESTOR_STATUS="$FAKE_GIT_ANCESTOR_STATUS" \
        FAKE_GH_PROBE_STATUS="$FAKE_GH_PROBE_STATUS" \
        FAKE_GH_PROBE_OUTPUT="$FAKE_GH_PROBE_OUTPUT" \
        FAKE_GH_CREATE_STATUS="$FAKE_GH_CREATE_STATUS" \
        FAKE_GH_VIEW_STATUS="$FAKE_GH_VIEW_STATUS" \
        FAKE_GH_UPLOAD_STATUS="$FAKE_GH_UPLOAD_STATUS" \
        FAKE_GH_DOWNLOAD_STATUS="$FAKE_GH_DOWNLOAD_STATUS" \
        FAKE_GH_EDIT_STATUS="$FAKE_GH_EDIT_STATUS" \
        FAKE_EXTRA_ASSET_NAMES="$FAKE_EXTRA_ASSET_NAMES" \
        PUBLISH_STATUS="$PUBLISH_STATUS" \
        "$FIXTURE_SCRIPT" "$@" 2>&1
    )"
    status=$?
    set -e
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "scripts/publish-release.sh is missing"
[[ -x "$SCRIPT_SOURCE" ]] || fail "scripts/publish-release.sh is not executable"
cp "$SCRIPT_SOURCE" "$FIXTURE_SCRIPT"
chmod +x "$FIXTURE_SCRIPT"

# New draft: stage both exact assets, publish R2, and expose the release last.
reset_scenario
run_release v1.2
assert_status 0
assert_before 'release create v1.2' "release upload v1.2 $UPDATE_DIR/$DMG_NAME"
assert_before "release upload v1.2 $UPDATE_DIR/$CHECKSUM_NAME" 'publish-update'
assert_before 'publish-update' 'release edit v1.2 --draft=false'
[[ "$(tail -1 "$ORDER_LOG")" == 'release edit v1.2 --draft=false' ]] || fail "final edit was not last"
grep -Fxq 'release create v1.2 --draft --verify-tag --generate-notes --title SwitchTab 1.2' "$GH_LOG" || \
    fail "draft creation flags/title were incorrect: $(<"$GH_LOG")"
[[ -f "$GH_ASSETS/$DMG_NAME" && -f "$GH_ASSETS/$CHECKSUM_NAME" ]] || fail "exact assets were not uploaded"
! grep -Fq -- '--clobber' "$GH_LOG" || fail "asset upload used --clobber"
[[ "$(<"$GH_STATE")" == published ]] || fail "draft was not published"

# Existing draft and published release are idempotent when both assets match.
reset_scenario
printf 'draft' > "$GH_STATE"
cp "$UPDATE_DIR/$DMG_NAME" "$GH_ASSETS/$DMG_NAME"
cp "$UPDATE_DIR/$CHECKSUM_NAME" "$GH_ASSETS/$CHECKSUM_NAME"
run_release v1.2
assert_status 0
! grep -Fq 'release upload ' "$ORDER_LOG" || fail "existing assets were reuploaded"
assert_before 'publish-update' 'release edit v1.2 --draft=false'

reset_scenario
printf 'published' > "$GH_STATE"
cp "$UPDATE_DIR/$DMG_NAME" "$GH_ASSETS/$DMG_NAME"
cp "$UPDATE_DIR/$CHECKSUM_NAME" "$GH_ASSETS/$CHECKSUM_NAME"
run_release v1.2
assert_status 0
[[ "$(<"$ORDER_LOG")" == 'publish-update' ]] || fail "published release was mutated: $(<"$ORDER_LOG")"

# Existing assets are immutable, unambiguous, and successfully downloaded before comparison.
for conflicting_name in "$DMG_NAME" "$CHECKSUM_NAME"; do
    reset_scenario
    printf 'draft' > "$GH_STATE"
    cp "$UPDATE_DIR/$DMG_NAME" "$GH_ASSETS/$DMG_NAME"
    cp "$UPDATE_DIR/$CHECKSUM_NAME" "$GH_ASSETS/$CHECKSUM_NAME"
    printf 'conflicting bytes\n' > "$GH_ASSETS/$conflicting_name"
    run_release v1.2
    [[ "$status" -ne 0 ]] || fail "conflicting $conflicting_name was accepted"
    assert_output_contains 'checksum conflict'
    assert_no_publish_or_edit
    ! grep -Fq 'release upload ' "$ORDER_LOG" || fail "conflicting asset was overwritten"
done

reset_scenario
printf 'draft' > "$GH_STATE"
cp "$UPDATE_DIR/$DMG_NAME" "$GH_ASSETS/$DMG_NAME"
cp "$UPDATE_DIR/$CHECKSUM_NAME" "$GH_ASSETS/$CHECKSUM_NAME"
FAKE_GH_DOWNLOAD_STATUS=46
run_release v1.2
assert_status 46
assert_no_publish_or_edit

reset_scenario
printf 'draft' > "$GH_STATE"
cp "$UPDATE_DIR/$DMG_NAME" "$GH_ASSETS/$DMG_NAME"
cp "$UPDATE_DIR/$CHECKSUM_NAME" "$GH_ASSETS/$CHECKSUM_NAME"
FAKE_EXTRA_ASSET_NAMES="$DMG_NAME"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "duplicate asset name was accepted"
assert_output_contains 'ambiguous'
assert_no_publish_or_edit

# R2 failure preserves its exact status and never exposes the draft.
reset_scenario
PUBLISH_STATUS=31
run_release v1.2
assert_status 31
[[ "$(<"$GH_STATE")" == draft ]] || fail "R2 failure did not leave a draft"
grep -Fxq 'publish-update' "$ORDER_LOG" || fail "R2 publisher did not run"
! grep -Fq 'release edit ' "$ORDER_LOG" || fail "R2 failure exposed the release"

# Input, XML, and checksum validation all happen before GitHub mutation.
reset_scenario
run_release
assert_status 64
assert_output_contains 'Usage: scripts/publish-release.sh v<version>'
assert_no_mutation

reset_scenario
run_release --help
assert_status 64
assert_no_mutation

reset_scenario
run_release v1.2 extra
assert_status 64
assert_no_mutation

reset_scenario
run_release v9.9
assert_status 64
assert_output_contains 'does not match'
assert_no_mutation

reset_scenario
cat > "$UPDATE_DIR/appcast.xml" <<'EOF'
<rss><channel><item /></channel></rss>
EOF
run_release v1.2
[[ "$status" -ne 0 ]] || fail "missing enclosure was accepted"
assert_no_mutation

reset_scenario
cat > "$UPDATE_DIR/appcast.xml" <<'EOF'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<enclosure url="https://updates.test.example/SwitchTab-1.2-7.dmg" sparkle:shortVersionString="1.2" />
<enclosure url="https://updates.test.example/SwitchTab-1.2-8.dmg" sparkle:shortVersionString="1.2" />
</item></channel></rss>
EOF
run_release v1.2
[[ "$status" -ne 0 ]] || fail "multiple enclosures were accepted"
assert_no_mutation

for bad_url in \
    'https://evil.example/SwitchTab-1.2-7.dmg' \
    'https://updates.test.example/../SwitchTab-1.2-7.dmg' \
    'https://updates.test.example/SwitchTab-1.2-7.dmg?download=1' \
    'https://updates.test.example/subdir/SwitchTab-1.2-7.dmg'; do
    reset_scenario
    write_appcast "$bad_url"
    run_release v1.2
    [[ "$status" -ne 0 ]] || fail "unsafe enclosure URL was accepted: $bad_url"
    assert_no_mutation
done

reset_scenario
write_appcast 'https://updates.test.example/SwitchTab-1.2-7.dmg' ''
sed -i '' 's/ sparkle:shortVersionString="1.2"//' "$UPDATE_DIR/appcast.xml"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "missing short version was accepted"
assert_no_mutation

reset_scenario
printf '%064d  Other.dmg\n' 0 > "$UPDATE_DIR/$CHECKSUM_NAME"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "unrelated checksum was accepted"
assert_no_mutation

reset_scenario
cat "$UPDATE_DIR/$CHECKSUM_NAME" >> "$UPDATE_DIR/$CHECKSUM_NAME.copy"
cat "$UPDATE_DIR/$CHECKSUM_NAME.copy" >> "$UPDATE_DIR/$CHECKSUM_NAME"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "multiple checksum records were accepted"
assert_no_mutation

reset_scenario
printf '%064d  %s\n' 0 "$DMG_NAME" > "$UPDATE_DIR/$CHECKSUM_NAME"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "checksum mismatch was accepted"
assert_no_mutation

# Git provenance checks fail before GitHub access/mutation and preserve true tool errors.
reset_scenario
FAKE_GIT_TAG_STATUS=27
run_release v1.2
assert_status 27
[[ ! -s "$GH_LOG" ]] || fail "GitHub was accessed after absent tag"

reset_scenario
FAKE_TAG_COMMIT='other-commit'
run_release v1.2
assert_status 64
assert_output_contains 'does not point to HEAD'
[[ ! -s "$GH_LOG" ]] || fail "GitHub was accessed after tag/HEAD mismatch"

reset_scenario
FAKE_GIT_ANCESTOR_STATUS=1
run_release v1.2
assert_status 64
assert_output_contains 'not on origin/main'
[[ ! -s "$GH_LOG" ]] || fail "GitHub was accessed after ancestry mismatch"

reset_scenario
FAKE_GIT_ANCESTOR_STATUS=29
run_release v1.2
assert_status 29
[[ ! -s "$GH_LOG" ]] || fail "GitHub was accessed after git failure"

# GitHub failures cannot be confused with absence and preserve their exact statuses.
reset_scenario
FAKE_GH_PROBE_STATUS=42
FAKE_GH_PROBE_OUTPUT='authentication network failure'
run_release v1.2
assert_status 42
assert_no_mutation

reset_scenario
FAKE_GH_PROBE_STATUS=42
FAKE_GH_PROBE_OUTPUT=$'HTTP/2.0 404 Not Found\nHTTP/2.0 401 Unauthorized'
run_release v1.2
assert_status 42
assert_no_mutation

reset_scenario
FAKE_GH_CREATE_STATUS=47
run_release v1.2
assert_status 47
assert_no_publish_or_edit

reset_scenario
FAKE_GH_UPLOAD_STATUS=43
run_release v1.2
assert_status 43
assert_no_publish_or_edit

reset_scenario
FAKE_GH_EDIT_STATUS=44
run_release v1.2
assert_status 44
grep -Fxq 'publish-update' "$ORDER_LOG" || fail "R2 was not published before edit failure"
[[ "$(<"$GH_STATE")" == draft ]] || fail "failed edit changed draft state"

# Inherited xtrace cannot disclose config credential sentinels.
reset_scenario
TRACE_GH_SECRET='trace-gh-secret'
TRACE_CF_SECRET='trace-cloudflare-secret'
TRACE_R2_SECRET='trace-r2-secret'
cat > "$CONFIG_PATH" <<EOF
GH_TOKEN='$TRACE_GH_SECRET'
CLOUDFLARE_API_TOKEN='$TRACE_CF_SECRET'
R2_SECRET_ACCESS_KEY='$TRACE_R2_SECRET'
EOF
set +e
output="$(
    RELEASE_CONFIG_PATH="$CONFIG_PATH" \
    UPDATE_DOMAIN='updates.test.example' \
    GIT_BIN="$FAKE_BIN/git" GH_BIN="$FAKE_BIN/gh" \
    PUBLISH_UPDATE_SCRIPT="$FIXTURE_ROOT/scripts/publish-update.sh" \
    GH_STATE="$GH_STATE" GH_ASSETS="$GH_ASSETS" GH_LOG="$GH_LOG" GIT_LOG="$GIT_LOG" \
    ORDER_LOG="$ORDER_LOG" MUTATION_LOG="$MUTATION_LOG" \
    bash -x "$FIXTURE_SCRIPT" v1.2 2>&1
)"
status=$?
set -e
assert_status 0
[[ "$output" != *"$TRACE_GH_SECRET"* && "$output" != *"$TRACE_CF_SECRET"* && "$output" != *"$TRACE_R2_SECRET"* ]] || \
    fail "credential sentinel leaked under xtrace: $output"

# Required commands, scripts, and files are checked before mutation.
reset_scenario
set +e
output="$(
    RELEASE_CONFIG_PATH="$CONFIG_PATH" UPDATE_DOMAIN='updates.test.example' \
    GIT_BIN="$TEMP_ROOT/missing-git" GH_BIN="$FAKE_BIN/gh" \
    PUBLISH_UPDATE_SCRIPT="$FIXTURE_ROOT/scripts/publish-update.sh" \
    "$FIXTURE_SCRIPT" v1.2 2>&1
)"
status=$?
set -e
assert_status 66

reset_scenario
rm -f "$FIXTURE_ROOT/scripts/publish-update.sh"
run_release v1.2
assert_status 66
cp "$PROJECT_ROOT/scripts/publish-update.sh" "$FIXTURE_ROOT/scripts/publish-update.sh"
chmod +x "$FIXTURE_ROOT/scripts/publish-update.sh"

reset_scenario
rm -f "$UPDATE_DIR/$DMG_NAME"
run_release v1.2
assert_status 66
assert_no_mutation

bash -n "$SCRIPT_SOURCE"
bash -n "$0"
echo "publish-release contract tests passed"
