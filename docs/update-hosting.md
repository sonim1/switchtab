# Update Hosting

The direct-distribution build reads its Sparkle feed from
`https://updates.switchtab.royjen.com/appcast.xml`. The feed and release
artifacts are hosted in the `switchtab` Cloudflare R2 bucket through the
`updates.switchtab.royjen.com` custom domain.

## One-Time Cloudflare Setup

Install the repository-pinned Wrangler version and create a local release
configuration:

```bash
npm ci --ignore-scripts
cp .env.release.local.example .env.release.local
```

`.env.release.local` is ignored by Git. Fill in its public settings without
committing the file. Leave the optional setup-token line and both publishing
secret lines commented during OAuth setup so placeholder values cannot
override Wrangler authentication.

Authenticate with `node_modules/.bin/wrangler login`, then set
`CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_ZONE_ID`. If OAuth is not used, supply
a separate setup management token through an approved secret mechanism. Keep
that token separate from the narrower R2 credentials used to publish objects
to the existing bucket.

Run:

```bash
scripts/setup-update-hosting.sh
```

The setup script creates the bucket or custom domain only when Wrangler proves
that the resource is absent. It otherwise validates the existing domain,
requires HTTPS with TLS 1.2 or later, fails closed on ambiguous errors, and
never deletes resources.

Wait for the custom domain to become available, then verify
`https://updates.switchtab.royjen.com/appcast.xml` over HTTPS. A 404 is expected
before the first release.

## Publishing Credentials

Release publishing uses one narrowly scoped credential surface:

- `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` are R2 S3-compatible Object
  Read & Write credentials scoped to the `switchtab` bucket. The release script
  uses them for atomic `If-None-Match: *` writes of immutable artifacts and
  ETag-guarded `If-Match` updates of `appcast.xml`.

The optional `CLOUDFLARE_API_TOKEN` in the local example is only a non-OAuth
alternative for the one-time hosting setup. Do not give CI that broader setup
token or any zone, DNS, custom-domain, or account-administration credential.

For an intentional local publish, uncomment and fill in only the two `R2_`
publishing secrets inside the ignored `.env.release.local`, or supply them
through a safe secret mechanism. CI receives the R2 credentials from GitHub
Secrets; tracked files keep all examples commented.

See Cloudflare's [R2 authentication documentation](https://developers.cloudflare.com/r2/api/tokens/)
and [conditional S3 API documentation](https://developers.cloudflare.com/r2/api/s3/api/#conditional-operations).

## Local Signing Prerequisites

Generate a Sparkle Ed25519 key with Sparkle's `generate_keys` tool. Keep the
private key in the macOS Keychain under account `ed25519`, or the value of
`SPARKLE_KEY_ACCOUNT`, and put only its public key in
`SPARKLE_PUBLIC_ED_KEY`.

Configure the `DEVELOPER_ID_APPLICATION` identity and store Apple notarization
credentials in the local notarytool profile named by
`NOTARYTOOL_KEYCHAIN_PROFILE`.

The normal release path is automated from pull-request CI through the merge to
`main`. Do not manually create or push a release tag during that path, and do
not run a local publisher alongside CI.

## Guarded Recovery Tag

If automatic main workflow tagging is unavailable and a maintainer deliberately
starts the tag path, use this guarded block from authoritative remote state. It
fails unless tracked files and non-ignored untracked files are clean, `HEAD` is
the freshly fetched `origin/main`, and the annotated tag resolves to that same
commit:

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

After the tag push, CI owns the release build and public GitHub/Sparkle
publication.

## Local Publishing Fallback

Use the local fallback only after confirming automated release CI is disabled
or cancelled and no active run owns the tag. Run the complete block from the
same tagged checkout. The prompt reads the temporary tap token without placing
it in shell history:

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
commit. `publish-release.sh` validates the tag and manifest, calls
`publish-update.sh` to publish R2, and makes the staged GitHub draft public
last. Only then does the Homebrew dispatch run.

Choose one publisher for a tag. Never race local and CI publication. If the
dispatch fails, rerun only the secure token read and dispatch commands without
rebuilding or replacing the public release.

## Publication Safety

The draft is created or reused first, exact assets are staged, R2 and the
appcast are published, and the GitHub draft is made public last. Generated
ignored artifacts do not change source provenance.

Versioned DMG and checksum objects are immutable. The mutable appcast is
uploaded only when its numeric Sparkle build version is newer than the
authoritative R2 feed, and an R2 ETag precondition prevents an older run from
rolling the feed back. See [Release workflow](release-workflow.md) for the full
asset contract and recovery rules.
