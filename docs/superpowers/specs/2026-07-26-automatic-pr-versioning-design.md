# Automatic PR Versioning Design

## Goal

Remove manual Xcode version edits from normal pull requests while preserving the existing invariant that every release tag points to a commit whose project metadata contains that exact release version.

## User-facing policy

- A release-relevant pull request without a release label receives a patch bump.
- `release:minor` selects a minor bump.
- `release:major` selects a major bump.
- Applying both release labels is invalid and blocks CI before any commit is pushed.
- Documentation-only pull requests do not change either version and do not release.
- Every release-relevant bump increments the integer `CURRENT_PROJECT_VERSION` by one.
- The bot owns version edits. If a pull request contains different manual version values, it replaces only those declarations with the label-derived values.

Starting from version `1.0.4` build `5`, the resulting examples are:

| PR labels | Marketing version | Build version |
|---|---:|---:|
| none | `1.0.5` | `6` |
| `release:minor` | `1.1.0` | `6` |
| `release:major` | `2.0.0` | `6` |

## Architecture

### Version bump script

Add a focused script that receives a trusted base commit, a pull-request head commit, and a release kind. It reads the base commit's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, classifies the diff using the same documentation-only path rules as the release planner, and calculates the exact target values.

For release-relevant changes, the script updates every active Debug and Release declaration in `SwitchTab.xcodeproj/project.pbxproj`. Marketing versions are normalized to three components for automatic bumps. The base build number must be a single non-negative integer; ambiguous dotted build numbers fail closed because their automatic successor is not defined by this policy.

The script is idempotent. When the pull-request head already contains the expected values, it reports that no commit is necessary. It changes no files other than the Xcode project.

### Pull-request workflow

Extend the existing `CI` workflow with a small versioning job that runs before verification on pull-request open, reopen, synchronize, label, and unlabel events.

The versioning job receives `contents: write` only when all of these conditions hold:

- the pull request originates from this repository;
- the target branch is `main`;
- the author association is `OWNER`, `MEMBER`, or `COLLABORATOR`.

It checks out the exact PR head, runs the version bump script, and commits only the Xcode project when a bump is required. The commit identity is `github-actions[bot]`, and the commit message records the calculated version and build. Pushing that commit triggers a fresh `synchronize` run.

The verification job keeps `contents: read`. It runs only when the versioning job reports that the current head already has the expected version, so the initial run that creates a bot commit does not produce a misleading release-plan failure. The fresh run then executes the existing release planner, contract tests, Swift tests, and unsigned Xcode build.

Unsupported fork or untrusted-author pull requests receive no write token and fail with an explicit versioning-policy message rather than executing PR-controlled code with repository write access.

### Existing release pipeline

The main-branch release workflow remains unchanged. After the versioned PR is merged, `scripts/plan-release.sh` verifies that both versions increased, creates the annotated tag on the exact merge commit, and dispatches the protected signing, notarization, GitHub Release, and R2/Sparkle publication workflow.

Keeping the bump inside the PR preserves auditable source metadata and avoids merge-time version commits, workflow recursion, and tag/source mismatches.

## Concurrency and stale pull requests

Multiple open pull requests may initially calculate the same next version. Once one merges, every remaining release-relevant PR must be refreshed against the new `main` before it can pass the latest CI run. The workflow recalculates from the current pull-request base SHA whenever GitHub refreshes the PR or its branch is updated.

As part of rollout, configure `main` branch protection to require pull requests, require the `verify` status check, and require branches to be up to date before merge. This prevents a stale PR carrying an already-used version from merging. The main release planner remains a second fail-closed guard and refuses equal or decreasing versions even if repository settings are misconfigured.

Create the repository labels `release:minor` and `release:major` during rollout so contributors can select the non-default bump without manual repository setup.

## Error handling

- Both release labels: fail before checkout mutation.
- Unknown release labels: ignored; the default remains patch.
- Documentation-only PR with release labels: no bump and no release.
- Missing, inconsistent, or malformed base declarations: fail before mutation. Recognized head declarations are always replaced with the exact calculated target.
- Failed push due to a concurrent head update: fail without force-pushing; the next synchronized run recalculates.
- Existing bot-authored expected bump: no-op and proceed to verification.

The workflow never force-pushes and never reads release-environment secrets.

## Testing

Contract tests cover:

- patch, minor, and major calculations;
- build-number increments;
- documentation-only no-op behavior;
- conflicting labels;
- malformed or inconsistent base versions;
- replacement of manual head-version edits;
- idempotent reruns;
- exact workflow events, permissions, trust guards, job ordering, commit scope, and absence of release secrets;
- preservation of the existing main release workflow behavior.

The complete release contract suite, `swift test`, an unsigned Debug Xcode build, ShellCheck, Bash syntax checks, and `git diff --check` must pass before merge.

## Documentation

Update `README.md` with the everyday contributor flow and label examples. Update `docs/repository-maintenance.md` with the maintainer policy, trust restrictions, stale-PR requirement, failure recovery, and the rule that the bot—not contributors—owns Xcode version declarations.
