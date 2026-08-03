# Documentation Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace completed planning trees with a short current-state AI guide and a compact, evidence-backed project decision history.

**Architecture:** `docs/AI_CONTEXT.md` becomes the only default agent context and stays focused on current truth. `docs/PROJECT_HISTORY.md` preserves historical context, decisions, rationale, changed requirements, superseded approaches, invariants, and evidence by feature; Git history remains the lossless source for exact originals. After both documents pass a source-by-source preservation audit, completed `docs/superpowers/` and `specs/001-macos-switchtab/` trees are removed from the current branch.

**Tech Stack:** Markdown, Git, shell repository checks, existing release documentation contract tests, Swift Package Manager tests.

---

## File Structure

- Create `docs/AI_CONTEXT.md`: current product, architecture, invariants, operations, and verification guidance.
- Create `docs/PROJECT_HISTORY.md`: task-selective history organized by feature.
- Modify `AGENTS.md`: route agents to the two new documents.
- Remove `docs/superpowers/plans/*.md`, `docs/superpowers/specs/*.md`, and `specs/001-macos-switchtab/**` after consolidation.

No application source, workflow, release script, or runtime configuration changes are in scope.

## Source-to-History Map

Every source below must be read completely and represented in the named history section before deletion.

### Product foundation and original macOS scope

- `specs/001-macos-switchtab/spec.md`
- `specs/001-macos-switchtab/plan.md`
- `specs/001-macos-switchtab/research.md`
- `specs/001-macos-switchtab/data-model.md`
- `specs/001-macos-switchtab/tasks.md`
- `specs/001-macos-switchtab/quickstart.md`
- `specs/001-macos-switchtab/launch-kit-plan.md`
- `specs/001-macos-switchtab/contracts/switcher-behavior.md`
- `specs/001-macos-switchtab/checklists/requirements.md`
- `docs/superpowers/plans/2026-07-02-overlay-sizing-header-window-filter.md`

### Signed updates and release operations

- `docs/superpowers/plans/2026-07-02-direct-release-automation-followup.md`
- `docs/superpowers/plans/2026-07-02-sparkle-direct-update.md`
- `docs/superpowers/specs/2026-07-02-sparkle-direct-update-design.md`
- `docs/superpowers/plans/2026-07-20-local-release-wrapper.md`
- `docs/superpowers/specs/2026-07-20-local-release-wrapper-design.md`
- `docs/superpowers/plans/2026-07-21-sparkle-r2-github-release.md`
- `docs/superpowers/specs/2026-07-21-sparkle-r2-github-release-design.md`
- `docs/superpowers/plans/2026-07-22-homebrew-tap-release-automation.md`
- `docs/superpowers/plans/2026-07-22-switchtab-homebrew-release-integration.md`
- `docs/superpowers/plans/2026-07-22-updatebar-sparkle-release-automation.md`
- `docs/superpowers/specs/2026-07-22-unified-release-operations-design.md`
- `docs/superpowers/plans/2026-07-27-automatic-pr-versioning.md`
- `docs/superpowers/specs/2026-07-26-automatic-pr-versioning-design.md`

### Permission recovery

- `docs/superpowers/specs/2026-07-26-permission-drag-helper-design.md`

### Window switcher selection and thumbnail quality

- `docs/superpowers/plans/2026-07-27-switcher-selection-visual-sync.md`
- `docs/superpowers/specs/2026-07-27-switcher-selection-visual-sync-design.md`
- `docs/superpowers/plans/2026-07-28-adaptive-thumbnail-quality.md`
- `docs/superpowers/specs/2026-07-28-adaptive-thumbnail-quality-design.md`

### Application switching and shortcut configuration

- `docs/superpowers/plans/2026-07-29-application-switching-cmd-tab.md`
- `docs/superpowers/specs/2026-07-29-application-switching-cmd-tab-design.md`
- `docs/superpowers/plans/2026-07-29-compact-application-switcher.md`
- `docs/superpowers/specs/2026-07-29-compact-application-switcher-design.md`
- `docs/superpowers/plans/2026-07-30-application-switcher-interaction-parity.md`
- `docs/superpowers/specs/2026-07-30-application-switcher-interaction-parity-design.md`
- `docs/superpowers/plans/2026-07-31-application-switcher-focus-layout.md`
- `docs/superpowers/specs/2026-07-31-application-switcher-focus-layout-design.md`
- `docs/superpowers/plans/2026-08-02-configurable-switcher-shortcuts.md`
- `docs/superpowers/specs/2026-08-02-configurable-switcher-shortcuts-design.md`

