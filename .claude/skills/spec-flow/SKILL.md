---
name: spec-flow
description: Work on SwitchTab features against the speckit plan (specs/001-macos-switchtab). Use before starting any feature-sized change.
---

# Spec Flow (SwitchTab)

AGENTS.md delegates context to `specs/001-macos-switchtab/plan.md` — the plan is the requirements source.

1. Read `specs/001-macos-switchtab/plan.md` (+ sibling spec files) for the area you're changing; the plan defines tech choices, structure, and shell commands.
2. Conflict between plan and code reality → code reality wins for HOW, plan wins for WHAT; report drift rather than silently picking.
3. Feature-sized work: state which plan section you're implementing in your report; keep changes inside that section's scope.
4. Plan doesn't cover the request → that's a scope decision: present a short proposal (what/where/tests) before implementing.
5. Finish through the verify skill; update the spec files only when Kendrick asks (they're his planning artifacts).
