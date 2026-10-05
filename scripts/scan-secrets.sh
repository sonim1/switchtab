#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"

if [[ "$#" -gt 1 ]]; then
    echo "usage: ${0##*/} [repository]" >&2
    exit 64
fi

repository="${1:-$PROJECT_ROOT}"

exec "$GITLEAKS_BIN" git "$repository" \
    --config "$PROJECT_ROOT/.gitleaks.toml" \
    --log-opts='--all --full-history --diff-merges=first-parent' \
    --redact=100 \
    --no-banner \
    --verbose
