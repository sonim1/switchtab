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
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.app/appcast.xml" \
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
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.app/appcast.xml" \
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
`https://updates.switchtab.app/appcast.xml`. The feed and release artifacts are
hosted in the `switchtab-updates` Cloudflare R2 bucket through the
`updates.switchtab.app` custom domain.

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
`https://updates.switchtab.app/appcast.xml` over HTTPS. A 404 is expected before
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

With `gh auth status` and Cloudflare authentication working, the local release
flow is:

```bash
scripts/release-local.sh
scripts/generate-appcast.sh
scripts/generate-release-manifest.sh v1.2.3
git tag -a v1.2.3 -m "SwitchTab 1.2.3"
git push origin v1.2.3
# Only when the tag-triggered CI run is disabled or cancelled:
scripts/publish-release.sh v1.2.3
```

`release-local.sh` builds, signs, notarizes, and staples the DMG.
`generate-appcast.sh` signs the appcast with the local Keychain key.
`generate-release-manifest.sh v<MARKETING_VERSION>` binds that exact DMG and
checksum to the release tag, repository, and current commit for Homebrew.
`publish-release.sh v<MARKETING_VERSION>` validates the exact tag, requires its
commit to be on `origin/main`, and requires the generated manifest.
It calls `publish-update.sh` internally to publish R2 objects; do not normally
call that child script directly.
The draft is created or reused first, exact assets are staged, R2 and the
appcast are published, and the draft is made public last.

Choose one publisher for a tag. When the GitHub release workflow is enabled,
pushing the tag starts CI and that run owns publication. Run the local publisher
only after confirming the tag-triggered run is disabled or cancelled, or during
documented recovery when no active CI run owns the tag.
Never race local and CI publication.

### Cloudflare publishing credentials

Release publishing uses one narrowly scoped credential surface:

- `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` are R2 S3-compatible Object
  Read & Write credentials scoped to `switchtab-updates`. The release script
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

Create a GitHub `release` Environment under repository settings and enable
required reviewer protection. Store the Apple, Sparkle, and R2 production
secrets there, along with the protected `TAP_GITHUB_APP_PRIVATE_KEY` secret and
the `TAP_GITHUB_APP_ID` variable. Both the `release` and `notify` jobs request
approval because both use this Environment sequentially. A notify-only rerun
can request approval again.

Both jobs use the same Environment, so Environment secrets are available to
both jobs after approval. The workflow YAML references and injects Apple,
Sparkle, and R2 secrets only into `release` steps, and references and injects
the tap App private key only into `notify`. That is a property of the reviewed
workflow, not an Environment-level availability boundary; true secret-availability
isolation requires separate Environments.

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
maintainers. Before every release, update the Xcode `MARKETING_VERSION` and
strictly increase `CURRENT_PROJECT_VERSION`; the build version must contain one
to three numeric components and must never decrease or be reused. Create an
annotated tag whose version exactly matches `MARKETING_VERSION`, then push it:

```bash
git tag -a v1.2.3 -m "SwitchTab 1.2.3"
git push origin v1.2.3
```

The workflow accepts only exact `refs/tags/v<version>` references, checks that
the tag commit is on `origin/main`, and follows this exact flow:

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

The canonical `SwitchTab-<version>-<build>.dmg` is shared by the Sparkle
appcast, GitHub Release, and Homebrew Cask; it is not rebuilt separately for
each channel. The protected `notify` job runs only after public publication and
asks the tap to render its Cask change, open a pull request, run CI, and
auto-merge after the protected checks pass.

All tags share one release concurrency group, and the appcast update itself
uses an R2 ETag precondition so an older run cannot roll the feed back. Manual
workflow dispatch is recovery-only and must name an existing version tag; it
does not create or move tags.

### Recovery and immutability

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
dependent `notify` job proceeds through its own approval. Do not delete or
recreate the tag, and do not rerun the full workflow unnecessarily.

If `notify` fails after the release is already public, use **Re-run failed
jobs** in GitHub Actions to rerun only the failed `notify` job. A notify-only
rerun can request approval again, but it does not rebuild, sign, notarize, or
replace public assets. As a manual fallback, provide a short-lived token with
`Contents: Read & write` access only to `sonim1/homebrew-tap` without putting
the token in shell history:

```bash
read -r -s -p "Temporary tap dispatch token: " TAP_GH_TOKEN
printf '\n'
export TAP_GH_TOKEN
scripts/dispatch-homebrew-update.sh v1.2.3
unset TAP_GH_TOKEN
```

The fallback sends the same `homebrew_release` event and does not alter the
already-public release.
