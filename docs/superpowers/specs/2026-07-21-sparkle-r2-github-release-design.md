# Sparkle, Cloudflare R2, and GitHub Release Automation Design

**Date:** 2026-07-21

## Goal

Create a reproducible release path for the direct-distribution build of
SwitchTab. A maintainer pushes a version tag such as `v1.0`, and GitHub Actions
builds, signs, notarizes, and staples the DMG, generates a signed Sparkle
appcast, publishes the update files to Cloudflare R2, and publishes a GitHub
Release containing the same DMG and checksum.

The same release operations must remain runnable locally through repository
scripts. GitHub Actions should supply credentials and orchestrate those scripts,
not contain a second implementation of the release logic.

## Current Context

- `scripts/build-direct-distribution.sh --release` already builds, signs,
  notarizes, staples, and checksums `SwitchTab.dmg`.
- `scripts/release-local.sh` loads untracked local configuration and delegates to
  the direct-distribution release script.
- The direct build embeds `https://updates.switchtab.app/appcast.xml` and the
  configured Sparkle EdDSA public key.
- Sparkle is pinned to the official 2.9.4 commit.
- There is no existing GitHub Actions workflow or Cloudflare configuration in
  the repository.
- The initial R2 bucket is `switchtab-updates`, and its public custom domain is
  `updates.switchtab.app`.

## Decision and Alternatives

Use small, purpose-specific shell scripts plus one GitHub Actions workflow.
This keeps local and CI behavior aligned, gives each destructive or
credential-bearing step a narrow boundary, and permits fixture-based tests.

Two alternatives were rejected:

1. Putting every command directly in workflow YAML would duplicate local
   release behavior and make failures harder to reproduce.
2. Expanding `release-local.sh` into one large local-and-CI script would mix
   one-time infrastructure setup, artifact creation, and public publishing.
   Those operations have different credentials and retry semantics.

## Components

### Existing artifact builder

`scripts/build-direct-distribution.sh --release` remains responsible for the
Apple release artifact. Its output contract is:

- `.build/direct-distribution/release/SwitchTab.dmg`
- `.build/direct-distribution/release/SwitchTab.dmg.sha256`
- a signed app under the direct-distribution DerivedData directory

The existing `scripts/release-local.sh` behavior remains compatible. Local
maintainers can run it first and then invoke the appcast and publishing scripts.

### `scripts/generate-appcast.sh`

This script consumes the notarized DMG and creates a deterministic staging
directory under `.build/direct-distribution/updates/`.

It will:

1. Read the marketing version and build number from the built app.
2. Verify the DMG checksum, code signature, stapling ticket, and Gatekeeper
   acceptance before signing update metadata.
3. Rename the staged artifact to
   `SwitchTab-<marketing-version>-<build-number>.dmg`, preventing releases with
   different build numbers from sharing an object name.
4. Verify that the Sparkle public key embedded in the app matches the configured
   public key.
5. Run Sparkle 2.9.4's `generate_appcast` from the binary artifact resolved by
   the existing pinned Swift package checkout, with the download prefix
   `https://updates.switchtab.app/`. CI does not download a second unpinned copy
   of Sparkle tooling.
6. Validate that `appcast.xml` is well-formed, references the versioned DMG, and
   contains a non-empty EdDSA signature.

Local execution uses the Sparkle private key stored in the macOS Keychain under
the configured account, defaulting to `ed25519`. CI execution passes the private
key to `generate_appcast` through standard input with `--ed-key-file -`, as
recommended by Sparkle. The private key is never accepted as a command-line
argument or printed.

Only the newest full DMG is included in the initial appcast. Delta generation
and historical appcast entries are outside this first implementation because a
clean CI runner has no trusted prior artifacts. They can be added later without
changing the publishing interface.

### `scripts/setup-update-hosting.sh`

This is a one-time, locally initiated infrastructure script. Wrangler is an
exact development dependency recorded in `package.json` and `package-lock.json`;
the script uses that locked Wrangler 4.x executable to:

