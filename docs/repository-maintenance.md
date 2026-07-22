# Repository Maintenance

Checked: 2026-07-21

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

## Standard Verification

Run these before treating repo cleanup as complete:

```bash
swift test
for test_script in scripts/tests/release-{tooling,local,workflow}-test.sh \
  scripts/tests/{generate-appcast,setup-update-hosting,publish-update,publish-release}-test.sh; do
  bash "$test_script"
done
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
