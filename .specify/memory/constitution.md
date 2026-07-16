<!--
Sync Impact Report
Version change: N/A -> 1.0.0
Modified principles:
- Template placeholder principles -> I. macOS-Only Product Scope
- Template placeholder principles -> II. Code Quality and Simplicity
- Template placeholder principles -> III. Testable Behavior
- Template placeholder principles -> IV. Consistent macOS UX
- Template placeholder principles -> V. Performance by Default
Added sections:
- macOS Platform Constraints
- Development Workflow and Quality Gates
- Governance
Removed sections:
- Template placeholder comments and examples
Templates requiring updates:
- .specify/templates/plan-template.md: reviewed, no update required
- .specify/templates/spec-template.md: reviewed, no update required
- .specify/templates/tasks-template.md: reviewed, no update required
- .specify/templates/commands/*.md: not present in this project
- AGENTS.md: reviewed, no update required
Follow-up TODOs: None
-->
# SwitchTab Constitution

## Core Principles

### I. macOS-Only Product Scope
The product MUST target macOS only. Specifications, plans, tasks, and code MUST
optimize for native macOS behavior before any portability concern. Cross-platform
abstractions are allowed only when they reduce local complexity without weakening
macOS behavior. Each plan MUST name the supported macOS version range.

Rationale: The app depends on macOS window management, accessibility, keyboard,
and menu bar conventions. Treating other platforms as first-class would dilute
the user experience and increase unnecessary complexity.

### II. Code Quality and Simplicity
Code MUST solve the requested behavior with the smallest clear design that fits
the current requirement. New abstractions MUST remove proven duplication or make
macOS-specific behavior easier to verify. Changes MUST stay scoped to the
feature or defect being addressed, and unused code introduced by the change MUST
be removed before completion.

Rationale: Window-management code is easy to over-generalize. Small, explicit
paths make accessibility permissions, focus changes, and edge cases easier to
reason about.

### III. Testable Behavior
New behavior MUST include automated tests when it can be validated without live
macOS UI state. Behavior that depends on real windows, accessibility prompts, or
system focus MUST include a documented manual validation path in quickstart.md or
the task output. Bug fixes MUST start from a failing reproduction when practical.

Rationale: The system boundary includes OS state that cannot always be mocked
faithfully. The project still requires verifiable evidence for every change.

### IV. Consistent macOS UX
User-facing behavior MUST follow macOS conventions for keyboard shortcuts,
window focus, menu bar presence, permission prompts, accessibility messaging,
and visual feedback. The primary workflow MUST be keyboard-first. UI text MUST
be concise, specific, and actionable, especially around permissions and errors.

Rationale: A window switcher is used repeatedly and under time pressure. Small
UX inconsistencies become daily friction.

### V. Performance by Default
Plans MUST define measurable performance targets for invocation latency, search
or filtering responsiveness, idle CPU usage, and memory impact. Implementations
MUST avoid continuous polling unless justified. Typical switching workflows MUST
feel immediate with dozens of open windows.

Rationale: The app sits in the background and is invoked often. Performance and
idle cost are core product qualities, not later polish.

## macOS Platform Constraints

The project MUST use macOS platform capabilities directly where they define the
product behavior, including accessibility APIs, keyboard shortcut handling,
window focus, and menu bar integration. Any plan that introduces a dependency
must explain why native APIs or simpler local code are insufficient.

Security and privacy requirements MUST treat accessibility permission as a
first-class user concern. The app MUST request only permissions needed for the
current feature and MUST explain recovery steps when permission is missing or
revoked.

## Development Workflow and Quality Gates

Every feature MUST pass through specification, plan, tasks, and implementation
artifacts before broad implementation begins. The specification MUST state user
value and success criteria without implementation details. The plan MUST record
macOS version support, testing strategy, UX constraints, and performance targets.
The task list MUST produce independently verifiable increments.

Before completion, the implementer MUST run relevant tests and any documented
manual validation steps. If a validation step cannot be run, the final report
MUST say why and identify the remaining risk.

## Governance

This constitution supersedes informal project practices. Specs, plans, tasks,
and reviews MUST check for compliance with these principles. A change that
violates a principle MUST document the violation, reason, rejected simpler
alternative, and follow-up review point in the plan's Complexity Tracking
section.

Amendments require updating this file, recording the version change in the Sync
Impact Report, and reviewing dependent Spec Kit templates or runtime guidance.
Semantic versioning applies: MAJOR for incompatible governance changes, MINOR
for new or materially expanded principles, and PATCH for clarifications.

Compliance review happens at planning, task generation, implementation, and
final verification. Plans that omit macOS scope, testing strategy, UX constraints,
or performance targets are incomplete.

**Version**: 1.0.0 | **Ratified**: 2026-06-17 | **Last Amended**: 2026-06-17
