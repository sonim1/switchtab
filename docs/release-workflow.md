# Release Workflow

## Pull Request Versions

For normal product work, open a pull request without editing
`MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. CI calculates and commits the
version on the pull-request branch before verification:

- no release label: patch, for example `1.0.4` to `1.0.5`
- `release:minor`: minor, for example `1.0.4` to `1.1.0`
- `release:major`: major, for example `1.0.4` to `2.0.0`

Every release bump increments the integer build number once. Applying both
release labels is invalid and blocks CI until one is removed. Documentation-
only changes under `*.md`, `*.markdown`, `docs/`, or `specs/` do not change
either version and do not create a release after merge.

Automatic version commits are limited to trusted contributors working from a
branch in this repository. Update an older pull-request branch from `main` when
GitHub reports it is behind; CI then recalculates from the latest base.

## GitHub Configuration

The release workflow expects these repository variables:

- `DEVELOPER_ID_APPLICATION`
- `SPARKLE_PUBLIC_ED_KEY`
- `CLOUDFLARE_ACCOUNT_ID`

It expects these GitHub Actions secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PRIVATE_ED_KEY`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `TAP_GITHUB_APP_PRIVATE_KEY`

Set non-secret values directly. Let `gh` read secrets from a prompt or file
instead of placing secret text in shell history:

```bash
gh variable set DEVELOPER_ID_APPLICATION --body "Developer ID Application: Your Name (TEAMID)"
gh variable set SPARKLE_PUBLIC_ED_KEY --body "your-public-ed25519-key"
gh variable set CLOUDFLARE_ACCOUNT_ID --body "your-account-id"

gh secret set --env release APPLE_CERTIFICATE_PASSWORD
gh secret set --env release APPLE_NOTARY_KEY_ID
gh secret set --env release APPLE_NOTARY_ISSUER_ID
gh secret set --env release R2_ACCESS_KEY_ID
gh secret set --env release R2_SECRET_ACCESS_KEY
```

Export transport values only into a permission-restricted temporary directory.
Base64 is transport encoding, not encryption:

```bash
release_secret_dir="$(mktemp -d)"
chmod 700 "$release_secret_dir"
/path/to/Sparkle/bin/generate_keys --account ed25519 -x "$release_secret_dir/sparkle-private-key"
gh secret set --env release SPARKLE_PRIVATE_ED_KEY < "$release_secret_dir/sparkle-private-key"
openssl base64 -A -in /path/to/certificate.p12 | gh secret set --env release APPLE_CERTIFICATE_P12_BASE64
openssl base64 -A -in /path/to/AuthKey.p8 | gh secret set --env release APPLE_NOTARY_KEY_P8_BASE64
rm -f "$release_secret_dir/sparkle-private-key"
rmdir "$release_secret_dir"
```

Never commit the `.p12`, `.p8`, exported Sparkle private key, or decoded
copies. Remove temporary exports immediately after registration.

## Protected Release Environment

Create a GitHub `release` Environment and store Apple, Sparkle, R2, and optional
tap production credentials there. The current automatic mode has no required
reviewer rule: merging a release-relevant PR into `main` is the production
release authorization point.

The secret-free `verify` job does not use the protected Environment. Workflow
YAML injects Apple, Sparkle, and R2 secrets only into `release` steps, and the
tap App private key only into `notify`. The Environment itself makes all its
secrets available to either job when that job starts; true availability
isolation requires separate Environments.

Adding required reviewers deliberately changes merge-to-main releases into
manual approval. Both `release` and enabled `notify` jobs then pause
independently.

## Homebrew Tap Integration

Homebrew notification is opt-in. The `notify` job runs only when the repository
variable `ENABLE_HOMEBREW_NOTIFY` is exactly `true`. Leave it unset or set it to
`false` to publish GitHub, Sparkle, and R2 without touching the tap.

When enabled, store `TAP_GITHUB_APP_PRIVATE_KEY` and `TAP_GITHUB_APP_ID` in the
`release` Environment. The GitHub App must be installed only on
`sonim1/homebrew-tap` with the minimum union of permissions:

- `Administration: Read` for the branch-protection preflight
- `Contents: Read & write` for repository dispatch and the update branch
- `Pull requests: Read & write` for pull-request creation and auto-merge

The App does not need installation on `sonim1/switchtab`. Register the same App
ID and private key in both configuration locations:

```bash
gh variable set --repo sonim1/switchtab ENABLE_HOMEBREW_NOTIFY --body "true"
gh variable set --env release TAP_GITHUB_APP_ID --body "your-github-app-id"
gh secret set --env release TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem

gh variable set --repo sonim1/homebrew-tap TAP_GITHUB_APP_ID --body "your-github-app-id"
gh secret set --repo sonim1/homebrew-tap TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem
```

