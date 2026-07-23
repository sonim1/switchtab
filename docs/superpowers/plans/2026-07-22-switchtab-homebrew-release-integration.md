# SwitchTab Homebrew Release Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend SwitchTab's existing signed Sparkle/GitHub release pipeline with protected manual approval, a validated Homebrew release manifest, and a post-publication dispatch to `sonim1/homebrew-tap`.

**Architecture:** Keep the existing DMG, appcast, R2, and draft-release safety model. Add one deterministic manifest producer and one narrow dispatch command, upload the manifest with the draft GitHub Release, and notify the tap only after the release is public.

**Tech Stack:** Bash 3.2, Ruby standard library JSON/XML helpers, GitHub CLI, GitHub Actions protected environments, GitHub App installation token, existing Sparkle 2.9.4 and Cloudflare R2 scripts.

---

## File Map

- Create `scripts/generate-release-manifest.sh`: derive a strict SwitchTab Cask manifest from the validated appcast and DMG checksum.
- Create `scripts/tests/generate-release-manifest-test.sh`: fixture-test manifest content and failure behavior.
- Create `scripts/dispatch-homebrew-update.sh`: send the typed tap event with a short-lived token.
- Create `scripts/tests/dispatch-homebrew-update-test.sh`: verify endpoint, payload, and failure propagation with a fake `gh`.
- Modify `scripts/publish-release.sh`: require and upload the manifest with the immutable release assets.
- Modify `scripts/tests/publish-release-test.sh`: cover manifest upload, reuse, and conflict behavior.
- Modify `.github/workflows/release.yml`: split secret-free verification from the protected `release` job, mint the tap token, and dispatch after publication.
- Modify `scripts/tests/release-workflow-test.sh`: enforce job boundary, Environment, permissions, and step ordering.
- Modify `README.md`: document the Environment, GitHub App, Homebrew Cask, and retry flow.

The pre-existing user changes in `SwitchTab/SwitchTabApp.swift` and `SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift` belong to the user's main worktree and must never be staged, reverted, or reformatted by this plan.

### Task 1: Generate a deterministic SwitchTab release manifest

**Files:**
- Create: `scripts/generate-release-manifest.sh`
- Create: `scripts/tests/generate-release-manifest-test.sh`

- [ ] **Step 1: Write the failing manifest contract**

Create a fixture update directory containing `appcast.xml`, a versioned DMG, and its checksum. Invoke the script as `scripts/generate-release-manifest.sh v1.2.0`, parse JSON with Ruby, and assert this exact object shape:

```json
{
  "schemaVersion": 1,
  "repository": "sonim1/switchtab",
  "tag": "v1.2.0",
  "version": "1.2.0",
  "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "packages": [
    {
      "type": "cask",
      "token": "switchtab",
      "source": {
        "kind": "release-asset",
        "name": "SwitchTab-1.2.0-7.dmg",
        "sha256": "<fixture SHA-256>"
      }
    }
  ]
}
```

The test injects `GIT_BIN`, `SHASUM_BIN`, and `XMLLINT_BIN` fixtures. Define the
failure matrix explicitly and run every row before the success case:

```bash
failure_cases=(
  "missing-appcast:66"
  "malformed-tag:64"
  "tag-version-mismatch:64"
  "invalid-commit:64"
  "multiple-enclosures:64"
  "foreign-asset-name:64"
  "path-asset-name:64"
  "missing-checksum:66"
  "recorded-checksum-mismatch:1"
  "computed-checksum-mismatch:1"
)
for entry in "${failure_cases[@]}"; do
  scenario="${entry%%:*}"
  expected_status="${entry##*:}"
  prepare_fixture "$scenario"
  run_generator v1.2.0
  [[ "$status" -eq "$expected_status" ]] \
    || fail "$scenario returned $status, expected $expected_status"
  [[ ! -e "$UPDATE_DIR/release-manifest.json" ]] \
    || fail "$scenario wrote a manifest"
done
```

`prepare_fixture` resets the fixture directory and changes only the named
input; `run_generator` captures status/output with `set +e` and restores
`set -e` immediately afterward.

Run: `rtk test bash scripts/tests/generate-release-manifest-test.sh`

Expected: FAIL because the generator is missing.

- [ ] **Step 2: Implement the manifest generator**

