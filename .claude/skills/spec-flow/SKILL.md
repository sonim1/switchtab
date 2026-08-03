---
name: spec-flow
description: Work on SwitchTab features from current context and task-selective decision history. Use before starting any feature-sized change.
---

# Context Flow (SwitchTab)

AGENTS.md delegates current context to `docs/AI_CONTEXT.md` and historical lookup to `docs/PROJECT_HISTORY.md`.

1. Read `docs/AI_CONTEXT.md`; it defines current behavior, boundaries, and verification commands.
2. Read only the relevant feature section of `docs/PROJECT_HISTORY.md` when prior rationale, changed requirements, or superseded choices matter.
3. Current code, tests, and live runbooks win when historical intent disagrees; report meaningful drift.
4. For feature-sized work, state the requested behavior, affected boundaries, and verification before implementing.
5. Finish through the verify skill; update current context/history only when the delivered change alters their durable facts.
