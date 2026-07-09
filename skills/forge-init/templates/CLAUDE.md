## Application Building Context

This project uses **tiered context loading** to stay
token-efficient. Do not read all context files by
default — read by tier:

**Tier 1 — always:** `context/context-digest.md` (compact
brief: project, stack, top invariants, state, tier map).
When starting implementation work, also read
`context/progress-tracker.md` for live state.

**Tier 2 — read the file(s) the task touches:**

1. `context/project-overview.md` — scope, features,
   product questions
2. `context/architecture.md` — boundaries, storage,
   dependencies, invariants (read before any
   architectural decision)
3. `context/ui-context.md` — UI, styling, components
4. `context/code-standards.md` — when writing code
5. `context/ai-workflow-rules.md` — workflow and
   scoping questions
6. `context/lessons.md` — when building or debugging
   (known mistakes and their rules; keep it in mind)
7. `context/specs/NN-*.md` — when building that unit

**Never guess to save tokens** — if a decision depends
on a file you have not read, read it first. The full
files are the source of truth; the digest only
summarizes them.

Update `context/progress-tracker.md` after each
meaningful implementation change. Keep it lean (active
window only); older history is rotated into
`context/progress-archive.md`, which is a record and is
**not** read on resume/build. Do not load the archive
unless you specifically need past history.

If implementation changes the architecture, scope, or
standards, update the relevant context file — and the
digest, if it affects what the digest summarizes —
before continuing.