Create `scripts/generate-release-manifest.sh` with this interface and validation order:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_DIR="${UPDATE_OUTPUT_DIR:-$PROJECT_ROOT/.build/direct-distribution/updates}"
GIT_BIN="${GIT_BIN:-git}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"

[[ $# -eq 1 ]] || { echo "Usage: scripts/generate-release-manifest.sh v<version>" >&2; exit 64; }
tag="$1"
[[ "$tag" =~ ^v[0-9]+([.][0-9]+)*$ ]] || { echo "Tag must match v<version>" >&2; exit 64; }

appcast="$UPDATE_DIR/appcast.xml"
manifest="$UPDATE_DIR/release-manifest.json"
[[ -f "$appcast" ]] || { echo "Missing appcast: $appcast" >&2; exit 66; }

enclosure_count="$($XMLLINT_BIN --xpath 'count(//*[local-name()="enclosure"])' "$appcast")"
[[ "$enclosure_count" == "1" ]] || { echo "Appcast must contain exactly one enclosure" >&2; exit 64; }
version="$($XMLLINT_BIN --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])' "$appcast")"
url="$($XMLLINT_BIN --xpath 'string(//*[local-name()="enclosure"]/@url)' "$appcast")"
asset="${url##*/}"
[[ "$tag" == "v$version" ]] || { echo "Tag/appcast version mismatch" >&2; exit 64; }
[[ "$asset" =~ ^SwitchTab-[0-9]+([.][0-9]+)*-[0-9]+([.][0-9]+){0,2}[.]dmg$ ]] \
  || { echo "Invalid SwitchTab DMG name" >&2; exit 64; }

dmg="$UPDATE_DIR/$asset"
checksum_file="$dmg.sha256"
[[ -f "$dmg" && -f "$checksum_file" ]] || { echo "Missing DMG or checksum" >&2; exit 66; }
computed="$($SHASUM_BIN -a 256 "$dmg" | awk '{print $1}')"
recorded="$(awk 'NR == 1 {print $1}' "$checksum_file")"
[[ "$computed" == "$recorded" && "$computed" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "DMG checksum mismatch" >&2; exit 1; }
commit="$($GIT_BIN rev-parse HEAD)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid release commit" >&2; exit 64; }

ruby -rjson -e '
  document = {
    schemaVersion: 1,
    repository: "sonim1/switchtab",
    tag: ARGV.fetch(1), version: ARGV.fetch(2), commit: ARGV.fetch(3),
    packages: [{
      type: "cask", token: "switchtab",
      source: {kind: "release-asset", name: ARGV.fetch(4), sha256: ARGV.fetch(5)}
    }]
  }
  File.write(ARGV.fetch(0), JSON.pretty_generate(document) + "\n")
' "$manifest" "$tag" "$version" "$commit" "$asset" "$computed"

echo "$manifest"
```

- [ ] **Step 3: Run the generator tests**

Run: `rtk test bash scripts/tests/generate-release-manifest-test.sh`

Expected: all success, malformed-input, and checksum cases pass.

Run: `rtk proxy bash -n scripts/generate-release-manifest.sh scripts/tests/generate-release-manifest-test.sh`

Expected: silent success.

- [ ] **Step 4: Commit manifest generation**

```bash
rtk git add scripts/generate-release-manifest.sh scripts/tests/generate-release-manifest-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: generate Homebrew release manifest"
```

### Task 2: Publish the manifest with the GitHub Release

**Files:**
- Modify: `scripts/publish-release.sh`
- Modify: `scripts/tests/publish-release-test.sh`

- [ ] **Step 1: Add failing release asset tests**

Extend the fixture to place `release-manifest.json` beside the appcast. Assert that the manifest is uploaded to the draft after the DMG/checksum and before `publish-update`, that a byte-identical existing manifest is reused, that a conflicting manifest stops before R2 publication, and that a missing manifest exits 66 before any `git` or `gh` mutation.

Run: `rtk test bash scripts/tests/publish-release-test.sh`

Expected: FAIL because the publisher currently knows only the DMG and checksum.

- [ ] **Step 2: Add the manifest to the existing asset contract**

Beside the current DMG/checksum paths, require:

```bash
MANIFEST="$UPDATE_DIR/release-manifest.json"
[[ -f "$MANIFEST" ]] || { echo "Missing release manifest" >&2; exit 66; }
```

Validate with Ruby that repository, tag, version, commit, token, asset name, and SHA exactly match the already validated release context. Change the existing asset loop from:

```bash
for asset in "$DMG" "$CHECKSUM"; do
```

to:

```bash
for asset in "$DMG" "$CHECKSUM" "$MANIFEST"; do
```

Do not change draft creation, immutable-asset conflict handling, R2 publication ordering, or final release publication.

- [ ] **Step 3: Run publisher regression coverage**

Run: `rtk test bash scripts/tests/publish-release-test.sh`

Expected: all existing cases plus manifest upload/retry/conflict cases pass.

- [ ] **Step 4: Commit manifest publication**

```bash
rtk git add scripts/publish-release.sh scripts/tests/publish-release-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: attach release manifest"
```

### Task 3: Dispatch the published release to the tap

**Files:**
- Create: `scripts/dispatch-homebrew-update.sh`
- Create: `scripts/tests/dispatch-homebrew-update-test.sh`

- [ ] **Step 1: Write the failing dispatch contract**

Use a fake `gh` to record calls. Assert one POST to `repos/sonim1/homebrew-tap/dispatches` with event type `homebrew_release` and client payload `{repository: "sonim1/switchtab", tag: "v1.2.0"}`. Reject malformed tags before invoking `gh`, require `TAP_GH_TOKEN`, and propagate a fake GitHub API failure.

Run: `rtk test bash scripts/tests/dispatch-homebrew-update-test.sh`

Expected: FAIL because the dispatcher is missing.

- [ ] **Step 2: Implement the narrow dispatcher**

```bash
#!/usr/bin/env bash
set -euo pipefail

GH_BIN="${GH_BIN:-gh}"
TAP_REPOSITORY="${TAP_REPOSITORY:-sonim1/homebrew-tap}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-sonim1/switchtab}"

[[ $# -eq 1 ]] || { echo "Usage: scripts/dispatch-homebrew-update.sh v<version>" >&2; exit 64; }
tag="$1"
[[ "$tag" =~ ^v[0-9]+([.][0-9]+)*$ ]] || { echo "Tag must match v<version>" >&2; exit 64; }
[[ -n "${TAP_GH_TOKEN:-}" ]] || { echo "TAP_GH_TOKEN is required" >&2; exit 64; }

GH_TOKEN="$TAP_GH_TOKEN" "$GH_BIN" api --method POST \
  "repos/$TAP_REPOSITORY/dispatches" \
  -f event_type=homebrew_release \
  -f "client_payload[repository]=$SOURCE_REPOSITORY" \
  -f "client_payload[tag]=$tag"
```

- [ ] **Step 3: Run dispatch tests and syntax checks**

Run: `rtk test bash scripts/tests/dispatch-homebrew-update-test.sh`

Expected: all payload and failure cases pass.

Run: `rtk proxy bash -n scripts/dispatch-homebrew-update.sh scripts/tests/dispatch-homebrew-update-test.sh`

Expected: silent success.

- [ ] **Step 4: Commit the dispatcher**

```bash
rtk git add scripts/dispatch-homebrew-update.sh scripts/tests/dispatch-homebrew-update-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: notify Homebrew tap releases"
```

### Task 4: Add protected approval and post-release dispatch to Actions

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `scripts/tests/release-workflow-test.sh`

- [ ] **Step 1: Add failing workflow-boundary assertions**

Parse the workflow with Ruby and assert:

- top-level `contents: read`;
- a `verify` job with tag validation, release contract tests, Swift tests, and unsigned Xcode build;
- `verify.outputs.release_commit`;
- a `release` job with `needs: verify`, `environment: release`, `contents: write`, and the existing global concurrency group;
- the release checkout commit equals `needs.verify.outputs.release_commit`;
- production secrets occur only in `release`;
- `generate-release-manifest.sh` runs after `generate-appcast.sh` and before `publish-release.sh`;
- a pinned GitHub App token action targets only `homebrew-tap`; and
- dispatch runs strictly after `publish-release.sh`.

Run: `rtk test bash scripts/tests/release-workflow-test.sh`

Expected: FAIL because the current workflow has one unprotected job.

- [ ] **Step 2: Split verification from release**

Move existing tag/provenance validation, Node setup, contract tests, Swift tests, and unsigned Xcode build into `verify`. Give its provenance step an ID and emit the exact commit:

```bash
printf 'release_commit=%s\n' "$tag_commit" >> "$GITHUB_OUTPUT"
```

Declare:

```yaml
outputs:
  release_commit: ${{ steps.provenance.outputs.release_commit }}
```

Create `release` with:

```yaml
needs: verify
environment: release
permissions:
  contents: write
```

Checkout the tag again with persisted credentials disabled and fail unless `git rev-parse HEAD` equals `${{ needs.verify.outputs.release_commit }}`. Keep signing workspace creation, Apple credential import, notarized DMG build, appcast generation, publication, and cleanup in this protected job.

- [ ] **Step 3: Generate the manifest and mint a tap token**

Add after appcast generation:

```yaml
- name: Generate release manifest
  run: scripts/generate-release-manifest.sh "$RELEASE_TAG"
```

After publishing, mint a short-lived installation token using a reviewed full-SHA pin of `actions/create-github-app-token`, `${{ vars.TAP_GITHUB_APP_ID }}`, `${{ secrets.TAP_GITHUB_APP_PRIVATE_KEY }}`, owner `sonim1`, and repository `homebrew-tap`. Then dispatch:

```yaml
- name: Notify Homebrew tap
  env:
    TAP_GH_TOKEN: ${{ steps.tap-token.outputs.token }}
  run: scripts/dispatch-homebrew-update.sh "$RELEASE_TAG"
```

The token step and dispatch are after GitHub Release publication. A dispatch failure fails the workflow but does not rebuild or replace public assets on rerun.

- [ ] **Step 4: Run workflow and full release contracts**

```bash
rtk test bash scripts/tests/release-workflow-test.sh
rtk test bash scripts/tests/generate-release-manifest-test.sh
rtk test bash scripts/tests/dispatch-homebrew-update-test.sh
rtk test bash scripts/tests/publish-release-test.sh
rtk test bash scripts/tests/publish-update-test.sh
```

Expected: all contract suites pass.

- [ ] **Step 5: Commit protected release integration**

```bash
rtk git add .github/workflows/release.yml scripts/tests/release-workflow-test.sh
rtk git diff --cached --check
rtk git commit -m "ci: protect and dispatch SwitchTab releases"
```

### Task 5: Document configuration and perform full verification

**Files:**
- Modify: `README.md`
- Modify: `scripts/tests/release-local-test.sh`

- [ ] **Step 1: Extend documentation contracts**

Require README references to the `release` Environment, required reviewer, `TAP_GITHUB_APP_ID`, `TAP_GITHUB_APP_PRIVATE_KEY`, `release-manifest.json`, `sonim1/homebrew-tap`, and the distinction between retrying dispatch and rebuilding a public tag.

- [ ] **Step 2: Update operator documentation**

Document GitHub App installation/permissions, the protected Environment, tag flow, tap PR result, and recovery commands. State that SwitchTab's canonical DMG is shared by GitHub Release, Sparkle, and the Homebrew Cask.

- [ ] **Step 3: Run all SwitchTab checks**

```bash
rtk test bash scripts/tests/release-tooling-test.sh
rtk test bash scripts/tests/release-local-test.sh
rtk test bash scripts/tests/generate-appcast-test.sh
rtk test bash scripts/tests/generate-release-manifest-test.sh
rtk test bash scripts/tests/setup-update-hosting-test.sh
rtk test bash scripts/tests/publish-update-test.sh
rtk test bash scripts/tests/publish-release-test.sh
rtk test bash scripts/tests/dispatch-homebrew-update-test.sh
rtk test bash scripts/tests/release-workflow-test.sh
rtk test swift test
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
```

Expected: all release contracts pass, the Xcode build succeeds, and whitespace checks are silent.

- [ ] **Step 4: Confirm user changes are absent from the branch diff**

Run:

```bash
rtk git diff origin/main...HEAD -- SwitchTab/SwitchTabApp.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
```

Expected: no output.

- [ ] **Step 5: Commit documentation**

```bash
rtk git add README.md scripts/tests/release-local-test.sh
rtk git diff --cached --check
rtk git commit -m "docs: explain Homebrew release integration"
```

## Live Configuration Handoff

After merging the tap receiver and this code, create/protect the GitHub `release` Environment, add the App ID/private key, and push a test tag matching `MARKETING_VERSION`. Approval must occur after `verify` succeeds. Validate the public DMG/appcast, GitHub Release manifest, tap PR checks, and installed Cask before treating the automation as production-ready.