1. Verify the active Cloudflare identity.
2. Create the `switchtab-updates` R2 bucket if it does not already exist.
3. Attach `updates.switchtab.app` as the bucket custom domain in the configured
   Cloudflare zone with TLS 1.2 or newer.
4. Query the bucket and custom-domain state again and print a concise summary.

The operation is idempotent: an existing matching bucket or domain is accepted;
an existing conflicting domain or inaccessible bucket fails without deleting or
replacing anything. The script does not create API tokens and never writes
credentials into the repository. Interactive local use relies on `wrangler
login`; CI does not run this setup script.

### `scripts/publish-update.sh`

This script publishes already generated artifacts to the existing R2 bucket.
It requires bucket-scoped R2 S3 Object Read & Write credentials through
`R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY`, plus
`CLOUDFLARE_ACCOUNT_ID` for the R2 endpoint.

Publishing order protects existing clients:

1. Upload the versioned DMG with
   `application/x-apple-diskimage`.
2. Upload its SHA-256 checksum as text.
3. Verify both public objects through `https://updates.switchtab.app/` and
   compare the downloaded DMG checksum.
4. Upload `appcast.xml` last with an XML content type and an R2 ETag
   precondition.
5. Fetch and validate the public appcast and its enclosure URL.

Versioned DMGs are immutable. If the public object already exists with the same
checksum, the upload is skipped; if its bytes differ, the script fails. The
mutable `appcast.xml` is the only object intentionally replaced. Its
`sparkle:version` must contain one to three numeric components and must be
strictly newer than the authoritative R2 feed. A byte-identical same-version
rerun is verification-only; a lower version or different same-version bytes
fail closed. `If-None-Match` and ETag-based `If-Match` writes close the race
between reading and replacing the feed.

### `scripts/publish-release.sh`

This script coordinates the public GitHub Release and R2 publication. It:

1. Requires a `v<marketing-version>` tag and verifies that the tag points to the
   checked-out commit and is reachable from `origin/main`.
2. Creates or reuses a draft GitHub Release for that tag.
3. Uploads the versioned DMG and checksum to the draft.
4. Calls `scripts/publish-update.sh`.
5. Publishes the GitHub draft only after R2 publication succeeds.

The script uses the preinstalled GitHub CLI and `GH_TOKEN`. If a rerun finds a
release or asset with the expected checksum, it treats it as complete. It fails
instead of silently replacing a different public asset. Release notes are
generated from GitHub's commits for the tag.

If R2 succeeds but the final GitHub publish call fails, the Sparkle update is
already valid and downloadable, and the GitHub draft still contains the exact
published artifacts. The recovery action is to verify the public R2 checksum
and publish that existing draft; rebuilding the same tag is not allowed because
Apple signing timestamps can produce different DMG bytes. Automatic rollback
of a published appcast is intentionally excluded because restoring an
unverified prior feed would be less safe than an explicit maintainer action.

### `.github/workflows/release.yml`

The workflow triggers on pushes of `v*` tags. It also supports manual execution
for an existing tag through `workflow_dispatch`; it does not create version
tags from arbitrary branch state. A partial release that has already created
public artifacts follows the explicit recovery rule above instead of rebuilding
the tag.

The single release job runs on a pinned macOS runner image and has only
`contents: write` repository permission. Its stages are:

1. Check out the complete tag history with the official checkout action pinned
   to a full commit SHA.
2. Install the exact locked Wrangler dependency with `npm ci`.
3. Verify that the tag version equals `MARKETING_VERSION`, validate the numeric
   `CURRENT_PROJECT_VERSION`, and confirm that the commit is reachable from
   `main`.
4. Run Swift tests and the existing unsigned Debug build checks.
5. Generate a random, per-run temporary Keychain password and import the
   Developer ID Application
   certificate from GitHub Secrets.
6. Store App Store Connect API-key credentials in that temporary Keychain as a
   `notarytool` profile.
7. Call `scripts/build-direct-distribution.sh --release`.
8. Call `scripts/generate-appcast.sh` using the Sparkle private key through
   standard input.
9. Call `scripts/publish-release.sh` using `GITHUB_TOKEN` and bucket-scoped R2
   S3 credentials.
