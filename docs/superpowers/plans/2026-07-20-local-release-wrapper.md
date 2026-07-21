# Local Release Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe one-command local entry point that loads machine-specific release settings and delegates to the existing signed/notarized release pipeline.

**Architecture:** Keep all signing and notarization behavior in `scripts/build-direct-distribution.sh`. A small Bash wrapper resolves the repository root, sources one ignored local configuration file, validates the three required values, and executes the existing script with exactly `--release`. A fixture-based shell contract test replaces the backend with a recorder so no real build, signing, or notarization occurs.

**Tech Stack:** Bash 3.2-compatible shell scripts, Git ignore rules, existing Swift/Xcode release pipeline.

---

## Task 1: Add the failing wrapper contract test

**Files:**

- Create: `scripts/tests/release-local-test.sh`

- [ ] Create an executable shell test with temporary-project fixtures and cleanup.
- [ ] Make the test fail clearly while `scripts/release-local.sh` is absent.
- [ ] Cover missing config, missing variable, exact environment/argument forwarding, invocation outside the repository, delegated exit status, ignore behavior, example completeness, and `bash -n` validation.
- [ ] Run `scripts/tests/release-local-test.sh` and confirm the expected RED failure is the missing wrapper.

The fake backend records the contract without invoking Xcode or Apple services:

```bash
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'SPARKLE_PUBLIC_ED_KEY=%s\n' "$SPARKLE_PUBLIC_ED_KEY"
    printf 'DEVELOPER_ID_APPLICATION=%s\n' "$DEVELOPER_ID_APPLICATION"
    printf 'NOTARYTOOL_KEYCHAIN_PROFILE=%s\n' "$NOTARYTOOL_KEYCHAIN_PROFILE"
    printf 'ARG=%s\n' "$@"
} > "$RECORD_PATH"

exit "${FAKE_EXIT_STATUS:-0}"
```

## Task 2: Add safe release configuration files

**Files:**

- Modify: `.gitignore`
- Create: `.env.release.local.example`
- Create locally, but keep ignored: `.env.release.local`

- [ ] Add `!.env.release.local.example` immediately after `.env.*`, preserving ignore coverage for the real local file.
- [ ] Add a tracked example with safe placeholders for all three variables.
- [ ] Add this Mac's ignored local configuration with the confirmed public Sparkle key, Developer ID identity, and notary profile name.
- [ ] Verify `.env.release.local` is ignored and `.env.release.local.example` is not ignored.

Tracked template:

```bash
# Copy this file to .env.release.local and replace the values for this Mac.
SPARKLE_PUBLIC_ED_KEY='your-sparkle-public-ed-key'
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
NOTARYTOOL_KEYCHAIN_PROFILE='switchtab-notary'
```

## Task 3: Implement the one-command wrapper

**Files:**

- Create: `scripts/release-local.sh`

- [ ] Resolve the repository root from `BASH_SOURCE`, independent of the caller's current directory.
- [ ] Reject arguments because the wrapper intentionally has no options.
- [ ] Fail before delegation when `.env.release.local` is absent, pointing to the example file.
- [ ] Source and export the local settings, then validate every required value is non-empty.
- [ ] Use `exec` to delegate exactly to `scripts/build-direct-distribution.sh --release` so output and exit status are preserved.
- [ ] Mark the wrapper executable.

Target implementation:

```bash
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
```

## Task 4: Verify without producing a real release

**Files:**

- Verify only: existing project sources and tests

- [ ] Run the shell contract test and confirm GREEN.
- [ ] Run `bash -n` on the wrapper, test, and existing distribution script.
- [ ] Run `scripts/build-direct-distribution.sh --prepare-only` with the public Sparkle key to validate workspace preparation only.
- [ ] Run the Swift test suite and unsigned Xcode build.
- [ ] Run `git diff --check` and verify pre-existing user changes are untouched.
- [ ] Commit only the tracked wrapper-related files; do not stage `.env.release.local` or unrelated working-tree changes.

Expected commit:

```text
feat: add local release wrapper
```
