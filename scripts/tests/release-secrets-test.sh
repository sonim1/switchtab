#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-release-secrets-test.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
export GH_LOG="$TEMP_ROOT/gh.log"

cat > "$TEMP_ROOT/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 7 && "$2" == set && "$4" == --env && "$5" == release-signing &&
   "$6" == --repo && "$7" == test-owner/switchtab ]] || exit 73
value="$(cat)"
[[ "$value" == "$3-test-sentinel" ]] || exit 74
case "$1:$3" in
    variable:DEVELOPER_ID_APPLICATION|variable:SPARKLE_PUBLIC_ED_KEY|variable:CLOUDFLARE_ACCOUNT_ID|\
    secret:APPLE_CERTIFICATE_P12_BASE64|secret:APPLE_CERTIFICATE_PASSWORD|\
    secret:APPLE_NOTARY_KEY_P8_BASE64|secret:APPLE_NOTARY_KEY_ID|secret:APPLE_NOTARY_ISSUER_ID|\
    secret:R2_ACCESS_KEY_ID|secret:R2_SECRET_ACCESS_KEY|secret:SPARKLE_PRIVATE_ED_KEY) ;;
    *) exit 75 ;;
esac
printf '%s %s\n' "$1" "$3" >> "$GH_LOG"
EOF
chmod +x "$TEMP_ROOT/gh"

names=(
    DEVELOPER_ID_APPLICATION SPARKLE_PUBLIC_ED_KEY CLOUDFLARE_ACCOUNT_ID
    APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD
    APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID
    R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY SPARKLE_PRIVATE_ED_KEY
)
for name in "${names[@]}"; do
    export "$name=$name-test-sentinel"
done
export TAP_GITHUB_APP_PRIVATE_KEY='tap-private-key-test-sentinel'

set +e
output="$(PATH="$TEMP_ROOT:$PATH" GITHUB_REPOSITORY='test-owner/switchtab' \
    bash "$PROJECT_ROOT/scripts/setup-release-secrets.sh" 2>&1)"
status=$?
set -e
[[ "$status" -eq 0 ]] || { echo "FAIL: signing environment setup rejected (status $status)" >&2; exit 1; }
[[ "$output" != *test-sentinel* ]] || { echo 'FAIL: setup output leaked credential input' >&2; exit 1; }
[[ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 11 ]] || { echo 'FAIL: expected three variables and eight signing secrets' >&2; exit 1; }
[[ "$(sort -u "$GH_LOG" | wc -l | tr -d ' ')" -eq 11 ]] || { echo 'FAIL: setup duplicated credential writes' >&2; exit 1; }
echo 'release signing secret isolation tests passed'
