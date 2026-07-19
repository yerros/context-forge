---
name: forge-reconcile
description: >
  This skill should be used to detect and adopt work done OUTSIDE the Context Forge
  process — phrases like "forge-reconcile", "someone committed without the process",
  "changes bypassed the workflow", "adopt these manual changes", "there are commits
  not in the tracker", or "bring out-of-band work back into the process". It finds
  commits with no unit/spec trail, analyzes them via the forge-scout agent, and —
  with approval — adopts each group as a retroactive spec plus tracker entry, so no
  work stays invisible to future sessions. Distinct from forge-audit (docs vs code
  content drift): this reconciles the PROCESS trail (git history vs tracker/specs).
metadata:
  version: "0.36.0"
---

# forge-reconcile

Work sometimes lands outside the forge loop: a manual hotfix, a teammate's commit, a
Claude session that skipped `forge-build`. The code moves, but the tracker, specs,
and context files never hear about it — and every later session works from a map
that's missing roads. This skill closes that gap: detect the out-of-band (OOB)
commits, understand them, and **adopt them back into the process** as first-class
history (retro-spec + tracker entry), or consciously dismiss them.

Division of labor with the neighbors: `forge-audit` fixes what the context files
*say* (docs vs code). `forge-reconcile` fixes what the process *knows* (git history
vs tracker/specs). A reconcile often ends by recommending a narrow `forge-audit`
pass when the adopted work changed architecture or scope.

## Argument

Text after the command narrows the scope (e.g. `/forge-reconcile last 5 commits` or
`/forge-reconcile abc1234`) — restrict analysis to the matching commits. No
argument → everything the detector reports.

## First: detect

Run the deterministic detector (read-only):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-reconcile/scripts/detect-oob.sh"
```

Interpret the verdict:

- `NO_CONTEXT` — no tracker; nothing to reconcile against. Point the user to
  `forge-init`.
- `NO_EPOCH` — the tracker exists but was never committed, so there is no adoption
  baseline. Recommend committing the context dir first; offer to do it.
- `CLEAN` with `dirty_tree: no` — the process trail is complete. Say so and stop.
- `CLEAN` with `dirty_tree: yes` — no OOB commits, but uncommitted work exists (the
  `dirty:` lines). Handle it under "Uncommitted work" below.
- `OOB` — the `oob:` lines (`sha|date|subject|n_files`) are the work to reconcile.

The same script backs the `SessionStart` hook (`--hook` mode), so sessions get a
token-free warning when OOB commits exist; this skill is the follow-up.

## Analyze

**Group** the OOB commits into logical clusters — commits that touch the same files
or clearly serve one intent (a fix + its follow-up = one cluster). Most reconciles
have 1–3 clusters.

**Delegate the diff reading** to the `forge-scout` agent (haiku-pinned, read-only),
one mission per cluster: give it the shas and ask for (a) what the change actually
does, in behavior terms, (b) files touched and any new dependencies, (c) whether it
violates any invariant in `architecture.md` or convention in `code-standards.md` /
`patterns.md` (give the scout those concrete claims), and (d) whether tests exist
for it. The scout returns compact findings; judging them stays here. If the agent
is unavailable, read the diffs in-session (`git show --stat` first, full diff only
where needed).

## Present the plan

Before writing anything, show the user one entry per cluster:

- **What it is** — the scout's behavioral summary, with commit shas.
- **Standing** — clean / violates invariant X / untested / undocumented dependency.
- **Proposed adoption** — retro-spec title + tracker line, plus any follow-ups
  (a `forge-decision` if it embodies an architecture choice, a fix unit if it
  violates an invariant, a test unit if it shipped untested).
- **Or dismissal** — trivial noise (typo fixes, formatting, generated files) is
  cheaper to ignore than to document: offer the `.reconcile-ignore` line instead.

Adopt only what the user approves, cluster by cluster.

## Adopt (per approved cluster)

1. **Write the retro-spec** to `context/specs/archived/R-YYYYMMDD-slug.md` —
   archived directly, because the work is already done. Use the six-section spec
   shape, written after the fact and marked as such:

   ```markdown
   # R-YYYYMMDD-slug — <title>  (RETROACTIVE)

   > Adopted by forge-reconcile on YYYY-MM-DD. This spec documents work done
   > outside the process; it was written after the implementation.

   ## Goal            — inferred intent, in one or two lines
   ## What was built  — behavior + files, from the scout's findings
   ## Source commits  — <sha> <date> <subject>, one per line
   ## Dependencies    — anything new it pulls in
   ## Tests           — what covers it (or "none — follow-up unit proposed")
   ## Standing        — invariant/standards check result
   ```

2. **Update the tracker.** Add a Completed entry `R-YYYYMMDD-slug (retroactive)`
   and a one-line Session Note ("adopted OOB work: <title>"). Respect the active
   window and rotation rules in
   `${CLAUDE_PLUGIN_ROOT}/skills/forge-build/references/close-unit.md`.
3. **Tidy the build plan.** Add the unit to the `## Completed` section of
   `context/specs/00-build-plan.md`, marked retroactive. If the adopted work
   overlaps a *pending* unit, flag it — the pending spec may now be partly done
   and needs a scope note.
4. **Sync the context files.** If the work changed stack, boundaries, scope, or
   conventions, update `architecture.md` / `project-overview.md` /
   `code-standards.md` now (this is the forge-audit half of the job — for large
   drift, recommend a narrow `/forge-audit` pass instead of improvising).
5. **Route the judgments.** Architecture choice embedded in the work → offer
   `forge-decision`. Invariant violation → do NOT silently rewrite the invariant;
   propose a fix unit (via `forge-feature`/`forge-fix`) or a conscious
   `forge-decision` changing the rule. Missing tests → propose a test unit.
6. **Refresh** the retrieval index and the digest State section per the close-unit
   procedure (steps 6–7 there), if the project has them.
7. **Capture the meta-lesson** when a pattern emerges (e.g. "hotfixes keep
   bypassing the process") via `forge-lesson` — one line, only if it generalizes.

## The bookkeeping commit

Finish with ONE commit that contains all reconcile artifacts (retro-specs, tracker,
build plan, context edits) and **marks the adopted commits as handled** so the
detector never flags them again:

```
chore(forge): reconcile out-of-band work

- adopted: <retro-spec titles>

Reconciles: <sha> <sha> <sha>
```

The `Reconciles:` line (short shas, space-separated) is the detector's exclusion
marker — do not omit it. Dismissed-not-adopted commits go into
`context/.reconcile-ignore` instead (one short sha per line, optional comment
after it); commit that file too.

## Uncommitted work

For `dirty:` findings (uncommitted OOB changes), triage with the user:

- **Keep in-process** — if it maps to a pending unit, route to the normal
  `forge-build` loop and let its close procedure record it. No reconcile needed.
- **Adopt** — treat like a cluster: scout it, retro-spec it, and fold it into the
  bookkeeping commit (the work and its documentation ship together — no
  `Reconciles:` sha needed since it was never a separate commit).
- **Discard** — if it's abandoned noise, offer `git checkout/clean` on the
  affected paths (destructive: confirm first, never touch paths the user didn't
  approve).

## Output

End with a short reconciliation report: clusters found → adopted / dismissed /
routed, artifacts written, and any follow-up units or decisions proposed. The
definition of done: running the detector again reports `CLEAN`.
