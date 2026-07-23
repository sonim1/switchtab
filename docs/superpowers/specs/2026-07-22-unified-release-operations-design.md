# Unified Release Operations for SwitchTab and UpdateBar

**Date:** 2026-07-22

## Goal

Give SwitchTab and UpdateBar the same reliable release experience while keeping
their source repositories, version numbers, tags, and product-specific build
logic independent.

A release tag in either application repository must:

1. validate and test the tagged source;
2. pause at a protected GitHub `release` environment for maintainer approval;
3. build, Developer ID sign, notarize, and publish the product's artifacts;
4. publish a signed Sparkle update for the macOS app;
5. publish a GitHub Release containing the canonical public artifacts; and
6. open an automatically mergeable update PR in `sonim1/homebrew-tap`.

The integration standardizes contracts and operator behavior. It does not move
the two products into a monorepo or create a central build service.

## Current Context

### SwitchTab

- The repository already has a tag-triggered release workflow.
- It produces a Developer ID-signed, notarized DMG.
- Sparkle 2.9.4 is pinned and the signed appcast is published to Cloudflare R2
  at `https://updates.switchtab.app/appcast.xml`.
- It does not yet publish a Homebrew Cask update.

### UpdateBar

- The repository publishes CLI archives, a TUI package, and a macOS menu app.
- Its Homebrew metadata is manually copied to `sonim1/homebrew-tap` as
  `Formula/updatebar.rb`, `Formula/updatebar-tui.rb`, and
  `Casks/updatebar-app.rb`.
- Its macOS app is currently released as an app tar archive and has no Sparkle
  integration.
- Its signing workflow has optional credentials and an unsigned fallback. A
  public app release must instead fail closed when signing credentials are
  absent.

### Shared constraints

- Both apps use the same Apple Developer team, Developer ID Application
  certificate, and App Store Connect notarization identity.
- The products have independent release cadences and must remain releasable if
  the other source repository is unavailable.
- `sonim1.com` is a long-lived personal domain. UpdateBar can use it now and
  adopt `updatebar.app` later if product branding warrants the purchase.

## Decision

Use an **app-repository-owned release with a tap-owned packaging update**.

- Each app repository owns its tests, builds, Apple signing, notarization,
  Sparkle publication, GitHub Release, and release manifest.
- `homebrew-tap` owns the mapping from release products to Formula/Cask files,
  validation, rendering, Homebrew tests, PR creation, and auto-merge.
- Repositories share naming conventions, manifest schema, secret names, and
  GitHub Environment policy, but they do not import a mutable cross-repository
  build workflow.

This is preferred over a central release repository because Apple build logic
needs to evolve with each product's source. A central build workflow would
couple unrelated releases and make a shared workflow change capable of breaking
both apps simultaneously. The small, versioned manifest is the stable boundary
between application release logic and Homebrew packaging logic.

## Architecture

```text
SwitchTab tag                         UpdateBar tag
      |                                     |
      v                                     v
verify source + tests                 verify source + tests
      |                                     |
      +------ protected `release` approval--+
      |                                     |
      v                                     v
signed/notarized DMG                  CLI/TUI archives + signed/notarized DMG
      |                                     |
      +--> GitHub Release                    +--> GitHub Release
      +--> SwitchTab R2/Sparkle              +--> UpdateBar R2/Sparkle
      +--> release-manifest.json             +--> release-manifest.json
                       \                     /
                        v                   v
                       repository_dispatch
                                |
                                v
                      sonim1/homebrew-tap
                 validate -> render -> test -> PR
                                |
                                v
                         auto-merge when green
```

### Repository independence

Tags and versions are repository-local. A SwitchTab `v1.2.0` tag has no
relationship to an UpdateBar `v0.6.0` tag. A release job checks that its tag
matches the version embedded in that product and that the tagged commit belongs
to that repository's `main` history.

The same secret and variable names are used in both repositories so setup and
rotation instructions are identical:

GitHub repository or environment variables:

- `DEVELOPER_ID_APPLICATION`
- `SPARKLE_PUBLIC_ED_KEY`
- `CLOUDFLARE_ACCOUNT_ID`
- `TAP_GITHUB_APP_ID`

