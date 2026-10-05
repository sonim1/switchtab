#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCANNER="$PROJECT_ROOT/scripts/scan-secrets.sh"
GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-secret-scan.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

secret_prefix='AKIA'
secret_suffix='A2B3C4D5E6F7G2H3'
synthetic_secret="${secret_prefix}${secret_suffix}"

init_repository() {
    local repository="$1"
    git init -q -b main "$repository"
    git -C "$repository" config user.name 'Secret Scan Test'
    git -C "$repository" config user.email 'secret-scan-test@example.invalid'
}

commit_file() {
    local repository="$1"
    local path="$2"
    local contents="$3"
    mkdir -p "$(dirname -- "$repository/$path")"
    printf '%s\n' "$contents" > "$repository/$path"
    git -C "$repository" add -- "$path"
    git -C "$repository" commit -q -m "test fixture"
}

assert_redacted_failure() {
    local repository="$1"
    local scenario="$2"
    local output="$fixture_root/${scenario}.log"
    local status

    set +e
    GITLEAKS_BIN="$GITLEAKS_BIN" "$SCANNER" "$repository" > "$output" 2>&1
    status="$?"
    set -e

    [[ "$status" -ne 0 ]] || {
        echo "FAIL: $scenario did not detect the synthetic credential" >&2
        exit 1
    }
    ! grep -Fq "$synthetic_secret" "$output" || {
        echo "FAIL: $scenario exposed the synthetic credential" >&2
        exit 1
    }
    grep -Fq 'REDACTED' "$output" || {
        echo "FAIL: $scenario did not show a redacted finding" >&2
        exit 1
    }
}

clean_repository="$fixture_root/clean repository"
init_repository "$clean_repository"
commit_file "$clean_repository" README.md 'public fixture content'
GITLEAKS_BIN="$GITLEAKS_BIN" "$SCANNER" "$clean_repository" > "$fixture_root/clean.log" 2>&1

removed_repository="$fixture_root/removed"
init_repository "$removed_repository"
commit_file "$removed_repository" config.txt "credential=$synthetic_secret"
commit_file "$removed_repository" config.txt 'credential removed'
assert_redacted_failure "$removed_repository" removed-history

merge_repository="$fixture_root/merge"
init_repository "$merge_repository"
commit_file "$merge_repository" config.txt 'base'
git -C "$merge_repository" checkout -q -b feature
commit_file "$merge_repository" config.txt 'feature'
git -C "$merge_repository" checkout -q main
commit_file "$merge_repository" config.txt 'main'
set +e
git -C "$merge_repository" merge -q --no-ff feature -m 'merge feature' >/dev/null 2>&1
merge_status="$?"
set -e
[[ "$merge_status" -ne 0 ]] || {
    echo 'FAIL: merge fixture did not create the expected conflict' >&2
    exit 1
}
printf 'main\nfeature\ncredential=%s\n' "$synthetic_secret" > "$merge_repository/config.txt"
git -C "$merge_repository" add -- config.txt
git -C "$merge_repository" commit -q --no-edit

GITLEAKS_CONFIG="$PROJECT_ROOT/.gitleaks.toml" "$GITLEAKS_BIN" git "$merge_repository" \
    --log-opts='--all' --redact=100 --no-banner --verbose > "$fixture_root/merge-simple.log" 2>&1
assert_redacted_failure "$merge_repository" merge-resolution

example_repository="$fixture_root/example-path"
init_repository "$example_repository"
commit_file "$example_repository" tests/examples/config.txt "credential=$synthetic_secret"
assert_redacted_failure "$example_repository" example-path

echo 'secret-scan-test: PASS'
