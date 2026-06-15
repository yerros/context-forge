---
name: forge-audit
description: >
  This skill should be used to check whether a project's context files still match the
  actual codebase — phrases like "forge-audit", "audit the context files", "are the
  docs still accurate", "check for context drift", or "sync context with the code". It
  compares each of the six files against real evidence in the repo and reports drift,
  then offers to update the docs.
metadata:
  version: "0.1.0"
---

# forge-audit

Detect and fix drift between the six context files and the real codebase. Over a long
build the code moves on; stale context files quietly make the agent guess wrong. This
skill keeps them honest.

## First: read the state

Run the deterministic detector to know exactly what exists before auditing (read-only):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/detect.sh"
```

If the `verdict` is `SETUP` (no context files), there's nothing to audit — tell the user
to run `forge-init` first. Otherwise proceed.

## How to audit

Read the six files in `context/`, then compare each against evidence in the repo. Do
NOT trust the docs — verify against the code.

### architecture.md

- Re-read `package.json` / lockfile / equivalent. Compare the declared stack table to
  the dependencies actually installed. Flag tech listed that's gone, and tech in use
  that's undocumented.
- Compare the documented system boundaries to the actual top-level folder structure.
- Spot-check each invariant: is there code that violates it? Flag violations.

### code-standards.md

- Open several representative source files. Check whether the documented conventions
  (TypeScript strictness, component patterns, API structure, naming) still match what's
  written in the code. Flag rules the code no longer follows.

### ui-context.md

- Compare documented color tokens / typography / radius scale against the real theme,
  Tailwind config, or token file. Flag tokens that drifted or were added.

### project-overview.md

- Check whether shipped features (evident from routes/folders) are reflected, and
  whether anything in "Out of Scope" has quietly been built.

### progress-tracker.md

- Check whether "Completed" matches what actually exists, and whether "In Progress" is
  stale.

### specs/ vs build plan (archive hygiene)

- Every unit marked complete should have its spec under `context/specs/archived/` and its
  line in the `## Completed` section of `context/specs/00-build-plan.md` — not in the
  active `## Units` list or loose in `context/specs/`. Flag completed units whose spec is
  still active (not archived), and pending units whose spec was archived too early.

### context budget (token cost)

The six files (plus the entry point) are re-read on every `forge-resume` / `forge-build`,
so their size is a recurring token cost. Measure it and flag bloat:

```bash
for f in CLAUDE.md AGENTS.md context/*.md; do
  [ -f "$f" ] && printf '%-34s %6s bytes  ~%5s tok\n' "$f" "$(wc -c <"$f")" "$(( $(wc -c <"$f") / 4 ))"
done
```

Soft budgets (warn when exceeded):

- `progress-tracker.md` — **~6 KB / ~1,500 tokens.** This is the most common offender: it
  grows every unit. Over budget ⇒ recommend rotating old Completed entries and Session
  Notes into `context/progress-archive.md` (history, never auto-read).
- `architecture.md`, `ui-context.md`, `code-standards.md`, `project-overview.md` —
  **~10 KB / ~2,500 tokens** each. Over budget ⇒ recommend tightening prose, removing
  examples, or splitting detail into an on-demand reference file.
- Entry point (`CLAUDE.md`/`AGENTS.md`) — keep lean; large embedded tables/reference
  blocks belong in a separate file that's read only when needed.

Report each file's size, whether it's within budget, and the recommended trim/rotate when
it isn't. Rotating completed history is a pure token saving with no loss of active context.

## Output

A drift report grouped by file, plus the **context budget** summary above. For each finding: **what the doc says**, **what the
code shows**, and a **recommended doc edit**. Categorize:

- **Stale** — doc describes something that's changed.
- **Undocumented** — code has something the docs don't mention.
- **Violation** — code breaks a documented invariant or standard (this is a code
  problem, not a doc problem — call it out separately).

Then offer to apply the recommended documentation updates. Apply only what the user
approves. For violations, recommend fixing the code (or consciously updating the
invariant) rather than silently rewriting the rule.
