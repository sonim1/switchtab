# README and Documentation Restructure Design

**Date:** 2026-07-29
**Status:** Approved for planning

## Goal

Make the repository entry point easy for a new SwitchTab user to scan while
preserving the existing developer and release guidance in focused documents.

## Audience and Scope

The root `README.md` is user-first. It should explain what SwitchTab does, its
macOS requirements, its default current-app window-switching behavior, and the
shortest development quick start. Maintainer-only build, hosting, release, and
recovery details move under `docs/`.

This change reorganizes existing documentation. It does not change product
behavior, release behavior, scripts, workflows, or credentials.

## README Structure

The README will contain:

1. A centered product header using the checked-in app icon at
   `SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png`.
2. A concise product description.
3. A short explanation of current-app window switching and the default
   shortcut behavior.
4. Requirements.
5. A minimal Xcode and SwiftPM development quick start.
6. A documentation index linking to each focused guide.

Long command sequences, credential inventories, CI internals, hosting setup,
tag recovery, and release failure handling will not remain inline.

## Document Boundaries

### `docs/development.md`

- Local requirements
- Xcode build and test flow
- SwiftPM build and test flow
- Expected verification surfaces

### `docs/direct-distribution.md`

- Why direct distribution uses an isolated generated workspace
- Standard direct-distribution build
- `--prepare-only` behavior
- Signed, notarized, stapled DMG build with `--release`
- Generated artifact location and required environment variables

### `docs/update-hosting.md`

- Sparkle feed and Cloudflare R2 ownership
- One-time Wrangler and custom-domain setup
- Local signing and publishing prerequisites
- Cloudflare credential boundaries
- Safe local publishing fallback and Homebrew dispatch handoff

### `docs/release-workflow.md`

- Pull-request version policy
- GitHub variables, secrets, and protected environment setup
- Automatic tag and release execution
- Homebrew tap integration
- Release asset contract
- Recovery and immutability rules

Existing `docs/repository-maintenance.md` remains an audit and maintenance
record. The untracked `docs/release-preflight-checklist.md` remains untouched.

## Content Rules

- Preserve operational requirements and safety constraints when moving text.
- Remove only repeated explanations created by the old single-file layout.
- Keep documentation in English to match the repository and reference projects.
- Use descriptive links and short sections modeled after `preqstation` and
  `preqstation-cli`.
- Avoid inventing installation, download, license, or support claims not already
  established by the repository.

## Verification

- Update the documentation contract test so it checks the direct-distribution
  guide and verifies that README links to the focused documents.
- Run the relevant Swift test suite.
- Check Markdown links and referenced local paths.
- Run `git diff --check`.
- Confirm unrelated existing worktree changes remain untouched.

## Success Criteria

- A new reader can understand SwitchTab and find the quick start without
  scanning release operations.
- Every substantive section from the original README remains available in the
  README or one focused document.
- README displays the checked-in app icon on GitHub.
- Documentation links resolve inside the repository.
- Documentation-related tests pass.