### Update diagnostics and documentation structure

- `docs/superpowers/plans/2026-07-30-update-error-diagnostics.md`
- `docs/superpowers/specs/2026-07-30-update-error-diagnostics-design.md`
- `docs/superpowers/specs/2026-07-29-readme-documentation-restructure-design.md`

### Compaction design and execution

- `docs/superpowers/specs/2026-08-03-documentation-compaction-design.md`
- `docs/superpowers/plans/2026-08-03-documentation-compaction.md`

---

### Task 1: Create the short default AI context

**Files:**
- Create: `docs/AI_CONTEXT.md`
- Modify: `AGENTS.md`
- Read: `README.md`, `docs/release-workflow.md`, `docs/update-hosting.md`, `docs/repository-maintenance.md`
- Read: `SwitchTab/AppDelegate.swift`, `SwitchTab/SwitchTabApp.swift`, `Package.swift`

- [ ] **Step 1: Verify the new context is absent**

Run: `test ! -e docs/AI_CONTEXT.md`

Expected: exit 0.

- [ ] **Step 2: Read current truth**

Read the files above and list the top-level contents of `SwitchTab/Models/`, `SwitchTab/Services/`, and `SwitchTab/UI/`. Prefer current code, tests, and live runbooks over historical plans.

- [ ] **Step 3: Create `docs/AI_CONTEXT.md`**

Use these exact headings:

```markdown
# SwitchTab AI Context
## Product and Platform
## Current User Experience
## Architecture
## Durable Invariants
## Permissions and Privacy
## Settings and Persistence
## Updates and Releases
## Verification
## Documentation Routing
```

Cover both switching modes, shortcut defaults/configuration, overlay selection and activation, permission boundaries, separate MRUs, update/release flow, canonical paths, and exact test/build commands. Keep it at 200 lines or fewer with no chronology or completed task lists.

- [ ] **Step 4: Update agent routing**

Replace the managed Spec Kit pointer in `AGENTS.md` with:

```markdown
## Project context

Read `docs/AI_CONTEXT.md` before repository work. Read only the relevant
feature section of `docs/PROJECT_HISTORY.md` when a task needs historical
decisions, rationale, changed requirements, or superseded approaches.
```

Do not modify RTK or gstack managed blocks.

- [ ] **Step 5: Verify size and routing**

Run:

```bash
test "$(wc -l < docs/AI_CONTEXT.md | tr -d ' ')" -le 200
grep -Fq 'docs/AI_CONTEXT.md' AGENTS.md
grep -Fq 'docs/PROJECT_HISTORY.md' AGENTS.md
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md docs/AI_CONTEXT.md
git commit -m "docs: add concise AI project context"
```

### Task 2: Build the evidence-backed project history

**Files:**
- Create: `docs/PROJECT_HISTORY.md`
- Read: every source in `Source-to-History Map`
- Read: `git log --oneline --decorate --all` and relevant current code/tests

- [ ] **Step 1: Extract every mapped source**

For each source, capture these fields in working notes before drafting:

```text
Context | Final decision | Rationale | Rejected alternatives |
Changed requirements | Superseded decisions | Invariants | Evidence
```

Do not mark a source complete when an applicable field is missing. Omit repeated commands, copied code, and completed checklist mechanics.

- [ ] **Step 2: Create `docs/PROJECT_HISTORY.md`**

Use these exact top-level sections:

```markdown
# SwitchTab Project History
## How to Use This Document
## Product Foundation and Original macOS Scope
## Window Switcher Layout and Filtering
## Signed Updates and Local Release Tooling
## R2, GitHub Release, and Homebrew Distribution
## Automatic Pull-Request Versioning
## Permission Recovery
## Selection Highlight and Thumbnail Quality
## Cmd-Tab Application Switching
## Compact Application Switcher
## Application Switching Interaction Parity
## Application Switcher Focus Layout
## Configurable Independent Shortcuts
## Update Error Diagnostics
## Documentation Structure
## Documentation Compaction
## Source Archive Index
```

Every feature section must contain `Context`, `Decision`, `Rationale`, `Changed from Original Plan`, `Invariants`, `Superseded Decisions`, and `Verification Evidence`. Use `None recorded` only after reading the complete source set.