GitHub `release` environment secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PRIVATE_ED_KEY`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `TAP_GITHUB_APP_PRIVATE_KEY`

The Apple certificate and notarization credentials may contain the same values
in both repositories because the products share a team. Each application uses
its own Sparkle EdDSA key pair and bucket-scoped R2 credential, limiting the
effect of one product's update credential being compromised.

### Approval boundary

The workflow is split into two phases:

1. A secret-free verification phase validates the tag, runs tests, and performs
   unsigned build checks.
2. A `release` job references the protected GitHub Environment. Required
   reviewers approve that job before GitHub exposes production secrets. The job
   then signs, notarizes, and publishes.

Approval is therefore given after ordinary validation succeeds but before any
public artifact or update feed changes.

## Artifact Contracts

### SwitchTab

SwitchTab retains its existing canonical DMG and Sparkle feed:

- GitHub Release: versioned notarized `SwitchTab-<version>-<build>.dmg` and its
  checksum;
- Sparkle: the same DMG at `updates.switchtab.app`;
- Homebrew: new `switchtab` Cask pointing at the GitHub Release DMG.

The current R2/appcast conditional-write and monotonic-version protections stay
in place.

### UpdateBar

UpdateBar changes the macOS app distribution artifact from `.app.tar.gz` to one
canonical Developer ID-signed, notarized DMG. Sparkle officially supports DMG
updates, so the exact same bytes can be used by:

- the UpdateBar GitHub Release;
- `Casks/updatebar-app.rb`; and
- the UpdateBar Sparkle appcast.

The DMG contains the app and an `/Applications` symlink. UpdateBar CLI and TUI
artifacts remain independent Formula/source or archive packages and are not
wrapped in the app DMG.

UpdateBar pins Sparkle to the same audited official 2.9.4 commit as SwitchTab,
but uses its own EdDSA key pair and feed:

- product site namespace: `https://updatebar.sonim1.com/`;
- update origin: `https://updates.updatebar.sonim1.com/`;
- appcast: `https://updates.updatebar.sonim1.com/appcast.xml`.

The update subdomain is attached to an UpdateBar-specific R2 bucket. If
`updatebar.app` is purchased later, new website traffic may move immediately,
but the old appcast origin remains available for already-installed app
versions. A feed migration may point a later app version to a new feed only
after that version has been delivered through the old feed.

## Release Manifest

Every public GitHub Release includes `release-manifest.json`. The schema is
small and versioned:

```json
{
  "schemaVersion": 1,
  "repository": "sonim1/UpdateBar",
  "tag": "v0.6.0",
  "version": "0.6.0",
  "commit": "<full commit SHA>",
  "packages": [
    {
      "type": "formula",
      "token": "updatebar",
      "source": {
        "kind": "release-asset",
        "name": "updatebar-0.6.0-macos-arm64.tar.gz",
        "sha256": "<hex digest>"
      }
    },
    {
      "type": "cask",
      "token": "updatebar-app",
      "source": {
        "kind": "release-asset",
        "name": "UpdateBar-0.6.0.dmg",
        "sha256": "<hex digest>"
      }
    },
    {
      "type": "formula",
      "token": "updatebar-tui",
      "source": {
        "kind": "github-tag-archive",
        "sha256": "<hex digest>"
      }
    }
  ]
}
```

SwitchTab publishes the same structure with one `cask` package. UpdateBar adds
only the packages consumed by the three existing Homebrew definitions. The CLI
continues to use its macOS ARM64 release archive. The TUI continues to build
from the GitHub tag archive. `homebrew-tap` constructs both URL forms from the
allowlisted repository and tag; the manifest cannot supply an arbitrary URL.

The manifest contains logical tokens, never target filesystem paths or Ruby
templates. The tap repository owns this allowlist:

| Source repository | Token | Tap destination |
| --- | --- | --- |
| `sonim1/switchtab` | `switchtab` | `Casks/switchtab.rb` |
| `sonim1/UpdateBar` | `updatebar` | `Formula/updatebar.rb` |
| `sonim1/UpdateBar` | `updatebar-app` | `Casks/updatebar-app.rb` |
| `sonim1/UpdateBar` | `updatebar-tui` | `Formula/updatebar-tui.rb` |

The tap rejects unknown repositories, schema versions, package types, tokens,
asset names, duplicate tokens, non-version tags, and non-hex checksums.

## Cross-Repository Authentication

The per-repository `GITHUB_TOKEN` is not used across repositories. A dedicated
GitHub App is installed only on SwitchTab, UpdateBar, and `homebrew-tap` with
the minimum repository permissions needed to dispatch the tap event and create
the resulting branch and PR.

Application release workflows mint a short-lived installation token and send a
typed `repository_dispatch` event only after the GitHub Release is public. The
event contains the source repository and tag, not trusted package contents.
The tap workflow fetches `release-manifest.json`, release assets, and any
declared GitHub tag archive directly from the allowlisted source repository.

The tap recalculates every asset checksum and requires it to match the manifest
before rendering a file. This prevents a crafted dispatch payload from choosing
an arbitrary URL, local path, or checksum.

## Homebrew Tap Flow

For each accepted event, `sonim1/homebrew-tap`:

1. verifies that the repository and token mapping is allowlisted;
2. fetches the public GitHub Release for the exact tag;
3. downloads and validates `release-manifest.json`;
4. constructs allowlisted release-asset or GitHub-tag-archive URLs, downloads
   them, and recalculates SHA-256;
5. updates only the allowlisted Formula/Cask files;
6. runs Ruby syntax checks, `brew audit`, installation, and product-specific
   smoke tests;
