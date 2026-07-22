#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$PROJECT_ROOT/scripts/release-local.sh"
EXAMPLE="$PROJECT_ROOT/.env.release.local.example"
README="$PROJECT_ROOT/README.md"

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

[[ -x "$WRAPPER" ]] || fail "scripts/release-local.sh is missing or not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-release-local.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
FIXTURE_WRAPPER="$FIXTURE_ROOT/scripts/release-local.sh"
RECORD_PATH="$TEMP_ROOT/delegation.txt"
mkdir -p "$FIXTURE_ROOT/scripts"
cp "$WRAPPER" "$FIXTURE_WRAPPER"

cat > "$FIXTURE_ROOT/scripts/build-direct-distribution.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'SPARKLE_PUBLIC_ED_KEY=%s\n' "$SPARKLE_PUBLIC_ED_KEY"
    printf 'DEVELOPER_ID_APPLICATION=%s\n' "$DEVELOPER_ID_APPLICATION"
    printf 'NOTARYTOOL_KEYCHAIN_PROFILE=%s\n' "$NOTARYTOOL_KEYCHAIN_PROFILE"
    printf 'ARG=%s\n' "$@"
} > "$RECORD_PATH"

exit "${FAKE_EXIT_STATUS:-0}"
EOF
chmod +x "$FIXTURE_ROOT/scripts/build-direct-distribution.sh"

invoke_wrapper() {
    local fake_exit_status="$1"
    shift

    set +e
    output="$(
        cd /
        RECORD_PATH="$RECORD_PATH" \
            FAKE_EXIT_STATUS="$fake_exit_status" \
            "$FIXTURE_WRAPPER" "$@" 2>&1
    )"
    status=$?
    set -e
}

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 66
assert_output_contains ".env.release.local.example"
[[ ! -e "$RECORD_PATH" ]] || fail "missing config delegated to the release script"

cat > "$FIXTURE_ROOT/.env.release.local" <<'EOF'
DEVELOPER_ID_APPLICATION='Developer ID Application: Test User (TESTTEAM)'
NOTARYTOOL_KEYCHAIN_PROFILE='test-notary'
EOF

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 64
assert_output_contains "SPARKLE_PUBLIC_ED_KEY"
[[ ! -e "$RECORD_PATH" ]] || fail "missing variable delegated to the release script"

cat > "$FIXTURE_ROOT/.env.release.local" <<'EOF'
SPARKLE_PUBLIC_ED_KEY='public-key-value'
DEVELOPER_ID_APPLICATION='Developer ID Application: Test User (TESTTEAM)'
NOTARYTOOL_KEYCHAIN_PROFILE='test-notary'
EOF

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 0
grep -Fxq "SPARKLE_PUBLIC_ED_KEY=public-key-value" "$RECORD_PATH" || fail "Sparkle public key was not forwarded"
grep -Fxq "DEVELOPER_ID_APPLICATION=Developer ID Application: Test User (TESTTEAM)" "$RECORD_PATH" || fail "Developer ID identity was not preserved"
grep -Fxq "NOTARYTOOL_KEYCHAIN_PROFILE=test-notary" "$RECORD_PATH" || fail "notary profile was not forwarded"
grep -Fxq "ARG=--release" "$RECORD_PATH" || fail "--release was not forwarded"
[[ "$(grep -c '^ARG=' "$RECORD_PATH")" -eq 1 ]] || fail "wrapper forwarded unexpected arguments"

rm -f "$RECORD_PATH"
invoke_wrapper 37
assert_status 37
[[ -e "$RECORD_PATH" ]] || fail "delegated failure did not execute the release script"

rm -f "$RECORD_PATH"
invoke_wrapper 0 --unexpected
assert_status 64
assert_output_contains "Usage: scripts/release-local.sh"
[[ ! -e "$RECORD_PATH" ]] || fail "invalid arguments delegated to the release script"

git -C "$PROJECT_ROOT" check-ignore -q .env.release.local || fail ".env.release.local is not ignored"
if git -C "$PROJECT_ROOT" check-ignore -q .env.release.local.example; then
    fail ".env.release.local.example is unexpectedly ignored"
fi

for name in \
    SPARKLE_PUBLIC_ED_KEY \
    DEVELOPER_ID_APPLICATION \
    NOTARYTOOL_KEYCHAIN_PROFILE \
    SPARKLE_KEY_ACCOUNT \
    R2_BUCKET_NAME \
    UPDATE_DOMAIN \
    CLOUDFLARE_ACCOUNT_ID \
    CLOUDFLARE_ZONE_ID \
    CLOUDFLARE_API_TOKEN \
    R2_ACCESS_KEY_ID \
    R2_SECRET_ACCESS_KEY; do
    grep -q "^${name}=" "$EXAMPLE" || fail "$EXAMPLE is missing $name"
done

for text in \
    "npm ci --ignore-scripts" \
    "setup-update-hosting.sh" \
    "release-local.sh" \
    "generate-appcast.sh" \
    "publish-release.sh" \
    "CLOUDFLARE_API_TOKEN" \
    "R2_ACCESS_KEY_ID" \
    "R2_SECRET_ACCESS_KEY" \
    "SPARKLE_PRIVATE_ED_KEY" \
    "APPLE_CERTIFICATE_P12_BASE64" \
    "git push origin v" \
    "updates.switchtab.app/appcast.xml" \
    "refs/tags/" \
    "https://developers.cloudflare.com/r2/api/tokens/" \
    "https://developers.cloudflare.com/r2/api/s3/api/#conditional-operations" \
    "--account ed25519" \
    "Base64" \
    "Recovery"; do
    grep -Fq -- "$text" "$README" || fail "$README is missing '$text'"
done

stale_cloudflare_auth_url='https://developers.cloudflare.com/r2/api/s3/'"tokens/"
if grep -Fq "$stale_cloudflare_auth_url" "$README"; then
    fail "$README contains the stale Cloudflare R2 authentication link"
fi

grep -Eq 'v\*.*(ruleset|protection)|(ruleset|protection).*v\*' "$README" || \
    fail "$README is missing v* tag protection guidance"

user_specific_path='/Users/'"kendrick"
if grep -Fq "$user_specific_path" "$README" "$EXAMPLE"; then
    fail "documentation contains a user-specific local path"
fi

if grep -Eq -- '-----BEGIN (OPENSSH |RSA |EC |ED25519 )?PRIVATE KEY-----' "$README" "$EXAMPLE"; then
    fail "documentation contains a private-key block"
fi

if grep -Eq -- '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})' "$README" "$EXAMPLE"; then
    fail "documentation contains an obvious secret literal"
fi

bash -n "$WRAPPER"
bash -n "$PROJECT_ROOT/scripts/build-direct-distribution.sh"
bash -n "$SCRIPT_DIR/release-local-test.sh"

echo "release-local contract tests passed"
