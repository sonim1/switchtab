#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/setup-update-hosting.sh"

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

assert_output_contains() {
    local expected="$1"

    if [[ "$output" != *"$expected"* ]]; then
        fail "expected output to contain '$expected'; output: $output"
    fi
}

assert_output_equals() {
    local expected="$1"

    if [[ "$output" != "$expected" ]]; then
        fail "expected output '$expected', got: $output"
    fi
}

assert_log_equals() {
    local expected="$1"
    local actual

    actual="$(<"$WRANGLER_LOG")"
    if [[ "$actual" != "$expected" ]]; then
        fail "unexpected Wrangler command order; expected:
$expected
got:
$actual"
    fi
}

[[ -f "$SCRIPT" ]] || fail "scripts/setup-update-hosting.sh is missing"
[[ -x "$SCRIPT" ]] || fail "scripts/setup-update-hosting.sh is not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-setup-update-hosting.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
FIXTURE_SCRIPT="$FIXTURE_ROOT/scripts/setup-update-hosting.sh"
FAKE_BIN="$TEMP_ROOT/bin/wrangler"
WRANGLER_STATE="$TEMP_ROOT/state"
WRANGLER_LOG="$TEMP_ROOT/wrangler.log"
TRACE_TOKEN='trace-cloudflare-token'
TRACE_CONFIG="$TEMP_ROOT/trace.env"
mkdir -p "$FIXTURE_ROOT/scripts" "$TEMP_ROOT/bin" "$WRANGLER_STATE"
cp "$SCRIPT" "$FIXTURE_SCRIPT"
chmod +x "$FIXTURE_SCRIPT"
printf "CLOUDFLARE_API_TOKEN='%s'\n" "$TRACE_TOKEN" > "$TRACE_CONFIG"

cat > "$FAKE_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$WRANGLER_LOG"

case "$*" in
    "whoami")
        if [[ "${FAKE_WHOAMI_STATUS:-0}" -ne 0 ]]; then
            printf 'whoami failed: not authenticated\n' >&2
            exit "$FAKE_WHOAMI_STATUS"
        fi
        printf '{"authenticated":true}\n'
        ;;
    "r2 bucket info "*)
        if [[ -f "$WRANGLER_STATE/bucket" ]]; then
            printf '{"name":"%s"}\n' "${R2_BUCKET_NAME:-switchtab}"
        else
            if [[ -z "${FAKE_BUCKET_INFO_SILENT:-}" ]]; then
                printf '%s\n' "${FAKE_BUCKET_INFO_ERROR:-bucket not found}" >&2
            fi
            exit "${FAKE_BUCKET_INFO_STATUS:-1}"
        fi
        ;;
    "r2 bucket create "*)
        if [[ "${FAKE_BUCKET_CREATE_STATUS:-0}" -ne 0 ]]; then
            printf 'bucket create failed\n' >&2
            exit "$FAKE_BUCKET_CREATE_STATUS"
        fi
        touch "$WRANGLER_STATE/bucket"
        ;;
    "r2 bucket domain get "*)
        count_file="$WRANGLER_STATE/domain-get-count"
        count=0
        if [[ -f "$count_file" ]]; then
            count="$(<"$count_file")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$count_file"
        if [[ -n "${FAKE_FINAL_DOMAIN_GET_STATUS:-}" && -f "$WRANGLER_STATE/domain-added" ]]; then
            if [[ -z "${FAKE_FINAL_DOMAIN_GET_SILENT:-}" ]]; then
                printf 'final domain verification failed\n' >&2
            fi
            exit "$FAKE_FINAL_DOMAIN_GET_STATUS"
        fi
        if [[ -f "$WRANGLER_STATE/domain" ]]; then
            printf 'domain: %s\nenabled: %s\nmin_tls_version: %s\n' \
                "${FAKE_DOMAIN_OUTPUT_DOMAIN:-${UPDATE_DOMAIN:-updates.switchtab.royjen.com}}" \
                "${FAKE_DOMAIN_ENABLED:-Yes}" \
                "${FAKE_DOMAIN_MIN_TLS:-1.2}"
        else
            if [[ -z "${FAKE_DOMAIN_GET_SILENT:-}" ]]; then
                printf '%s\n' "${FAKE_DOMAIN_GET_ERROR:-domain not found}" >&2
            fi
            exit "${FAKE_DOMAIN_GET_STATUS:-1}"
        fi
        ;;
    "r2 bucket domain add "*)
        if [[ "${FAKE_DOMAIN_ADD_STATUS:-0}" -ne 0 ]]; then
            printf 'domain add failed\n' >&2
            exit "$FAKE_DOMAIN_ADD_STATUS"
        fi
        touch "$WRANGLER_STATE/domain" "$WRANGLER_STATE/domain-added"
        ;;
    *)
        printf 'unexpected Wrangler invocation: %s\n' "$*" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$FAKE_BIN"

