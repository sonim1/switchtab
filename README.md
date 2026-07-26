# SwitchTab

Native macOS window switcher prototype for fast keyboard-first current-app window switching.

## Requirements

- macOS 14.0 or later
- Swift 6 toolchain or Xcode with Swift 5.10+

## Build and Test

Open `SwitchTab.xcodeproj` in Xcode, select the `SwitchTab` scheme, then use `Product > Build` or `Product > Test`.

SwitchTab leaves macOS Cmd+Tab app switching untouched. The app focuses on current-app window switching with Cmd+` by default, falling back to Option+Ctrl+` when macOS refuses the reserved shortcut.

This workspace can be tested with Swift Package Manager:

```bash
swift build
swift test
```

## Direct Distribution Build

The default Xcode project stays Sparkle-free for App Store-oriented builds. To
prepare or build the website/DMG distribution variant, use:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.royjen.com/appcast.xml" \
scripts/build-direct-distribution.sh
```

`SWITCHTAB_UPDATE_FEED_URL` must use `https://`.

Use `--prepare-only` to generate the patched workspace without building:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" scripts/build-direct-distribution.sh --prepare-only
```

Use `--release` to produce a signed, notarized, stapled DMG and SHA-256
checksum:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.royjen.com/appcast.xml" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_KEYCHAIN_PROFILE="switchtab-notary" \
scripts/build-direct-distribution.sh --release
```

Generated files live under `.build/direct-distribution/`. The generated project
adds Sparkle, `DIRECT_DISTRIBUTION`, and `Info.direct.plist`; the checked-in
`SwitchTab.xcodeproj` remains unchanged.

The app sources are laid out for an Xcode macOS menu bar app target at
`SwitchTab.xcodeproj`. Automated verification should include the SwiftPM build,
the SwiftPM test suite, and an Xcode Debug app build when full Xcode is
selected.

## Sparkle Update Hosting

The direct-distribution build reads its update feed from
`https://updates.switchtab.royjen.com/appcast.xml`. The feed and release artifacts are
hosted in the `switchtab` Cloudflare R2 bucket through the
`updates.switchtab.royjen.com` custom domain.

Install the repository-pinned Wrangler version and create a local release
configuration:

```bash
npm ci --ignore-scripts
cp .env.release.local.example .env.release.local
```

`.env.release.local` is ignored by Git. Fill in its public settings without
committing the file. Leave the optional setup-token line and both publishing-
secret lines commented during the one-time OAuth hosting setup so placeholder
values cannot override Wrangler authentication. Authenticate with
`node_modules/.bin/wrangler login`, then set
`CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_ZONE_ID`.

If OAuth is not used, supply a separate setup management token through an
approved secret mechanism. Keep it separate from the narrower R2 S3
credentials used only for publishing objects to the existing bucket. Run:

```bash
scripts/setup-update-hosting.sh
```

The setup script creates the bucket or custom domain only when Wrangler proves
that resource is absent. It otherwise validates the existing domain, requires
HTTPS with TLS 1.2 or later, fails closed on ambiguous errors, and never deletes
resources. Wait for the custom domain to become available, then verify
`https://updates.switchtab.royjen.com/appcast.xml` over HTTPS. A 404 is expected before
the first release.

After setup, for an intentional local publish, uncomment and fill in only the
two `R2_` publishing secrets inside the ignored `.env.release.local`, or supply
them through a safe secret mechanism. The optional regular Cloudflare token is
only for non-OAuth hosting setup and is not used by publication. CI receives
the R2 credentials from GitHub Secrets; tracked files keep all examples
commented.

### Local signing and publishing

Generate a Sparkle Ed25519 key with Sparkle's `generate_keys` tool. Keep the
private key in the macOS Keychain under account `ed25519` (or the value of
`SPARKLE_KEY_ACCOUNT`) and put only its public key in
`SPARKLE_PUBLIC_ED_KEY`. Configure the `DEVELOPER_ID_APPLICATION` identity and
store Apple notarization credentials in the local notarytool profile named by
`NOTARYTOOL_KEYCHAIN_PROFILE`.