Before enabling notification, configure `sonim1/homebrew-tap` to accept the
`homebrew_release` repository-dispatch event, enable pull-request auto-merge,
and protect its default branch in strict mode with exact required checks
`contracts` and `homebrew`. Release scripts do not mutate these settings.

## Tags and Release Execution

Protect creation and updates of `v*` tags with a GitHub ruleset restricted to
maintainers. Every pull request runs secret-free CI. A release-relevant PR must
strictly increase Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
both app target configurations. The build version must contain one to three
numeric components and must never decrease or be reused.

After a release-relevant PR merges, the push to `main` creates or verifies the
annotated `refs/tags/v<MARKETING_VERSION>` on that exact merge commit and pushes
only that tag ref. GitHub recursion suppression means the tag push with
`GITHUB_TOKEN` does not start another workflow, so the automatic workflow
explicitly dispatches `release.yml` with the existing tag.

Both automatic planning/tagging and downstream release execution use fixed,
non-cancelling, max-queued concurrency groups. Rapid main merges are serialized
and preserved rather than replacing an older queued run.

Normal automatic flow:

```text
PR CI -> main merge -> exact annotated tag -> explicit release dispatch -> secret-free verify -> signed release -> public GitHub/Sparkle publication -> notify -> tap PR/CI/auto-merge
```

A deliberately maintainer-pushed recovery tag enters the same downstream flow:

```text
tag push -> secret-free verify -> signed release -> public GitHub/Sparkle publication -> notify -> tap PR/CI/auto-merge
```

The workflow accepts only exact `refs/tags/v<version>` references and verifies
that the tag commit is on `origin/main`. Manual workflow dispatch is
recovery-only and must name an existing version tag; it does not create or move
tags.

The secret-free `verify` job installs pinned Node 24.18.0 and runs contract,
Swift, and unsigned Xcode checks. The `release` job creates a temporary
Keychain, signs and notarizes the DMG, generates the signed appcast and
`release-manifest.json`, creates or reuses the GitHub draft, and stages exact
assets. It publishes R2 objects and the appcast before making the draft public
last.

## Release Asset Contract

GitHub Release assets are exactly:

- `SwitchTab-<version>-<build>.dmg`
- `SwitchTab-<version>-<build>.dmg.sha256`
- `release-manifest.json`

The canonical DMG is shared by the Sparkle appcast, GitHub Release, and Homebrew
Cask. It is not rebuilt for each channel. The `homebrew_release` dispatch
payload contains only `repository` and `tag`; the tap downloads and validates
`release-manifest.json` from the public GitHub Release before rendering its
Cask change.

## Recovery

Recover an existing tag through `workflow_dispatch` only after checking that no
active run owns it and that the annotated tag resolves to the intended commit:

```bash
gh workflow run release.yml --ref main -f tag=v1.0.1
```

Do not blindly dispatch a full rebuild after immutable DMG or checksum assets
have been published. Inspect the existing run, GitHub Release, and public
assets first. Prefer rerunning only the failed job or notification path; a new
notarized build may differ and immutable publication rejects replacement bytes.

If R2 publishing succeeds but final GitHub publication fails, verify the public
DMG against its checksum, inspect the matching GitHub draft, and publish that
draft after resolving the failure. Do not rebuild or retag the release.

If publication fails before the GitHub Release becomes public, resolve the
cause and rerun the failed `release` job. The existing draft and byte-idempotent
asset rules make that narrow rerun safe.

If `notify` fails after the release is public, use **Re-run failed jobs** to
rerun only `notify`. A notify-only rerun does not rebuild, sign, notarize, or
replace public assets. As a manual fallback, securely read a short-lived token
with `Contents: Read & write` access only to `sonim1/homebrew-tap`:

```bash
(
set -euo pipefail
release_tag=v1.2.3
trap 'unset TAP_GH_TOKEN' EXIT HUP INT TERM
read -r -s -p "Temporary tap dispatch token: " TAP_GH_TOKEN
printf '\n'
export TAP_GH_TOKEN
set +e
scripts/dispatch-homebrew-update.sh "$release_tag"
dispatch_status=$?
set -e
unset TAP_GH_TOKEN
trap - EXIT HUP INT TERM
exit "$dispatch_status"
)
```

## Immutability Rules

- Versioned DMG and checksum objects are immutable.
- A rerun with byte-identical assets is verification-only and safe.
- Different bytes under an existing versioned name stop the release.
- The mutable appcast is updated only when its numeric Sparkle build version is
  newer than the authoritative R2 feed.
- Appcast publication uses an R2 ETag precondition so an older run cannot roll
  the feed back.
- Do not delete or recreate a release tag during recovery.
- Do not run local and CI publishers for the same tag.

See [Update hosting](update-hosting.md) for guarded recovery tagging and the
complete local publishing fallback.
