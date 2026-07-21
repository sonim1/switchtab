#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$PROJECT_ROOT/.env.release.local"
DISTRIBUTION_SCRIPT="$PROJECT_ROOT/scripts/build-direct-distribution.sh"

if [[ $# -ne 0 ]]; then
    echo "Usage: scripts/release-local.sh" >&2
    exit 64
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Missing $CONFIG_PATH" >&2
    echo "Copy $PROJECT_ROOT/.env.release.local.example to $CONFIG_PATH and fill in the values." >&2
    exit 66
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_PATH"
set +a

require_env() {
    local name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "$name is required in $CONFIG_PATH" >&2
        exit 64
    fi
}

require_env "SPARKLE_PUBLIC_ED_KEY" "${SPARKLE_PUBLIC_ED_KEY:-}"
require_env "DEVELOPER_ID_APPLICATION" "${DEVELOPER_ID_APPLICATION:-}"
require_env "NOTARYTOOL_KEYCHAIN_PROFILE" "${NOTARYTOOL_KEYCHAIN_PROFILE:-}"

exec "$DISTRIBUTION_SCRIPT" --release