The normal release path is automated from pull-request CI through the merge to
`main`; see **Tags and release execution**. Do not manually create or push a
release tag during that path, and do not run a local publisher alongside CI.

If the automatic main workflow is unavailable and a maintainer deliberately
starts the tag path, use this guarded block from the authoritative remote state.
It fails closed unless tracked files and all non-ignored untracked files are
clean, `HEAD` is exactly the freshly fetched `origin/main`, and the annotated
tag resolves to that same commit:

```bash
(
set -euo pipefail
release_tag=v1.2.3
git fetch --prune --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
git fetch --prune --tags origin
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
release_commit="$(git rev-parse HEAD)"
git tag -a "$release_tag" "$release_commit" -m "SwitchTab ${release_tag#v}"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git rev-parse "refs/tags/$release_tag^{commit}")" = "$release_commit"
git push origin "refs/tags/$release_tag:refs/tags/$release_tag"
)
```

The normal CI handoff for this guarded path stops after the tag push; CI owns
the release build and public GitHub/Sparkle publication.

Use the local fallback only after confirming that automated release CI is
disabled or cancelled and that no active run owns the tag. Run this complete
block from the same tagged checkout. Its prompt securely reads a short-lived
tap token without placing it in shell history:

```bash
(
set -euo pipefail
release_tag=v1.2.3
git fetch --prune --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
git fetch --prune --tags origin
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git rev-parse "refs/tags/$release_tag^{commit}")" = "$(git rev-parse HEAD)"
scripts/release-local.sh
scripts/generate-appcast.sh
scripts/generate-release-manifest.sh "$release_tag"
scripts/publish-release.sh "$release_tag"
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

`release-local.sh` builds, signs, notarizes, and staples the DMG.
`generate-appcast.sh` signs the appcast with the local Keychain key, and
`generate-release-manifest.sh` binds that exact DMG and checksum to the tagged
commit. `publish-release.sh` validates the tag and manifest.
It calls `publish-update.sh` internally to publish R2 and makes the staged
GitHub draft public last. Only after that succeeds does the dispatch run. The
`homebrew_release` dispatch sends only `repository` and `tag`; the tap downloads
`release-manifest.json` from the public GitHub Release.
The draft is created or reused first, exact assets are staged, R2 and the
appcast are published, and the draft is made public last.

The generated ignored artifacts do not change source provenance.
Choose one publisher for a tag. Never race local and CI publication. If
dispatch fails, rerun the same secure token-read and dispatch commands without
rebuilding or replacing the public release.

### Cloudflare publishing credentials

Release publishing uses one narrowly scoped credential surface:

- `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` are R2 S3-compatible Object
  Read & Write credentials scoped to `switchtab`. The release script
  uses them for atomic `If-None-Match: *` writes of immutable artifacts and
  ETag-guarded `If-Match` updates of `appcast.xml`.

The optional regular `CLOUDFLARE_API_TOKEN` in the local example is only a
non-OAuth alternative for the one-time Wrangler hosting setup. Do not give CI
that broader setup token or any zone, DNS, custom-domain, or account-
administration credential. See Cloudflare's official [R2 authentication
documentation](https://developers.cloudflare.com/r2/api/tokens/) and
[conditional S3 API
documentation](https://developers.cloudflare.com/r2/api/s3/api/#conditional-operations).

## Automated GitHub Releases

The release workflow expects these GitHub repository variables:

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

Set non-secret values directly, and let `gh` read secrets from a prompt or a
file rather than placing secret text in shell history:

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
For example, Base64-encode the `.p12` and `.p8` files directly into `gh`, and
export the Sparkle key with `generate_keys -x` before uploading it:

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

Replace the example paths with your own temporary inputs. Base64 is transport
encoding, not encryption. Never commit the `.p12`, `.p8`, exported Sparkle
private key, or decoded copies, and remove temporary exports immediately after
the secrets are registered.

### Protected release environment and tap integration

Create a GitHub `release` Environment under repository settings and store the
Apple, Sparkle, and R2 production secrets there. The current automatic mode has
no required reviewer rule. Merging a release-relevant PR into `main` is the
production release authorization point, so downstream release jobs continue
without manual approval. The Environment still scopes production secrets to
jobs that explicitly reference it.

Homebrew notification is opt-in: the `notify` job runs only when the
repository-level `ENABLE_HOMEBREW_NOTIFY` variable is exactly `true`. Leave it
unset or set it to `false` to publish GitHub, Sparkle, and R2 without touching
the tap. When enabled, also store the protected `TAP_GITHUB_APP_PRIVATE_KEY`
secret and `TAP_GITHUB_APP_ID` variable in the `release` Environment. Both the
`release` and enabled `notify` jobs use this Environment sequentially and
request no approval in current mode.
A notify-only rerun does not request approval again.

Both jobs use the same Environment, so Environment secrets are available to
both jobs when each starts in current mode, not after approval. The workflow
YAML references and injects Apple, Sparkle, and R2 secrets only into `release`
steps, and references and injects the tap App private key only into `notify`.
That is a property of the reviewed workflow, not an Environment-level
availability boundary; true secret-availability isolation requires separate
Environments.

Adding required reviewers to the `release` Environment is a deliberate
alternative that changes merge-to-main releases to manual approval. Both the
`release` and enabled `notify` jobs would then pause independently, so configure
that policy only when the intentional product behavior is no longer immediate
release after merge.

The GitHub App must be installed only on `sonim1/homebrew-tap`. Grant the
installation the minimum union of permissions required by the unified release
system:

- `Administration: Read` for the tap receiver's branch-protection preflight.
- `Contents: Read & write` for repository dispatch and the tap update branch.
- `Pull requests: Read & write` for pull-request creation and auto-merge.

It does not need installation on `sonim1/switchtab`. The SwitchTab `notify`
token uses only the dispatch/contents capability, while the tap receiver token
requests all three permissions for its guarded update job.

Register the same App ID and private key in both configuration locations. The
source repository uses its protected `release` Environment for `notify`; the
tap repository uses an Actions variable and secret for its receiver workflow.
Pass the private-key file through standard input so its contents do not enter
shell history:

```bash
gh variable set --repo sonim1/switchtab ENABLE_HOMEBREW_NOTIFY --body "true"
gh variable set --env release TAP_GITHUB_APP_ID --body "your-github-app-id"
gh secret set --env release TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem

gh variable set --repo sonim1/homebrew-tap TAP_GITHUB_APP_ID --body "your-github-app-id"
gh secret set --repo sonim1/homebrew-tap TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem
```

Before enabling releases, configure `sonim1/homebrew-tap` to accept the
`homebrew_release` repository-dispatch event, enable pull-request auto-merge,
and protect its default branch in strict mode with the exact required checks
`contracts` and `homebrew`. These settings and the source `release` Environment
are administrative prerequisites; the release scripts do not mutate them.
The secret-free `verify` job does not use the protected Environment and receives
no production secrets.

### Tags and release execution

Protect creation and updates of `v*` tags with a GitHub ruleset restricted to
maintainers. Every pull request runs secret-free CI. A release-relevant PR must
strictly increase Xcode `MARKETING_VERSION` and
strictly increase `CURRENT_PROJECT_VERSION` in both app target configurations.
The build version must contain one to three numeric components and must never
decrease or be reused. A docs-only PR still runs CI, but plans `release=false`
and does not require either version bump.

After a release-relevant PR merges, the push to `main` creates or verifies the
annotated `refs/tags/v<MARKETING_VERSION>` on that exact merge commit and pushes
only that tag ref. Because the tag is pushed with the repository
`GITHUB_TOKEN`, GitHub's recursion suppression does not start another workflow
from the tag event. The automatic workflow therefore explicitly dispatches
`release.yml` with that existing tag.

Both automatic planning/tagging and downstream release execution use fixed,
non-cancelling, max-queued concurrency groups. Rapid main merges and their
release dispatches are serialized and preserved instead of replacing an older
queued run.

The guarded normal CI block under **Local signing and publishing** remains the
operator recovery path for pushing a fully qualified ref for the release tag;
do not use a shorter tag command.

The workflow accepts only exact `refs/tags/v<version>` references, checks that
the tag commit is on `origin/main`, and follows this exact flow:

```text
PR CI -> main merge -> exact annotated tag -> explicit release dispatch -> secret-free `verify` -> protected signed `release` -> public GitHub/Sparkle publication -> protected `notify` -> tap PR/CI/auto-merge
```

A deliberately maintainer-pushed recovery tag enters the same downstream flow:

```text
tag push -> secret-free `verify` -> protected signed `release` -> public GitHub/Sparkle publication -> protected `notify` -> tap PR/CI/auto-merge
```

The secret-free `verify` job installs the pinned Node 24.18.0 runtime and runs
the contract, Swift, and unsigned Xcode checks. After approval, `release`
creates a temporary Keychain, signs and notarizes the DMG, generates the signed
appcast and `release-manifest.json`, creates or reuses the GitHub draft, and
stages its exact assets. It then publishes R2 objects and the appcast before
making the draft public last. The manifest is both a GitHub Release asset and
the tap package-update contract. The `homebrew_release` dispatch payload
consists only of `repository` and `tag`. After receiving those identifiers,
`sonim1/homebrew-tap` downloads `release-manifest.json` from the public GitHub
Release, validates it, renders the Cask change, and opens the tap pull request.

The GitHub Release assets are exactly
`SwitchTab-<version>-<build>.dmg`,
`SwitchTab-<version>-<build>.dmg.sha256`, and `release-manifest.json`. The
canonical DMG is shared by the Sparkle appcast, GitHub Release, and Homebrew
Cask; it is not rebuilt separately for each channel. When
`ENABLE_HOMEBREW_NOTIFY=true`, the protected `notify` job runs only after public
publication and asks the tap to render its Cask change, open a pull request,
run CI, and auto-merge after the protected checks pass.

The appcast update uses an R2 ETag precondition so an older run cannot roll the
feed back. Manual workflow dispatch is recovery-only and must name an existing
version tag; it does not create or move tags.

### Recovery and immutability

Recover an existing tag through `workflow_dispatch` only after checking that no
active run owns it and that the annotated tag resolves to the intended commit:

```bash
gh workflow run release.yml --ref main -f tag=v1.0.1
```

Do not blindly dispatch a full rebuild after immutable DMG or checksum assets
have been published. Inspect the existing run, GitHub Release, and public assets
first, then rerun only the failed job or notification path when possible; a new
notarized build may differ and immutable publication will reject replacement
bytes.

Versioned DMG and checksum objects are immutable. Re-running a release with the
same bytes is safe; different bytes under an existing versioned name stop the
release. The mutable appcast is uploaded last and only when its numeric Sparkle
build version is newer than the authoritative R2 feed. A byte-identical rerun
is verification-only; a lower version or different bytes for the same version
stop the release. `appcast.xml` is uploaded only after the immutable objects
have been written and publicly verified.

If R2 publishing succeeds but the final GitHub publication fails, verify the
public DMG against its public checksum, inspect the existing matching GitHub
draft, and publish that draft after resolving the failure.
Do not rebuild or re-tag the same release. Do not automatically delete objects
or run a destructive rollback; investigate and recover from the existing
artifacts.

If release publication fails before the GitHub Release becomes public, resolve
the cause and rerun the failed `release` job. The existing draft and
byte-idempotent asset rules make that narrow rerun safe; after publication, the
dependent `notify` job runs automatically when enabled. Do not delete or
recreate the tag, and do not rerun the full workflow unnecessarily.

If `notify` fails after the release is already public, use **Re-run failed
jobs** in GitHub Actions to rerun only the failed `notify` job. A notify-only
rerun does not request approval again in current automatic mode, and it does not
rebuild, sign, notarize, or replace public assets. As a manual fallback, provide
a short-lived token with `Contents: Read & write` access only to
`sonim1/homebrew-tap` without putting the token in shell history:

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

The subshell prevents the token from persisting in the caller. The cleanup trap
covers normal exit, command failure, interruption, and termination, while the
explicit status capture preserves the dispatch result. The fallback sends the
same `homebrew_release` event and does not alter the already-public release.
