# Documentation Compaction Design

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Historical plans and specifications under `docs/superpowers/` and `specs/001-macos-switchtab/`

## Problem

The repository currently keeps 32 completed Superpowers plan/design documents
with 11,436 lines and a nine-file Spec Kit bundle with another 1,972 lines.
These documents preserve useful reasoning, but they also repeat implementation
steps, code excerpts, test instructions, and superseded details. Future coding
agents can spend substantial context reconstructing history instead of reading
the current code and authoritative operational documentation.

`AGENTS.md` also directs agents to read
`specs/001-macos-switchtab/plan.md`, so an historical 243-line plan can enter
unrelated sessions even when its implementation is already shipped.

## Goals

- Preserve product history, decisions, rationale, changed requirements,
  superseded approaches, invariants, and verification evidence.
- Give coding agents a short current-state document that is safe to read on
  every task.
- Make detailed history discoverable without loading it by default.
- Remove completed plans and specs from the current tree after their durable
  information has been consolidated.
- Keep exact original documents recoverable through Git history.

## Non-Goals

- Reconstructing every implementation step or checklist item.
- Duplicating source code, tests, release scripts, or operational runbooks.
- Replacing user-facing README or release/update documentation.
- Rewriting Git history to erase the original documents.
- Changing application behavior, release behavior, or test behavior.

## Chosen Structure

### `docs/AI_CONTEXT.md`

This is the default context document for coding agents. `AGENTS.md` will point
to it instead of the completed Spec Kit plan.

It will contain only current truth:

- product purpose and supported platform;
- current architecture and major component boundaries;
- user-visible behavior and durable invariants;
- permissions and privacy boundaries;
- release/versioning model;
- canonical tests and verification commands;
- links to authoritative operational documents;
- a pointer to `docs/PROJECT_HISTORY.md` for task-relevant history.

Target size: no more than 200 lines. It must not contain chronological
narrative, completed task lists, copied code, or detailed historical debate.

### `docs/PROJECT_HISTORY.md`

This is the selective historical reference. Agents read only the relevant
feature section when a task touches that feature.

Each feature record uses this schema:

```markdown
## Feature name

**Status:** Shipped / Superseded / Partial
**Evidence:** release, PR, commit, and key code/test paths

### Context
The user problem and constraints at the time.

### Decision
The final implementation decision.

### Rationale
Why this option won and which alternatives were rejected.

### Changed from Original Plan
Requirements or implementation details that changed during delivery.

### Invariants
Behavior future work must preserve.

### Superseded Decisions
Old decisions, what replaced them, and why.

### Verification Evidence
Tests, manual evidence, releases, and operational validation.
```

The `Changed from Original Plan` section replaces the idea of a standalone
`CHANGED.md`. A separate file would look like a release changelog and separate
changes from the decisions and rationale that explain them.

Target size: no more than 600 lines, with a preference for 300–450 lines.

## Source Material and Consolidation Scope

The consolidation includes:

- all completed plans in `docs/superpowers/plans/`;
- all completed designs in `docs/superpowers/specs/`;
- the completed Spec Kit bundle in `specs/001-macos-switchtab/`, including its
  plan, spec, research, data model, task list, quickstart, contracts, and
  checklists;
- this design and its implementation plan after the compaction work is
  complete.

The current tree will retain authoritative documents that describe live
operations or public behavior, including:

- `README.md`;
- `docs/release-workflow.md`;
- `docs/update-hosting.md`;
- `docs/repository-maintenance.md`;
- other focused current runbooks that are not completed implementation plans.

## Preservation Rules

Every source plan/design must map to at least one history section. A source is
not removed until the consolidated history preserves all applicable items:

1. the original problem and constraints;
2. the final decision and why it was chosen;
3. meaningful alternatives and why they were rejected;
4. changes between the original plan and shipped behavior;
5. superseded decisions and their replacements;
6. durable behavioral, security, and release invariants;
7. unresolved limitations or follow-up risks;
8. evidence: releases, PRs, commits, tests, and canonical code paths.

Completed task-by-task instructions, repeated shell commands, copied code,
stale line numbers, and verification steps already encoded in tests are omitted.

## Recoverability

Original documents are deleted only from the current tree. Git history remains
the lossless archive. Each history section will cite at least one release, PR,
or commit that lets a future agent retrieve the exact source with commands such
as:

```bash
git show <commit>^:<historical-path>
git log --all -- <historical-path>
```

No `archive/` directory is created. Moving originals into an archive would keep
them visible to repository searches and make accidental context loading likely.

## Migration Process

1. Inventory every source document and assign it to a feature/history section.
2. Extract decisions, rationale, changes, invariants, risks, and evidence.
3. Draft `AI_CONTEXT.md` from current code, tests, and authoritative runbooks.
4. Draft `PROJECT_HISTORY.md` from the extraction inventory.
5. Cross-check every source document against the preservation rules.
6. Update `AGENTS.md` to route default context to `AI_CONTEXT.md` and selective
   historical lookup to `PROJECT_HISTORY.md`.
7. Remove the consolidated historical plan/spec trees.
8. Validate links, paths, content limits, Git cleanliness, and documentation
   contract tests.

## Validation

The migration is complete only when:

- every historical source is represented in the consolidation inventory;
- `docs/AI_CONTEXT.md` is at most 200 lines;
- `docs/PROJECT_HISTORY.md` is at most 600 lines;
- `AGENTS.md` no longer points to a deleted or completed plan;
- no tracked document links to removed plan/spec paths;
- the two context documents contain no unfinished placeholder markers;
- `git diff --check` passes;
- documentation/release contract tests pass;
- `swift test` passes because the migration also validates the repository's
  canonical test entry point;
- the final diff contains documentation and routing changes only, with no app
  behavior changes.

## Risks and Mitigations

- **Over-compression loses rationale.** Mitigation: use the preservation
  checklist per source and cite recoverable Git evidence.
- **Current behavior is inferred incorrectly from old plans.** Mitigation:
  derive `AI_CONTEXT.md` from current source/tests and use plans only for
  historical rationale.
- **History becomes hard to discover.** Mitigation: feature headings, code/test
  path references, and an index at the top of `PROJECT_HISTORY.md`.
- **Agents still load all history.** Mitigation: `AGENTS.md` points only to
  `AI_CONTEXT.md` by default and explicitly makes history task-selective.
- **Operational guidance is accidentally removed.** Mitigation: keep live
  runbooks outside the consolidation scope and verify all removed-path links.

## Expected Result

The default agent context becomes a short current-state reference, while the
repository retains a compact, evidence-backed decision history. The current
tree drops roughly 13,400 lines of completed planning material in favor of at
most 800 lines across the two durable context files, while Git remains the
lossless archive for exact originals.
