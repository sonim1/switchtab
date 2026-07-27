# Repository Maintenance

Checked: 2026-07-27

## Current Source Of Truth

- `README.md`: project overview, local build/test commands, and local/CI direct
  distribution release operation.
- `specs/001-macos-switchtab/plan.md`: current source layout and implementation
  verification notes.
- `specs/001-macos-switchtab/quickstart.md`: manual macOS validation scenarios
  and recorded validation history.
- `BLOCKERS.md`: validation that requires user-controlled macOS permissions,
  release credentials, or approval for live external mutations.

The checked-in app currently implements current-app window switching only.
Older research/task sections that mention app-level switching or drag-overlay
permission recovery are preserved as historical planning context unless a future
feature goal updates code, tests, and docs together.

No `gbrain` or similarly named brain/context file was found in the repository
scan.

## Dependency State

- `Package.swift` has no external SwiftPM dependencies.
- `scripts/build-direct-distribution.sh` injects Sparkle only into a generated
  direct-distribution workspace under `.build/direct-distribution/`.
- The generated distribution workspace pins Sparkle 2.9.4 at
  `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`:
  https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4
- `package-lock.json` locks the repository release tooling to Wrangler 4.112.0
  and overrides its transitive `sharp` dependency to patched 0.35.3; install it
  with `npm ci --ignore-scripts`.
- `.github/workflows/release.yml` installs Node 24.18.0 with a full-SHA-pinned
  `actions/setup-node` action before installing the release tooling.
- `scripts/generate-appcast.sh`, `scripts/setup-update-hosting.sh`,
  `scripts/publish-update.sh`, and `scripts/publish-release.sh` implement signed
  appcast generation, fail-closed R2 setup, atomic update publication, and
  GitHub release publication. `.github/workflows/release.yml` runs the release
  path for protected version tags or an existing-tag manual dispatch.

## Security Checks

- Secret-pattern scan found no AWS keys, OpenAI-style `sk-` keys, GitHub PATs,
  Slack tokens, or private key blocks outside ignored build/git directories.
- Keyword scan found expected release/documentation placeholders only. Public
  configuration includes `SPARKLE_PUBLIC_ED_KEY`,
  `DEVELOPER_ID_APPLICATION`, `NOTARYTOOL_KEYCHAIN_PROFILE`,
  `CLOUDFLARE_ACCOUNT_ID`, and `CLOUDFLARE_ZONE_ID`; secret placeholders
  include `CLOUDFLARE_API_TOKEN`, `R2_ACCESS_KEY_ID`, and
  `R2_SECRET_ACCESS_KEY`. No values are stored in the repository.
- `shellcheck`, `gitleaks`, and `trufflehog` were not installed in this local
  environment, so repository-local regex scans were used as the available
  fallback checks.
- Release credentials are read from environment variables. They are not stored
  in the repository.
- The release workflow uses bucket-scoped R2 S3 credentials for conditional
  object writes and does not receive the broader Cloudflare hosting-setup
  token. Mutable appcast updates require a newer numeric build version and an
  authoritative R2 ETag precondition.
- Local `.env`, private key, and certificate-like files are ignored by
  `.gitignore`.
- Permission recovery opens System Settings and requires the user to grant
  access manually. The app does not mutate TCC state or synthesize privacy
  approval input.
- Signed appcast generation and feed publication are automated. Live validation
  still requires user-controlled Apple, Sparkle, Cloudflare/R2, and GitHub
  credentials plus approval for external mutations; see `BLOCKERS.md`.

## Local Hygiene

- `.build/`, `.gstack/`, `.omo/`, `.swiftpm/`, `.worktrees/`, Xcode user state,
  DMGs, zips, app bundles, and `.debug-journal.md` are ignored local artifacts.
- Local worktrees and ignored evidence may exist during isolated verification;
  their presence is not repository release content.
- Unrelated user-owned changes in the primary checkout must remain untouched.
  Inspect status before staging, cleaning, or rewriting history instead of
  recording a temporary dirty/clean state in this document.

## Pull Request Version Policy

- `.github/workflows/ci.yml` owns pull-request version changes. Contributors
  should not manually maintain `MARKETING_VERSION` or
  `CURRENT_PROJECT_VERSION` in `SwitchTab.xcodeproj/project.pbxproj`.
- A release-relevant PR defaults to a patch bump. `release:minor` and
  `release:major` select the other supported bump kinds; applying both fails
  policy before checkout mutation.
- Documentation-only changes (`*.md`, `*.markdown`, `docs/`, and `specs/`) do
  not change versions and produce `release=false` after merge.
- The marketing version is derived from the current PR base and normalized to
  three components. The integer build number increments exactly once.
- Write-scoped versioning runs only for a same-repository PR targeting `main`
  whose author association is OWNER, MEMBER, or COLLABORATOR. Fork and
  untrusted-author PRs fail with an explicit policy message and receive no
  versioning write job.
- The bot stages only `SwitchTab.xcodeproj/project.pbxproj`, never force-pushes,
  and stops after its version commit. The resulting `synchronize` event runs
  the read-only `verify` job against the new exact head.

Repository rollout requirements:

- labels `release:minor` and `release:major` must exist;
- `main` must require pull requests and the exact `verify` status check;
- required status checks must be strict so a branch behind `main` cannot merge.

If CI reports conflicting release labels, remove one. If the PR is stale,
update it from `main` and let CI recalculate. If a non-fast-forward push loses a
race with another head update, rerun or update the branch; do not force-push the
bot commit. `scripts/plan-release.sh` remains the final fail-closed guard after
merge and rejects equal or decreasing versions.

## Standard Verification

Run these before treating release automation changes as complete:

```bash
for test_script in scripts/tests/*-test.sh; do
  bash "$test_script"
done
swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
for script in scripts/*.sh scripts/tests/*.sh; do bash -n "$script"; done
ruby -e 'require "yaml"; YAML.safe_load(File.read(".github/workflows/release.yml"), aliases: true)'
npm ls --depth=0
git diff --check
```

Live focus, thumbnail, and permission-recovery scenarios still require a real
logged-in macOS session where the user grants Accessibility and Screen Recording
permissions.

## Last Verification

Recorded on 2026-07-21 without live external publication:

- All seven release contract tests passed: tooling, local wrapper, appcast
  generation, hosting setup, R2 update publication, GitHub release publication,
  and workflow contracts.
- `swift test`: passed; 18 tests, 0 failures.
- Unsigned `xcodebuild` Debug for `platform=macOS,arch=arm64` with
  `CODE_SIGNING_ALLOWED=NO`: passed.
- `SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh
  --prepare-only`: passed.
- Bash 3.2 syntax validation passed for all release and contract-test scripts.
- `.github/workflows/release.yml` parsed successfully as YAML.
- `npm ls` reported Wrangler 4.112.0 with transitive `sharp` 0.35.3, and
  `npm audit --audit-level=high` reported zero vulnerabilities.
- `git diff --check`: passed.
- User-specific path, Korean text, private-key block, and high-risk secret-literal
  scans found no release-content matches.
- No hosting setup, object upload, tag creation/push, or GitHub release mutation
  was performed during this verification.
