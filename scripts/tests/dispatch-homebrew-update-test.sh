#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/dispatch-homebrew-update.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_status() {
    local expected="$1"
    [[ "$status" -eq "$expected" ]] || fail "expected status $expected, got $status; output: $output"
}

assert_no_call() {
    [[ ! -s "$GH_LOG" ]] || fail "GitHub CLI ran unexpectedly: $(<"$GH_LOG")"
}

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-homebrew-dispatch.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
GH_LOG="$TEMP_ROOT/gh.log"
FAKE_GH="$TEMP_ROOT/gh"
TOKEN='tap-token-secret-sentinel'

cat > "$FAKE_GH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'call\n' >> "$GH_LOG"

[[ "${GH_TOKEN:-}" == "$EXPECTED_TOKEN" ]] || exit 80
[[ -z "${TAP_GH_TOKEN:-}" ]] || exit 85
[[ "${GH_HOST:-}" == 'github.com' ]] || exit 81
[[ "${GH_REPO:-}" == 'sonim1/homebrew-tap' ]] || exit 82

expected=(
    api
    --hostname github.com
    --method POST
    repos/sonim1/homebrew-tap/dispatches
    -f event_type=homebrew_release
    -f 'client_payload[repository]=sonim1/switchtab'
    -f 'client_payload[tag]=v1.2.0'
)
[[ "$#" -eq "${#expected[@]}" ]] || exit 83
index=0
for argument in "$@"; do
    [[ "$argument" == "${expected[$index]}" ]] || exit 84
    index=$((index + 1))
done

exit "${FAKE_GH_STATUS:-0}"
EOF
chmod +x "$FAKE_GH"
: > "$GH_LOG"

run_dispatch() {
    set +e
    output="$(
        GH_BIN="$FAKE_GH" \
        GH_LOG="$GH_LOG" \
        EXPECTED_TOKEN="$TOKEN" \
        TAP_GH_TOKEN="${TEST_TAP_GH_TOKEN-$TOKEN}" \
        GH_HOST='attacker.example.invalid' \
        GH_REPO='attacker/ambient' \
        FAKE_GH_STATUS="${FAKE_GH_STATUS:-0}" \
        "$SCRIPT_SOURCE" "$@" 2>&1
    )"
    status=$?
    set -e
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "scripts/dispatch-homebrew-update.sh is missing"
[[ -x "$SCRIPT_SOURCE" ]] || fail "scripts/dispatch-homebrew-update.sh is not executable"

# The exact official repository dispatch is made once, despite hostile ambient gh bindings.
run_dispatch v1.2.0
assert_status 0
[[ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 1 ]] || fail "expected exactly one GitHub CLI call"
[[ "$output" != *"$TOKEN"* ]] || fail "token leaked to command output"

# GitHub CLI failures are not retried or translated.
: > "$GH_LOG"
FAKE_GH_STATUS=37
run_dispatch v1.2.0
assert_status 37
[[ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 1 ]] || fail "failed dispatch was retried"
[[ "$output" != *"$TOKEN"* ]] || fail "token leaked on GitHub CLI failure"
FAKE_GH_STATUS=0

# Usage, authentication, and tag validation happen before invoking GitHub CLI.
for arguments in \
    '' \
    'v1.2.0 extra' \
    '1.2.0' \
    'v' \
    'v1.' \
    'v1..2' \
    'v1.2-beta' \
    'v1.2 3' \
    'v1.2;touch-pwned'; do
    : > "$GH_LOG"
    if [[ -z "$arguments" ]]; then
        run_dispatch
    else
        # These are deliberately split to cover both excess arguments and unsafe tag text.
        # shellcheck disable=SC2086
        run_dispatch $arguments
    fi
    assert_status 64
    assert_no_call
done

for unsafe_tag in 'v1.2 3' $'v1.2\t3'; do
    : > "$GH_LOG"
    run_dispatch "$unsafe_tag"
    assert_status 64
    assert_no_call
done

: > "$GH_LOG"
TEST_TAP_GH_TOKEN=''
run_dispatch v1.2.0
assert_status 64
assert_no_call
unset TEST_TAP_GH_TOKEN

# Inherited xtrace is disabled before the token-bearing command is expanded.
: > "$GH_LOG"
set +e
output="$(
    GH_BIN="$FAKE_GH" GH_LOG="$GH_LOG" EXPECTED_TOKEN="$TOKEN" TAP_GH_TOKEN="$TOKEN" \
    GH_HOST='attacker.example.invalid' GH_REPO='attacker/ambient' \
    bash -x "$SCRIPT_SOURCE" v1.2.0 2>&1
)"
status=$?
set -e
assert_status 0
[[ "$output" != *"$TOKEN"* ]] || fail "token leaked under inherited xtrace"
[[ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 1 ]] || fail "xtrace scenario dispatched incorrectly"

bash -n "$0"
echo "dispatch-homebrew-update contract tests passed"
