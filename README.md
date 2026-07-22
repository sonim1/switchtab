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

`.env.release.local` is ignored by Git. Fill in the public settings and local
credential placeholders without committing the file. For the one-time hosting
setup, authenticate with `node_modules/.bin/wrangler login` or use a separate,
broader setup credential. Set `CLOUDFLARE_ACCOUNT_ID` and
`CLOUDFLARE_ZONE_ID`, then run:

```bash
scripts/setup-update-hosting.sh
```

The setup script creates the bucket or custom domain only when Wrangler proves
that resource is absent. It otherwise validates the existing domain, requires
HTTPS with TLS 1.2 or later, fails closed on ambiguous errors, and never deletes
resources. Wait for the custom domain to become available, then verify
`https://updates.switchtab.app/appcast.xml` over HTTPS. A 404 is expected before
the first release.

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
git tag -a v1.2.3 -m "SwitchTab 1.2.3"
git push origin v1.2.3
# Only when the tag-triggered CI run is disabled or cancelled:
scripts/publish-release.sh v1.2.3
```

`release-local.sh` builds, signs, notarizes, and staples the DMG.
`generate-appcast.sh` signs the appcast with the local Keychain key.
`publish-release.sh v<MARKETING_VERSION>` validates the exact tag, uploads the
R2 artifacts, and publishes the matching GitHub draft release last. The tag
commit must already be on `origin/main`. It calls `publish-update.sh` internally
to publish R2 objects; do not normally call that child script directly.

Choose one publisher for a tag. When the GitHub release workflow is enabled,
pushing the tag starts CI and that run owns publication. Run the local publisher
only after confirming the tag-triggered run is disabled or cancelled, or during
documented recovery when no active CI run owns the tag. Never race local and CI
publication.

### Cloudflare publishing credentials

Release publishing deliberately uses two narrowly scoped credential surfaces:

- `CLOUDFLARE_API_TOKEN` is a regular Cloudflare API token scoped to
  **Workers R2 Storage Bucket Item Write** for the existing
  `switchtab-updates` bucket. Wrangler uses it for the mutable `appcast.xml`.
  It needs no DNS or custom-domain permissions in CI.
- `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` are R2 S3-compatible Object
  Read & Write credentials scoped to `switchtab-updates`. The release script
  uses them for atomic `If-None-Match: *` writes of the immutable DMG and
  checksum.

An R2 Object Read & Write S3 credential is not a replacement for the regular
Cloudflare API token used by Wrangler. Conversely, do not give CI the broader
zone, DNS, custom-domain, or account-administration credential used for initial
hosting setup. See Cloudflare's official [R2 authentication
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
- `CLOUDFLARE_API_TOKEN`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`

Set non-secret values directly, and let `gh` read secrets from a prompt or a
file rather than placing secret text in shell history:

```bash
gh variable set DEVELOPER_ID_APPLICATION --body "Developer ID Application: Your Name (TEAMID)"
gh variable set SPARKLE_PUBLIC_ED_KEY --body "your-public-ed25519-key"
gh variable set CLOUDFLARE_ACCOUNT_ID --body "your-account-id"

gh secret set APPLE_CERTIFICATE_PASSWORD
gh secret set APPLE_NOTARY_KEY_ID
gh secret set APPLE_NOTARY_ISSUER_ID
gh secret set CLOUDFLARE_API_TOKEN
gh secret set R2_ACCESS_KEY_ID
gh secret set R2_SECRET_ACCESS_KEY
```

Export transport values only into a permission-restricted temporary directory.
For example, Base64-encode the `.p12` and `.p8` files directly into `gh`, and
export the Sparkle key with `generate_keys -x` before uploading it:

```bash
release_secret_dir="$(mktemp -d)"
chmod 700 "$release_secret_dir"
/path/to/Sparkle/bin/generate_keys --account ed25519 -x "$release_secret_dir/sparkle-private-key"
gh secret set SPARKLE_PRIVATE_ED_KEY < "$release_secret_dir/sparkle-private-key"
openssl base64 -A -in /path/to/certificate.p12 | gh secret set APPLE_CERTIFICATE_P12_BASE64
openssl base64 -A -in /path/to/AuthKey.p8 | gh secret set APPLE_NOTARY_KEY_P8_BASE64
rm -f "$release_secret_dir/sparkle-private-key"
rmdir "$release_secret_dir"
```

Replace the example paths with your own temporary inputs. Base64 is transport
encoding, not encryption. Never commit the `.p12`, `.p8`, exported Sparkle
private key, or decoded copies, and remove temporary exports immediately after
the secrets are registered.

### Tags and release execution

Protect creation and updates of `v*` tags with a GitHub ruleset restricted to
maintainers. Create an annotated tag whose version exactly matches the Xcode
`MARKETING_VERSION`, then push it:

```bash
git tag -a v1.2.3 -m "SwitchTab 1.2.3"
git push origin v1.2.3
```

The workflow accepts only exact `refs/tags/v<version>` references, checks that
the tag commit is on `origin/main`, runs the contract and Swift tests, creates a
temporary Keychain, signs and notarizes the DMG, generates the signed appcast,
publishes to R2, and publishes the GitHub draft release last. Manual workflow
dispatch is recovery-only and must name an existing version tag; it does not
create or move tags.

### Recovery and immutability

Versioned DMG and checksum objects are immutable. Re-running a release with the
same bytes is safe; different bytes under an existing versioned name stop the
release. `appcast.xml` is mutable and is uploaded only after the immutable
objects have been written and publicly verified.

If R2 publishing succeeds but the final GitHub publication fails, verify the
public DMG against its public checksum, inspect the existing matching GitHub
draft, and publish that draft after resolving the failure. Do not rebuild or
re-tag the same release. Do not automatically delete objects or run a
destructive rollback; investigate and recover from the existing artifacts.
