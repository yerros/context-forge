# Context Digest

<!-- Compact brief of the whole context set. Budget: ~2.5 KB / ~600 tokens.
     Summarizes the six files — it never replaces them; when in doubt, the full
     file wins. The State section is refreshed at every close-unit; regenerate
     the whole digest with forge-compact when the underlying files change. -->

## Project

[One or two sentences: what this product is, for whom, and the current goal.]

## Stack & shape

[Key technologies and the system's boundaries in 2–4 lines — e.g. "Next.js 15 +
Clerk + Drizzle/Postgres; app router; UI in src/components, data access only via
src/db; background jobs in src/jobs."]

## Top invariants

<!-- The 3–7 rules from architecture.md that must never be violated. -->

- [Invariant 1]
- [Invariant 2]
- [Invariant 3]

## Conventions that matter most

<!-- The handful of code/UI standards that prevent the most rework. -->

- [e.g. TypeScript strict; no `any`]
- [e.g. All colors via theme tokens — no raw hex in components]

## State

<!-- Refreshed at every close-unit. Live detail lives in progress-tracker.md. -->

- Phase: [current phase]
- Last completed: [unit NN — name]
- In progress / Next up: [unit NN — name]

## Read further (tier map)

Read only what the task touches; the full files are the source of truth:

- UI, styling, components → `context/ui-context.md`
- Architecture, boundaries, storage, dependencies → `context/architecture.md`
- Writing code → `context/code-standards.md`
- Scope & product questions → `context/project-overview.md`
- Workflow rules → `context/ai-workflow-rules.md`
- Live state, open questions → `context/progress-tracker.md`
- Building or debugging → `context/lessons.md` (known mistakes & rules), then the
  unit's spec in `context/specs/`
