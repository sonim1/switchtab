# Automatic PR Versioning Implementation Plan

**Goal:** Make every trusted, release-relevant pull request receive the exact label-derived Xcode marketing/build version before the existing CI verification and main-branch release automation run.

**Architecture:** A deterministic shell tool calculates versions from the trusted base commit, classifies documentation-only diffs, and updates only `SwitchTab.xcodeproj/project.pbxproj`. The pull-request workflow runs a metadata-only policy check first, lets a write-scoped job commit the calculated project version only for trusted same-repository contributors, and runs the existing read-only verification job only after the head is already correct.

**Policy:** No release label means patch; `release:minor` and `release:major` select those bumps; both labels fail. Documentation-only changes remain non-releases. `CURRENT_PROJECT_VERSION` increments by exactly one.

---

## Task 1: Add version preparation contract tests

**Files:**

- Create: `scripts/tests/prepare-pr-version-test.sh`
- Test: `scripts/tests/prepare-pr-version-test.sh`

1. Build an isolated Git fixture with Debug and Release version declarations.
2. Add failing cases for patch, minor, major, build increment, docs-only no-op, idempotency, manual head replacement, malformed/inconsistent base versions, invalid bump kinds, missing declarations, comments/quoted text, and output-file behavior.
3. Run `bash scripts/tests/prepare-pr-version-test.sh` and confirm it fails because the production script does not exist.

## Task 2: Implement deterministic project version preparation

**Files:**

- Create: `scripts/prepare-pr-version.sh`
- Modify: `scripts/tests/prepare-pr-version-test.sh`

1. Accept `<base-commit> <head-commit> <patch|minor|major> [output-file]` and resolve both commits fail-closed.
2. Reuse the release planner's documentation-only path policy.
3. Parse all active base declarations while ignoring comments and quoted text. Require one consistent one-to-three-component numeric marketing version and one consistent integer build number.
4. Normalize marketing versions to three components, calculate the requested bump, and increment the build integer once.
5. Replace every active head declaration with the exact target while changing no other file. Require both version keys to exist.
6. Emit `release`, `changed`, `ready`, `version`, and `build` outputs; make a correct rerun a no-op.
7. Run the new contract test until green, then run Bash syntax and ShellCheck.

## Task 3: Add pull-request workflow contracts

**Files:**

- Create: `scripts/tests/ci-workflow-test.sh`
- Modify: `scripts/tests/release-tooling-test.sh`

1. Assert exact pull-request event types: opened, reopened, synchronize, labeled, and unlabeled.
2. Assert repository-level read permission, a metadata-only trust/label policy job, a write-scoped version job gated to same-repository `main` pull requests from OWNER/MEMBER/COLLABORATOR authors, and the existing read-only verify job.
3. Assert conflict detection occurs before checkout, no force push is present, only the Xcode project is staged, the bot identity is fixed, and verification runs only when the current head is ready.
4. Assert the new version preparation test is included in the release contract suite and no release-environment secret is referenced.
5. Run `bash scripts/tests/ci-workflow-test.sh` and confirm it fails against the current workflow.

## Task 4: Wire trusted automatic version commits into CI

**Files:**

- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/tests/ci-workflow-test.sh`

1. Add the exact pull-request activity types and a policy job that derives the bump kind from event labels, rejects conflicts, and rejects unsupported trust contexts without checking out PR code.
2. Add a `contents: write` version job gated by policy outputs. Check out the exact same-repository PR branch with full history, run `scripts/prepare-pr-version.sh`, stage only the project file, commit as `github-actions[bot]`, and push without force.
3. Preserve `contents: read` on verification. Gate it on a successful ready/no-op version result so a mutation run stops and the resulting synchronize run performs verification.
4. Add the new version and workflow contract tests to the existing release test array.
5. Run both new contract tests and the complete existing release contract suite.

## Task 5: Document contributor and maintainer operation

**Files:**

- Modify: `README.md`
- Modify: `docs/repository-maintenance.md`

1. Document the default patch behavior and the `release:minor` / `release:major` labels.
2. State that contributors do not edit Xcode version declarations manually and that documentation-only PRs do not release.
3. Document same-repository trust restrictions, conflicting-label recovery, stale-branch refresh requirements, and required `verify` branch protection.

## Task 6: Verify locally and roll out repository settings

**Files:**

- Verify only: all changed files

1. Run every `scripts/tests/*-test.sh` contract test.
2. Run `swift test`.
3. Run an unsigned Debug Xcode build for `platform=macOS,arch=arm64`.
4. Run ShellCheck, Bash syntax checks, YAML parsing, and `git diff --check`.
5. Create repository labels `release:minor` and `release:major` if missing.
6. Update `main` protection to require pull requests, require the exact `verify` status, and require branches to be current before merge.
7. Push the feature branch and open a pull request only after all local checks pass; do not merge it until GitHub reports the required checks successful.