- [ ] **Step 3: Add evidence and archive references**

Each feature section must cite current code/test paths plus a release, PR, or commit. `Source Archive Index` must list all 43 paths from this plan exactly once and explain Git recovery with `git log --all -- <path>` and `git show <commit>^:<path>`.

- [ ] **Step 4: Run the preservation audit**

Check all 43 source paths against `Source Archive Index`, then verify their target sections contain the eight extraction fields. Fix all omissions before deletion.

- [ ] **Step 5: Verify size and shape**

Run:

```bash
test "$(wc -l < docs/PROJECT_HISTORY.md | tr -d ' ')" -le 600
grep -Fq '### Changed from Original Plan' docs/PROJECT_HISTORY.md
grep -Fq '### Superseded Decisions' docs/PROJECT_HISTORY.md
grep -Fq '### Verification Evidence' docs/PROJECT_HISTORY.md
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add docs/PROJECT_HISTORY.md
git commit -m "docs: consolidate project decision history"
```

### Task 3: Remove completed planning trees

**Files:**
- Remove: `docs/superpowers/plans/`, `docs/superpowers/specs/`, `specs/001-macos-switchtab/`
- Modify if required: tracked documents referring to removed paths

- [ ] **Step 1: Confirm replacements are committed**

Run: `git log --oneline -- docs/AI_CONTEXT.md docs/PROJECT_HISTORY.md`

Expected: commits for both layers.

- [ ] **Step 2: Find external references**

Run:

```bash
git grep -n -E 'docs/superpowers/(plans|specs)/|specs/001-macos-switchtab/' -- . \
  ':(exclude)docs/superpowers/**' ':(exclude)specs/001-macos-switchtab/**'
```

Replace every live reference with `docs/AI_CONTEXT.md`, `docs/PROJECT_HISTORY.md`, or a surviving runbook.

- [ ] **Step 3: Remove completed sources**

Run: `git rm -r docs/superpowers/plans docs/superpowers/specs specs/001-macos-switchtab`

Expected: only the 43 mapped historical documents are staged for deletion.

- [ ] **Step 4: Verify no dangling references**

Run: `git grep -n -E 'docs/superpowers/(plans|specs)/|specs/001-macos-switchtab/' -- .`

Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/AI_CONTEXT.md docs/PROJECT_HISTORY.md
git commit -m "docs: retire completed implementation plans"
```

### Task 4: Verify the compacted repository

**Files:**
- Verify: `AGENTS.md`, `docs/AI_CONTEXT.md`, `docs/PROJECT_HISTORY.md`, all tracked Markdown links, and canonical tests

- [ ] **Step 1: Verify budgets and removals**

Run:

```bash
test "$(wc -l < docs/AI_CONTEXT.md | tr -d ' ')" -le 200
test "$(wc -l < docs/PROJECT_HISTORY.md | tr -d ' ')" -le 600
test ! -e docs/superpowers/plans
test ! -e docs/superpowers/specs
test ! -e specs/001-macos-switchtab
```

Expected: all commands exit 0.

- [ ] **Step 2: Verify routing and content hygiene**

Run:

```bash
grep -Fq 'docs/AI_CONTEXT.md' AGENTS.md
grep -Fq 'docs/PROJECT_HISTORY.md' AGENTS.md
git grep -n -E 'docs/superpowers/(plans|specs)/|specs/001-macos-switchtab/' -- . && exit 1 || true
git diff --check origin/main...HEAD
```

Expected: routing checks pass, removed-path search has no matches, and the diff has no whitespace errors.

- [ ] **Step 3: Run documentation contracts**

Run: `bash scripts/tests/release-local-test.sh`

Expected: `release-local contract tests passed`.

- [ ] **Step 4: Run Swift tests**

Run: `swift test`

Expected: 19 tests, 0 failures.

- [ ] **Step 5: Confirm the diff is documentation-only**

Run: `git diff --name-only origin/main...HEAD`

Expected: only `AGENTS.md`, the two new context documents, and removed files under the completed planning trees. No `SwitchTab/`, `SwitchTabTests/`, workflow, or release-script changes.

- [ ] **Step 6: Commit verification fixes only if needed**

```bash
git add AGENTS.md docs/AI_CONTEXT.md docs/PROJECT_HISTORY.md
git commit -m "docs: finalize compact project context"
```

If no fixes were needed, do not create an empty commit.
