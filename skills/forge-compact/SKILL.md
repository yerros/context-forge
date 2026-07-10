---
name: forge-compact
description: >
  This skill should be used to shrink the recurring token cost of a Six-File Context
  Methodology project — phrases like "forge-compact", "compact the context", "the
  context files are too big", "reduce token usage", "trim the context files",
  "generate the digest", or "make resume cheaper". It measures every context file
  against its soft budget, compresses over-budget files with user approval (never
  dropping facts), rotates tracker history, and (re)generates the compact
  context-digest.md used for tiered loading.
metadata:
  version: "0.13.0"
---

# forge-compact

Bring the project's recurring context cost back under budget. The six files plus the
entry point and digest are what every session pays to load; this skill is the guided
maintenance pass that keeps that price low. Budgets, tiers, and the digest contract
are defined canonically in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-resume/references/token-economy.md` — read it
first.

## 1. Measure

Run the measurement (read-only) and compare against the canonical budgets:

```bash
for f in CLAUDE.md AGENTS.md context/*.md; do
  [ -f "$f" ] && printf '%-34s %6s bytes  ~%5s tok\n' "$f" "$(wc -c <"$f")" "$(( $(wc -c <"$f") / 4 ))"
done
```

Report a table to the user: file, size, budget, verdict (OK / over). Include the
estimated **per-session saving** the compact pass would deliver (sum of the overages,
plus the digest saving below if the project has no digest yet).

## 2. Propose, then compress (approval required per file)

Never trim meaning: compression rewrites for density — it does not drop facts,
invariants, decisions, or scope statements without explicit user approval. For each
over-budget file, propose the appropriate treatment and apply only what the user
approves:

- **`progress-tracker.md`** — rotate: move older Completed entries and Session Notes
  into `context/progress-archive.md`, per the active-window rules in
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-build/references/close-unit.md`.
- **Core files** (`architecture.md`, `ui-context.md`, `code-standards.md`,
  `project-overview.md`, `ai-workflow-rules.md`) — tighten prose (cut filler,
  merge repetition, convert paragraphs to dense bullets), and move long
  examples/tables that are rarely needed into an on-demand file under
  `context/reference/` with a one-line pointer left behind. Show a before/after
  summary for each file before writing.
- **Entry point** (`CLAUDE.md`/`AGENTS.md`) — keep only the tiered-loading contract
  and pointers; move anything bulky into `context/`.
- **`lessons.md`** — dedupe/generalize overlapping lessons, **promote** lessons that
  have become real conventions into `code-standards.md` / `ai-workflow-rules.md` /
  `architecture.md`, and drop lines about code that no longer exists (rules:
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md`).
- **Specs and archives** — leave alone. `specs/archived/` and
  `progress-archive.md` are never auto-read, so they cost nothing.

## 3. (Re)generate the digest

The digest is Tier 1 — injected every session by the `SessionStart` hook — so it must
be accurate and tiny (~2.5 KB / ~600 tokens):

- **No digest yet** → create `context/context-digest.md` from the template at
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/context-digest.md`,
  filled from the (now compacted) six files. This is the single biggest saving for
  older projects: the hook stops injecting the full tracker.
- **Digest exists** → regenerate it from the current files so it reflects
  post-compaction reality; keep the State section current with the tracker.

## 4. Report

Summarize: what was rotated/tightened/moved, the new size table, and the estimated
tokens saved per session (before → after). Suggest committing the compaction as a
`chore:` commit so the history is clean.

## Rules

- Read the full six files (Tier 3) before compressing — never compress what you
  haven't read.
- One approval per file write; show before/after for anything rewritten.
- Never delete `progress-archive.md`, `specs/archived/`, or `context/reference/`
  content — moved history must stay recoverable.
- If nothing is over budget and a digest exists, say so and stop — this skill is
  maintenance, not busywork.
