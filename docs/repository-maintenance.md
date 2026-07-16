# Repository Maintenance

Checked: 2026-07-12

## Current Source Of Truth

- `README.md`: quick project overview, local build/test commands, and direct
  distribution build usage.
- `specs/001-macos-switchtab/plan.md`: current source layout and implementation
  verification notes.
- `specs/001-macos-switchtab/quickstart.md`: manual macOS validation scenarios
  and recorded validation history.
- `BLOCKERS.md`: validation that requires user-controlled macOS permissions or
  external signing/notarization access.

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
- The default Sparkle revision is pinned to Sparkle 2.9.4
  (`b6496a74a087257ef5e6da1c5b29a447a60f5bd7`), matching the latest GitHub
  release checked on 2026-07-12:
  https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4

## Security Checks

- Secret-pattern scan found no AWS keys, OpenAI-style `sk-` keys, GitHub PATs,
  Slack tokens, or private key blocks outside ignored build/git directories.
- Keyword scan found expected release/documentation placeholders only:
  `SPARKLE_PUBLIC_ED_KEY`, `DEVELOPER_ID_APPLICATION`,
  `NOTARYTOOL_KEYCHAIN_PROFILE`, and template examples.
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
- Public Sparkle auto-updates still require signed appcast generation and feed
  publication; see `BLOCKERS.md`.

## Local Hygiene

- `git worktree list` shows only the current worktree.
- `git stash list` shows no stashes.
- `.build/`, `.gstack/`, Xcode user state, DMGs, zips, and app bundles are
  ignored local artifacts.
- The current dirty worktree includes the SwitchTab rename and active code/docs
  changes. Do not delete, reset, or clean these without user confirmation.

## Standard Verification

Run these before treating repo cleanup as complete:

```bash
swift build
swift test
xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' build
SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
git diff --check
```

Live focus, thumbnail, and permission-recovery scenarios still require a real
logged-in macOS session where the user grants Accessibility and Screen Recording
permissions.

## Last Verification

Recorded on 2026-07-12:

- `swift build`: passed.
- `swift run SwitchTabTestRunner`: passed; all tests passed.
- `xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration
  Debug -destination 'platform=macOS,arch=arm64' build`: passed.
- `SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh
  --prepare-only`: passed.
- `SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh`: passed;
  Sparkle 2.9.4 was fetched and the generated Release app built successfully.
- `SWITCHTAB_UPDATE_FEED_URL=http://...` with direct distribution prepare:
  rejected as expected because update feeds must use HTTPS.
- Generated `Info.direct.plist` and `project.pbxproj` linted successfully.
- `git diff --check`: passed.
- High-risk secret-pattern scan: no matches.
- Temporary-marker scan: no matches.
