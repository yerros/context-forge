# Review ledger (shared reference)

The persistent memory of a review across passes. Without it, every pass starts
from zero: it re-litigates what was already swept clean, misses what was never
swept, and cannot prove that a previously found bug is actually gone. The ledger
turns a sequence of stochastic passes into cumulative, auditable coverage.

One ledger per review scope, at `<context-dir>/reviews/<scope-id>.md` (under
`context/` or `.forge/`, whichever the project uses; `.forge-reviews/` at repo
root when there is no context dir) — `pr-42`, `branch-feat-07-auth`, or
`worktree-<date>` for local changes. Create the `reviews/` folder if absent. The ledger is working state, not history: when the
scope merges (or the review is abandoned), delete the file — anything worth
keeping became a lesson or a fix.

## Format

```markdown
# Review: <scope-id>
Base: <base ref @ SHA> · Head: <head SHA at last pass> · Pass: <N>

## Inventory
| # | File / hunk (function) | Lenses due | Status |
|---|------------------------|-----------|--------|
| 1 | src/auth/login.ts — validateSession() | std, err, types | clean (pass 2) |
| 2 | src/auth/login.ts — refreshToken()    | std, err        | F3 open |
...

## Findings
| # | file:line | Lens | Severity | What | Status |
|---|-----------|------|----------|------|--------|
| F1 | src/auth/login.ts:41 | errors | Critical | catch swallows TokenError | verified-fixed (pass 2: test auth.spec.ts:12 red→green) |
| F2 | ... | ... | Important | ... | open |
...

## Pass log
- pass 1 (<date>, head <SHA>): lenses std,err,types over items 1–14 → F1–F4. RECOMMEND CHANGES.
- pass 2 (<date>, head <SHA>): re-verified F1 (fixed), F2 (still open); fix-diff items 15–17 reviewed → F5. PR comment posted. RECOMMEND CHANGES.
```

For PR scopes, each pass log line notes whether the fix-round PR comment was
posted (per the Convergence section in SKILL.md).

## Rules

1. **Inventory before opinions.** Pass 1 enumerates the diff mechanically
   (`git diff --stat` + per-file hunks, named by function/section) into numbered
   items before any lens runs. A lens is finished with an item only when the item
   carries that lens's verdict — clean or a finding number. **An unmarked item is
   an unreviewed item**, and the pass may not report a verdict while any due
   item×lens cell is unmarked.
2. **Every later pass reads the ledger first.** Three obligations, in order:
   re-verify every finding marked `fixed` against the current code — with cited
   evidence (the regression test red→green, or file:line) — promoting it to
   `verified-fixed` or reopening it; dedupe new findings against existing ones
   (same root cause → same F-number, never a fresh discovery); add the hunks new
   since the last pass (the fixes) as **new inventory items** and review them like
   any other — fixes are new code and get no lighter treatment.
3. **Statuses are earned, not asserted.** `fixed` is what a fixer claims;
   `verified-fixed` is what a reviewer proved with fresh evidence
   (loop-contract § claims require evidence). Only `verified-fixed` counts toward
   convergence.
4. **A finding that reopens twice is not a review problem** — it is a diagnosis
   problem. Route it to `forge-debug` with the ledger's history for that finding.
5. **On disk, always.** The ledger is updated as the pass runs, not summarized at
   the end from memory — it must survive compaction and session loss
   (loop-contract § state survives compaction).