10. Delete temporary key and certificate files and the temporary Keychain in an
   `always()` cleanup step.

Release jobs share a repository-wide concurrency group. Because queue order is
not an integrity guarantee, the R2 appcast update also enforces monotonic
versions with an ETag precondition. Pull-request workflows never receive
release secrets. Tag rules should restrict creation of `v*` tags to
maintainers.

## Configuration and Secrets

Tracked defaults and public values will be documented in
`.env.release.local.example` and `README.md`. Local overrides remain in the
ignored `.env.release.local` file.

GitHub repository variables:

- `DEVELOPER_ID_APPLICATION`
- `SPARKLE_PUBLIC_ED_KEY`
- `CLOUDFLARE_ACCOUNT_ID`

GitHub repository secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PRIVATE_ED_KEY`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`

The non-secret local hosting configuration includes
`CLOUDFLARE_ZONE_ID`, `R2_BUCKET_NAME=switchtab-updates`, and
`UPDATE_DOMAIN=updates.switchtab.app`. The implementation will not treat the
Cloudflare account or zone identifiers as secrets.

The R2 S3 credential is limited to reading and writing objects in the existing
bucket. CI receives no DNS or custom-domain permissions because hosting setup
remains a separate local operation. `GITHUB_TOKEN` is generated per job and
receives only `contents: write`.

No secret is committed, included in an artifact, passed as a command-line
value, or printed. Shell tracing is disabled in all credential-bearing steps.

## Error Handling and Retry Rules

- Invalid arguments or configuration exit with status 64.
- Missing required local files exit with status 66.
- Apple, Sparkle, `curl`, and GitHub CLI failures propagate as a
  non-zero workflow result.
- Public publishing never begins until tests, signing, notarization, stapling,
  checksums, appcast parsing, and tag/version validation succeed.
- The appcast is uploaded only after its referenced DMG is publicly readable.
- A rerun may reuse byte-identical immutable artifacts, but any checksum
  conflict stops the release for manual investigation.
- Infrastructure setup never deletes a bucket, domain, object, DNS record, or
  token.

## Testing

Each new script receives a fixture-based shell contract test under
`scripts/tests/`. Fake executables are injected through `PATH` so tests do not
access the real Keychain, Apple services, Cloudflare, GitHub, DNS, or the
network.

The tests cover:

- required configuration and missing-file failures;
- versioned artifact naming and tag/version mismatch rejection;
- local Keychain and CI standard-input Sparkle signing modes;
- signature and checksum validation failures;
- idempotent bucket/domain setup and conflict handling;
- R2 upload order, MIME types, immutable-object checks, and appcast-last
  publication, including reversed tag completion and conditional-write races;
- GitHub draft creation, asset reuse, final publication, and rerun behavior;
- propagation of every external command failure;
- cleanup behavior for temporary CI credentials; and
- workflow syntax plus its trigger, permission, concurrency, and secret wiring.

Final verification includes all shell contract tests, the 18 Swift tests, an
unsigned Xcode Debug build, and a dry fixture run of the full workflow command
sequence. Live Cloudflare setup or public release execution requires a separate
explicit maintainer invocation after the implementation is committed.

## Operator Flow

One-time setup:

```text
scripts/setup-update-hosting.sh
```

Local release:

```text
scripts/release-local.sh
scripts/generate-appcast.sh
scripts/publish-release.sh v1.0
```

Automated release:

```text
git tag -a v1.0 -m "SwitchTab 1.0"
git push origin v1.0
```

The tag push starts the GitHub Actions release workflow. A successful run ends
with matching artifacts at GitHub Releases and
`https://updates.switchtab.app/`, with the public appcast pointing to the
versioned R2 DMG.

## References

- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [Sparkle security and reliability notes](https://sparkle-project.org/documentation/security-and-reliability/)
- [Cloudflare Wrangler R2 commands](https://developers.cloudflare.com/workers/wrangler/commands/r2/)
- [Cloudflare R2 public buckets and custom domains](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- [GitHub Actions macOS signing certificate guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub Actions secrets guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
- [GitHub `GITHUB_TOKEN` guidance](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)