reset_fixture() {
    rm -rf "$WRANGLER_STATE"
    mkdir -p "$WRANGLER_STATE"
    : > "$WRANGLER_LOG"
    unset FAKE_WHOAMI_STATUS FAKE_BUCKET_CREATE_STATUS FAKE_DOMAIN_ADD_STATUS \
        FAKE_FINAL_DOMAIN_GET_STATUS FAKE_FINAL_DOMAIN_GET_SILENT \
        FAKE_BUCKET_INFO_STATUS FAKE_BUCKET_INFO_ERROR FAKE_BUCKET_INFO_SILENT \
        FAKE_DOMAIN_GET_STATUS FAKE_DOMAIN_GET_ERROR FAKE_DOMAIN_GET_SILENT \
        FAKE_DOMAIN_OUTPUT_DOMAIN FAKE_DOMAIN_ENABLED FAKE_DOMAIN_MIN_TLS
}

invoke_script() {
    set +e
    output="$(
        cd /
        env \
            CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-zone-123}" \
            RELEASE_CONFIG_PATH="${RELEASE_CONFIG_PATH:-$TEMP_ROOT/does-not-exist}" \
            R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab}" \
            UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.royjen.com}" \
            WRANGLER_BIN="$FAKE_BIN" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            WRANGLER_STATE="$WRANGLER_STATE" \
            ${FAKE_WHOAMI_STATUS:+FAKE_WHOAMI_STATUS="$FAKE_WHOAMI_STATUS"} \
            ${FAKE_BUCKET_CREATE_STATUS:+FAKE_BUCKET_CREATE_STATUS="$FAKE_BUCKET_CREATE_STATUS"} \
            ${FAKE_DOMAIN_ADD_STATUS:+FAKE_DOMAIN_ADD_STATUS="$FAKE_DOMAIN_ADD_STATUS"} \
            ${FAKE_FINAL_DOMAIN_GET_STATUS:+FAKE_FINAL_DOMAIN_GET_STATUS="$FAKE_FINAL_DOMAIN_GET_STATUS"} \
            ${FAKE_FINAL_DOMAIN_GET_SILENT:+FAKE_FINAL_DOMAIN_GET_SILENT="$FAKE_FINAL_DOMAIN_GET_SILENT"} \
            FAKE_BUCKET_INFO_STATUS="${FAKE_BUCKET_INFO_STATUS:-}" \
            FAKE_BUCKET_INFO_ERROR="${FAKE_BUCKET_INFO_ERROR:-}" \
            FAKE_BUCKET_INFO_SILENT="${FAKE_BUCKET_INFO_SILENT:-}" \
            FAKE_DOMAIN_GET_STATUS="${FAKE_DOMAIN_GET_STATUS:-}" \
            FAKE_DOMAIN_GET_ERROR="${FAKE_DOMAIN_GET_ERROR:-}" \
            FAKE_DOMAIN_GET_SILENT="${FAKE_DOMAIN_GET_SILENT:-}" \
            FAKE_DOMAIN_OUTPUT_DOMAIN="${FAKE_DOMAIN_OUTPUT_DOMAIN:-}" \
            FAKE_DOMAIN_ENABLED="${FAKE_DOMAIN_ENABLED:-}" \
            FAKE_DOMAIN_MIN_TLS="${FAKE_DOMAIN_MIN_TLS:-}" \
            "$FIXTURE_SCRIPT" "$@" 2>&1
    )"
    status=$?
    set -e
}

invoke_trace_script() {
    set +e
    output="$(
        cd /
        env \
            CLOUDFLARE_API_TOKEN="$TRACE_TOKEN" \
            CLOUDFLARE_ZONE_ID=zone-123 \
            RELEASE_CONFIG_PATH="$TRACE_CONFIG" \
            R2_BUCKET_NAME=switchtab \
            UPDATE_DOMAIN=updates.switchtab.royjen.com \
            WRANGLER_BIN="$FAKE_BIN" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            WRANGLER_STATE="$WRANGLER_STATE" \
            bash -x "$FIXTURE_SCRIPT" "$@" 2>&1
    )"
    status=$?
    set -e
}