7. creates or refreshes one deterministic release PR; and
8. enables auto-merge so repository rules merge it only after required checks
   pass.

The PR title and branch include the product and version. A rerun for the same
release updates or reuses that PR; it does not create duplicates. A newer
version event supersedes an older still-open PR for the same product only after
the newer artifacts have passed validation.

PRs are created with the GitHub App token rather than the tap repository's
default `GITHUB_TOKEN`, ensuring that the PR triggers the tap's required CI.

## Publication Ordering and Recovery

Public release operations are ordered so every published pointer references an
already available immutable artifact:

1. build and locally validate all artifacts;
2. create or reuse a draft GitHub Release and upload assets plus manifest;
3. upload the versioned Sparkle artifact to R2;
4. verify its public checksum;
5. update and verify `appcast.xml` last;
6. publish the GitHub Release; and
7. dispatch the Homebrew update.

Immutable files are never silently replaced. A retry accepts an existing file
only if its checksum matches. A same-tag checksum mismatch stops for manual
investigation because rebuilding a signed/notarized artifact can produce
different bytes.

Important partial-failure behavior:

- **Before appcast publication:** the GitHub Release remains a draft and no
  installed app sees an update.
- **After appcast but before GitHub publication:** the valid Sparkle update
  remains available. Recovery verifies the existing checksums and publishes
  the existing draft; it does not rebuild the tag.
- **After GitHub publication but before tap dispatch:** rerunning only the
  dispatch is safe because the tap validates the immutable public release.
- **Tap PR failure:** the app release remains valid. Homebrew stays on its last
  working version until the deterministic PR is fixed and checks pass.
- **Out-of-order releases:** each Sparkle feed enforces monotonically increasing
  bundle versions, and the tap refuses to replace a newer package version with
  an older one.

No workflow automatically deletes or rolls back a public update feed, GitHub
Release, R2 object, tag, or Homebrew version.

## Testing and Acceptance

### Script and workflow contracts

Both app repositories test:

- tag/version and `main` ancestry validation;
- required-secret failures and absence of an unsigned release fallback;
- temporary Keychain creation and unconditional cleanup;
- Developer ID signature, notarization, stapling, and Gatekeeper validation;
- canonical asset naming and checksum generation;
- Sparkle key/feed validation and appcast-last publication;
- draft GitHub Release retry and checksum-conflict behavior;
- manifest schema and exact asset/checksum content; and
- GitHub Environment, minimal permissions, pinned actions, and cross-repository
  dispatch wiring.

Network and credential-bearing shell behavior is covered with fake commands and
fixtures. Tests never alter real Apple, Cloudflare, GitHub, DNS, Keychain, or
Homebrew state.

### Tap contracts

The tap tests:

- every allowlisted repository/token/destination mapping;
- rejection of path traversal, unknown tokens, malformed manifests, duplicate
  packages, checksum mismatch, and unsupported schemas;
- deterministic Formula/Cask rendering and idempotent reruns;
- refusal to downgrade package versions;
- Ruby syntax, `brew audit`, installation, and executable/app smoke tests; and
- PR creation and auto-merge configuration.

### Release acceptance

Before enabling tag releases, each product performs one manual test release or
prerelease that verifies:

- the DMG passes `codesign`, `spctl`, and stapling checks on a clean Mac;
- Sparkle updates a previously installed Developer ID-signed build;
- the public appcast and enclosure are HTTPS-accessible and signature-valid;
- Homebrew installs the exact GitHub Release bytes; and
- a tap CI failure blocks merge without affecting the already published app.

## Rollout Order

1. Add the manifest validator, renderer, CI, and GitHub App automation to
   `homebrew-tap`.
2. Add the SwitchTab manifest and Cask dispatch to its already working release
   pipeline.
3. Add Sparkle 2.9.4, the strict Apple signing path, canonical DMG, R2 hosting,
   and manifest publication to UpdateBar.
4. Enable UpdateBar dispatch for its existing two Formulae and one Cask.
5. Perform test releases, then protect production `release` environments and
   enable normal tag-triggered operation.

This order establishes and tests the receiving boundary before either source
repository depends on it. SwitchTab exercises the simpler single-Cask path
before UpdateBar adds the multi-package release.

## Non-Goals

- Combining SwitchTab and UpdateBar into one repository or shared version.
- Including TamiCut.
- Purchasing or migrating to `updatebar.app` now.
- Replacing UpdateBar's CLI/TUI packaging strategy beyond automating its current
  Formula contracts.
- Automatically creating tags or deciding release versions.
- Automatic rollback or deletion of public release artifacts.
- Sharing one Sparkle private key between products.

## References

- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [Sparkle publishing documentation](https://sparkle-project.org/documentation/publishing/)
- [GitHub `GITHUB_TOKEN` scope](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub App authentication in Actions](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)
- [GitHub deployment environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments)
