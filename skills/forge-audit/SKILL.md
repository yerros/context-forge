---
name: forge-audit
description: >
  This skill should be used to check whether a project's context files still match the
  actual codebase — phrases like "forge-audit", "audit the context files", "are the
  docs still accurate", "check for context drift", or "sync context with the code". It
  compares each of the six files against real evidence in the repo and reports drift,
  then offers to update the docs.
metadata:
  version: "0.20.0"
---

# forge-audit

Detect and fix drift between the six context files and the real codebase. Over a long
build the code moves on; stale context files quietly make the agent guess wrong. This
skill keeps them honest.

## Argument

Text after the command narrows the audit (e.g. `/forge-audit architecture` or
`/forge-audit just the budgets`) — run only the matching sections below. No argument
→ full audit.

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

For the evidence gathering, delegate to the `forge-scout` agent (haiku-pinned,
read-only): give it the concrete claims extracted from each context file (mission
"drift evidence") and let it report confirmed/drifted/gone with file:line evidence —
the sweep stays out of this session's context. Judging the findings and recommending
doc edits stays here. If the agent is unavailable, verify in-session.

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

### context-digest.md (Tier 1 accuracy)

The digest is injected every session by the `SessionStart` hook, so a stale digest
misleads every session:

- If the detector reports `digest: no`, flag it and recommend generating one with
  `forge-compact` — it's the biggest per-session token saving available.
- If present, check it against the files it summarizes: does the State section match
  the tracker? Do the top invariants still match `architecture.md`? Is it within its
  ~2.5 KB budget? Flag any disagreement — the full file wins, and the digest should
  be regenerated.

### lessons.md (memory hygiene)

If `context/lessons.md` exists: flag lessons that contradict the current context
files (one of them is wrong — usually the lesson is stale), lessons about code that
no longer exists, and lessons that have clearly become conventions and should be
promoted into `code-standards.md` / `ai-workflow-rules.md` (per
`${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md`). Check it's within
its ~1.5 KB budget.

### context budget (token cost)

The Tier 1 files are re-read every session and the others per task, so their size is
a recurring token cost. Measure each file (bytes / ~tokens) and compare against the
canonical soft budgets in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-resume/references/token-economy.md` (which also
contains the measurement snippet). Report each file's size, whether it's within
budget, and the recommended fix when it isn't (rotate the tracker, regenerate the
digest, tighten or split core files) — or a single `forge-compact` run for a guided
pass. Rotating completed history is a pure token saving with no loss of active
context.

## Output

A drift report grouped by file, plus the **context budget** summary above. For each
finding: **what the doc says**, **what the code shows**, and a **recommended doc
edit**. Categorize:

- **Stale** — doc describes something that's changed.
- **Undocumented** — code has something the docs don't mention.
- **Violation** — code breaks a documented invariant or standard (this is a code
  problem, not a doc problem — call it out separately).

Then offer to apply the recommended documentation updates. Apply only what the user
approves. For violations, recommend fixing the code (or consciously updating the
invariant) rather than silently rewriting the rule.