# Missing zone ID is rejected before any Wrangler command.
reset_fixture
set +e
output="$(
    cd /
    env -u CLOUDFLARE_ZONE_ID RELEASE_CONFIG_PATH="$TEMP_ROOT/does-not-exist" \
        WRANGLER_BIN="$FAKE_BIN" WRANGLER_LOG="$WRANGLER_LOG" WRANGLER_STATE="$WRANGLER_STATE" \
        "$FIXTURE_SCRIPT" 2>&1
)"
status=$?
set -e
assert_status 64
assert_output_contains "CLOUDFLARE_ZONE_ID"
[[ ! -s "$WRANGLER_LOG" ]] || fail "Wrangler ran before zone validation"

# A missing executable gives actionable install guidance.
reset_fixture
set +e
output="$(
    cd /
    env CLOUDFLARE_ZONE_ID=zone-123 RELEASE_CONFIG_PATH="$TEMP_ROOT/does-not-exist" \
        WRANGLER_BIN="$TEMP_ROOT/bin/missing-wrangler" WRANGLER_LOG="$WRANGLER_LOG" WRANGLER_STATE="$WRANGLER_STATE" \
        "$FIXTURE_SCRIPT" 2>&1
)"
status=$?
set -e
assert_status 66
assert_output_contains "npm ci"
[[ ! -s "$WRANGLER_LOG" ]] || fail "Wrangler ran while executable was missing"

# First run creates both resources in the required order and verifies them.
reset_fixture
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
assert_log_equals "whoami
r2 bucket info switchtab --json
r2 bucket create switchtab
r2 bucket info switchtab --json
r2 bucket domain get switchtab --domain updates.switchtab.royjen.com
r2 bucket domain add switchtab --domain updates.switchtab.royjen.com --zone-id zone-123 --min-tls 1.2 --force
r2 bucket domain get switchtab --domain updates.switchtab.royjen.com"
[[ -f "$WRANGLER_STATE/bucket" ]] || fail "bucket was not created"
[[ -f "$WRANGLER_STATE/domain" ]] || fail "domain was not created"

# Existing resources are left untouched on an idempotent second run.
: > "$WRANGLER_LOG"
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
assert_log_equals "whoami
r2 bucket info switchtab --json
r2 bucket domain get switchtab --domain updates.switchtab.royjen.com"

