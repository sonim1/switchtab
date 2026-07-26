#!/usr/bin/env bash
set -euo pipefail
set +x

readonly TARGET_ENV="release"
readonly REPO="${GITHUB_REPOSITORY:-$(git remote get-url origin | sed -E 's#(https://github.com/|git@github.com:)##; s#\.git$##')}"

readonly REQUIRED_VARS=(
  "DEVELOPER_ID_APPLICATION"
  "SPARKLE_PUBLIC_ED_KEY"
  "CLOUDFLARE_ACCOUNT_ID"
)

readonly REQUIRED_SECRETS=(
  "APPLE_CERTIFICATE_P12_BASE64"
  "APPLE_CERTIFICATE_PASSWORD"
  "APPLE_NOTARY_KEY_P8_BASE64"
  "APPLE_NOTARY_KEY_ID"
  "APPLE_NOTARY_ISSUER_ID"
  "R2_ACCESS_KEY_ID"
  "R2_SECRET_ACCESS_KEY"
  "SPARKLE_PRIVATE_ED_KEY"
)

require_value() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    echo "missing env value: $name (source .env.release.local first)" >&2
    exit 1
  fi
  printf '%s' "$value"
}

main() {
  command -v gh >/dev/null 2>&1 || {
    echo "required command missing: gh" >&2
    exit 1
  }

  for name in "${REQUIRED_VARS[@]}"; do
    printf '%s\n' "$(require_value "$name")" |
      gh variable set "$name" --env "$TARGET_ENV" --repo "$REPO" >/dev/null
    echo "set variable: $name"
  done

  for name in "${REQUIRED_SECRETS[@]}"; do
    printf '%s' "$(require_value "$name")" |
      gh secret set "$name" --env "$TARGET_ENV" --repo "$REPO" >/dev/null
    echo "set secret: $name"
  done

  echo "release environment values updated in $REPO"
}

main "$@"
