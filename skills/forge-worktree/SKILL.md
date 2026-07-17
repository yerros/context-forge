---
name: forge-worktree
description: >
  This skill should be used to run Context Forge builds in parallel across
  terminals — phrases like "forge-worktree", "build units in parallel", "work on
  two specs at once", "open another build in a new terminal", "claim unit 7", or
  "clean up the worktree". One unit = one git worktree = one branch = one terminal:
  it checks the unit is dependency-ready, claims it atomically (visible across all
  worktrees), creates the worktree, and hands the user the exact commands for the
  new terminal. Also lists claims and releases finished ones.
metadata:
  version: "0.25.1"
---

# forge-worktree

Parallel builds without collisions. Two sessions in one working tree WILL crash
into each other (shared test suite, shared git state, shared context files) — so
parallelism means isolation: each unit gets its own worktree and branch, and a
claim that every other terminal can see.

## Argument

- `/forge-worktree unit 07` (or `7 payments-crud`) → claim + create the worktree
  for that unit.
- `/forge-worktree list` → active claims and their ages.
- `/forge-worktree done 07` → release the claim, remove the (clean) worktree.

No argument → show `list` and offer to claim the next ready unit.

## Claiming a unit (`new`)

1. **Dependency gate.** Read `context/specs/00-build-plan.md`: the unit may only be
   claimed if every unit it depends on is in `## Completed`. Parallel work is for
   **independent** units — if it depends on something still in flight, refuse and
   say which unit blocks it. Its spec must exist (else: `forge-spec` first).
2. **Claim + create** (atomic, shared across worktrees):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-worktree/scripts/forge-worktree.sh" new <NN> <slug>
   ```

   A double claim loses cleanly ("ALREADY CLAIMED" + who/where). The script prints
   the exact next step — relay it verbatim to the user:
   open a **new terminal** → `cd <worktree-path> && claude` → `/forge-build unit NN`.
3. Remind: each parallel session burns quota independently — this buys wall-clock
   time, not tokens. Two or three parallel units is the sweet spot.

## While parallel (what forge-build does differently there)

`forge-build` detects it is in a linked worktree and applies **parallel mode**
(defined in close-unit.md): it verifies the unit matches the claim, edits only its
own unit's lines in the tracker, and defers the digest/index refresh to
reconciliation on main. Nothing for the user to configure.

## Finishing

Ship from the worktree with `forge-pr` as normal (the branch already exists). After
the PR merges:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-worktree/scripts/forge-worktree.sh" done <NN>
```

It refuses if the worktree still has uncommitted changes. Then, on main,
`/forge-resume` reconciles: pulls the merges, refreshes the digest State and the
retrieval index once for everything that landed.

## Rules

- One unit per worktree; never claim a unit whose dependencies aren't Completed.
- Never run two Claude sessions in the SAME directory — that is the crash this
  skill exists to prevent.
- Claims older than a day with no branch activity are probably stale — surface
  them in `list` output and ask before releasing someone's claim.
- Merge conflicts in the tracker after parallel merges are expected to be small
  (each session touched only its own lines) — resolve by keeping both units'
  entries.