# Existing domains must have the requested name, be enabled, and use TLS 1.2+.
assert_invalid_domain_state() {
    local expected_output_domain="$1"
    local expected_enabled="$2"
    local expected_min_tls="$3"

    reset_fixture
    touch "$WRANGLER_STATE/bucket" "$WRANGLER_STATE/domain"
    FAKE_DOMAIN_OUTPUT_DOMAIN="$expected_output_domain"
    FAKE_DOMAIN_ENABLED="$expected_enabled"
    FAKE_DOMAIN_MIN_TLS="$expected_min_tls"
    invoke_script
    [[ "$status" -ne 0 ]] || fail "invalid domain state was accepted"
    [[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "invalid domain state triggered an add"
    [[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed for invalid domain state"
}

assert_invalid_domain_state wrong.example.com Yes 1.2
assert_invalid_domain_state updates.switchtab.royjen.com No 1.2
assert_invalid_domain_state updates.switchtab.royjen.com Yes 1.0

# The post-add verification is subject to the same state checks.
reset_fixture
FAKE_DOMAIN_OUTPUT_DOMAIN=wrong.example.com
invoke_script
[[ "$status" -ne 0 ]] || fail "invalid post-add domain state was accepted"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "post-add state test did not add the domain"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed for invalid post-add domain state"

# Valid resource names containing zone/token words still create and connect.
reset_fixture
R2_BUCKET_NAME=zone-assets UPDATE_DOMAIN=zone.example.com invoke_script
assert_status 0
assert_output_contains "https://zone.example.com/appcast.xml"
assert_log_equals "whoami
r2 bucket info zone-assets --json
r2 bucket create zone-assets
r2 bucket info zone-assets --json
r2 bucket domain get zone-assets --domain zone.example.com
r2 bucket domain add zone-assets --domain zone.example.com --zone-id zone-123 --min-tls 1.2 --force
r2 bucket domain get zone-assets --domain zone.example.com"

reset_fixture
R2_BUCKET_NAME=token-assets UPDATE_DOMAIN=token.example.com invoke_script
assert_status 0
assert_output_contains "https://token.example.com/appcast.xml"
[[ "$(grep -c '^r2 bucket create token-assets' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "token-named bucket was not created"
[[ "$(grep -c '^r2 bucket domain add token-assets --domain token.example.com' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "token-named domain was not added"

# bash -x must not expose credentials loaded from config or inherited environment.
reset_fixture
invoke_trace_script
assert_status 0
[[ "$output" != *"$TRACE_TOKEN"* ]] || fail "bash -x exposed the Cloudflare token"
[[ "$(<"$WRANGLER_LOG")" != *"$TRACE_TOKEN"* ]] || fail "Cloudflare token reached Wrangler argv/log"

# Authentication failures are returned byte-for-byte with their status.
reset_fixture
FAKE_WHOAMI_STATUS=17
invoke_script
assert_status 17
assert_output_equals "whoami failed: not authenticated"
[[ "$(wc -l < "$WRANGLER_LOG")" -eq 1 ]] || fail "commands ran after whoami failed"

# Unrelated bucket errors are not treated as an absent bucket.
reset_fixture
FAKE_BUCKET_INFO_STATUS=41
FAKE_BUCKET_INFO_ERROR='API token not found'
invoke_script
assert_status 41
assert_output_equals "API token not found"
[[ "$(grep -c '^r2 bucket create' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "bucket was created after an auth error"
[[ "$(grep -c '^r2 bucket domain' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain action ran after a bucket auth error"

# An auth diagnostic mentioning the requested bucket is still not bucket absence.
reset_fixture
FAKE_BUCKET_INFO_STATUS=51
FAKE_BUCKET_INFO_ERROR='API token not found for bucket switchtab'
invoke_script
assert_status 51
assert_output_equals "$FAKE_BUCKET_INFO_ERROR"
[[ "$(grep -c '^r2 bucket create' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "bucket was created after a same-line auth diagnostic"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after a same-line bucket auth diagnostic"

# A bare unrelated 404 is not treated as an absent bucket.
reset_fixture
FAKE_BUCKET_INFO_STATUS=42
FAKE_BUCKET_INFO_ERROR='HTTP 404 from zone endpoint'
invoke_script
assert_status 42
assert_output_equals "HTTP 404 from zone endpoint"
[[ "$(grep -c '^r2 bucket create' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "bucket was created after an unrelated 404"

# Endpoint context and an auth error on separate lines are not bucket absence.
reset_fixture
FAKE_BUCKET_INFO_STATUS=47
FAKE_BUCKET_INFO_ERROR=$'request failed for /r2/buckets/switchtab\nAPI token not found'
invoke_script
assert_status 47
assert_output_equals "$FAKE_BUCKET_INFO_ERROR"
[[ "$(grep -c '^r2 bucket create' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "bucket was created from split-line diagnostics"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed from split-line bucket diagnostics"

# An endpoint-style bucket 404 is a legitimate bucket absence.
reset_fixture
FAKE_BUCKET_INFO_STATUS=46
FAKE_BUCKET_INFO_ERROR='404 /r2/buckets/switchtab'
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
[[ -f "$WRANGLER_STATE/bucket" ]] || fail "endpoint-style bucket absence was not created"

# Wrangler's resource-specific missing-bucket transcript is a legitimate absence.
reset_fixture
FAKE_BUCKET_INFO_STATUS=49
FAKE_BUCKET_INFO_ERROR=$'A request to the Cloudflare API (/accounts/test-account/r2/buckets/switchtab) failed.\n  The specified bucket does not exist. [code: 10006]'
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
[[ -f "$WRANGLER_STATE/bucket" ]] || fail "Wrangler missing-bucket transcript did not create"

# An endpoint-style domain 404 is a legitimate domain absence.
reset_fixture
FAKE_DOMAIN_GET_STATUS=45
FAKE_DOMAIN_GET_ERROR='404 /r2/buckets/switchtab/domains/custom/updates.switchtab.royjen.com'
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
[[ -f "$WRANGLER_STATE/domain" ]] || fail "endpoint-style domain absence was not added"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "endpoint-style domain absence did not add exactly once"

# Wrangler's resource-specific missing-domain transcript is a legitimate absence.
reset_fixture
FAKE_DOMAIN_GET_STATUS=50
FAKE_DOMAIN_GET_ERROR=$'A request to the Cloudflare API (/accounts/test-account/r2/buckets/switchtab/domains/custom/updates.switchtab.royjen.com) failed.\n  The specified custom domain does not exist. [code: 10006]'
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
[[ -f "$WRANGLER_STATE/domain" ]] || fail "Wrangler missing-domain transcript did not add"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "Wrangler missing-domain transcript did not add exactly once"

# Wrangler 4.112's coded missing-domain transcript is a legitimate absence.
reset_fixture
FAKE_DOMAIN_GET_STATUS=53
FAKE_DOMAIN_GET_ERROR=$'A request to the Cloudflare API (/accounts/test-account/r2/buckets/switchtab/domains/custom/updates.switchtab.royjen.com) failed.\n  Domain not found. [code: 10053]'
invoke_script
assert_status 0
assert_output_contains "https://updates.switchtab.royjen.com/appcast.xml"
[[ -f "$WRANGLER_STATE/domain" ]] || fail "Wrangler coded missing-domain transcript did not add"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 1 ]] || fail "Wrangler coded missing-domain transcript did not add exactly once"

# Endpoint context and a zone error on separate lines are not domain absence.
reset_fixture
FAKE_DOMAIN_GET_STATUS=48
FAKE_DOMAIN_GET_ERROR=$'request failed for /r2/buckets/switchtab/domains/custom/updates.switchtab.royjen.com\nzone not found'
invoke_script
assert_status 48
assert_output_equals "$FAKE_DOMAIN_GET_ERROR"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain was added from split-line diagnostics"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed from split-line domain diagnostics"

# A zone error is not treated as an absent domain.
reset_fixture
FAKE_DOMAIN_GET_STATUS=43
FAKE_DOMAIN_GET_ERROR='zone not found'
invoke_script
assert_status 43
assert_output_equals "zone not found"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain was added after a zone error"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after a domain zone error"

# A zone diagnostic mentioning the requested domain is still not domain absence.
reset_fixture
FAKE_DOMAIN_GET_STATUS=52
FAKE_DOMAIN_GET_ERROR='zone not found for domain updates.switchtab.royjen.com'
invoke_script
assert_status 52
assert_output_equals "$FAKE_DOMAIN_GET_ERROR"
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain was added after a same-line zone diagnostic"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after a same-line domain zone diagnostic"

# A silent initial domain failure is propagated without attempting an add.
reset_fixture
FAKE_DOMAIN_GET_STATUS=44
FAKE_DOMAIN_GET_SILENT=1
invoke_script
assert_status 44
[[ "$(grep -c '^r2 bucket domain add' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain was added after a silent initial failure"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after a silent initial failure"

# An unknown silent bucket failure is not treated as an absent bucket.
reset_fixture
FAKE_BUCKET_INFO_STATUS=37
FAKE_BUCKET_INFO_SILENT=1
invoke_script
assert_status 37
[[ "$(<"$WRANGLER_LOG")" == $'whoami\nr2 bucket info switchtab --json' ]] || fail "silent bucket failure triggered a create"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after silent bucket failure"

# Bucket creation failures stop before domain work and preserve the status.
reset_fixture
FAKE_BUCKET_CREATE_STATUS=23
invoke_script
assert_status 23
assert_output_contains "bucket create failed"
[[ "$(grep -c '^r2 bucket domain' "$WRANGLER_LOG" || true)" -eq 0 ]] || fail "domain action ran after bucket create failure"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after bucket create failure"

# Domain add failures stop without claiming success.
reset_fixture
FAKE_DOMAIN_ADD_STATUS=29
invoke_script
assert_status 29
assert_output_contains "domain add failed"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after domain add failure"

# Final domain verification failures are propagated.
reset_fixture
FAKE_FINAL_DOMAIN_GET_STATUS=31
invoke_script
assert_status 31
assert_output_contains "final domain verification failed"
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after final verification failure"

# A silent final verification failure is still propagated and cannot claim success.
reset_fixture
FAKE_FINAL_DOMAIN_GET_STATUS=31
FAKE_FINAL_DOMAIN_GET_SILENT=1
invoke_script
assert_status 31
[[ "$output" != *"https://updates.switchtab.royjen.com/appcast.xml"* ]] || fail "success was printed after silent final verification failure"

# Unexpected arguments use the documented usage and status.
reset_fixture
invoke_script --unexpected
assert_status 64
assert_output_contains "Usage: scripts/setup-update-hosting.sh"
[[ ! -s "$WRANGLER_LOG" ]] || fail "Wrangler ran for unexpected arguments"

bash -n "$SCRIPT"
bash -n "$SCRIPT_DIR/setup-update-hosting-test.sh"

echo "setup-update-hosting contract tests passed"
