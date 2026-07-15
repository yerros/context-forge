# Close-unit procedure (shared reference)

The single source of truth for closing a completed, verified unit. Used by
`forge-build` (step 5), `forge-build-all` (per-unit Pass decision), and `forge-pr`
(step 4). If the close rules or window numbers ever change, change them HERE only.

## Active-window numbers (canonical)

`context/progress-tracker.md` holds an **active window** only:

- current phase/goal, In Progress, Next Up, Open Questions
- the **~10 most recent** Completed units
- the **~8 most recent** Session Notes
- soft size cap: **~6 KB / ~1,500 tokens**

Anything older rotates into `context/progress-archive.md` — history, appended
newest-first, **never auto-read** on resume/build.

The whole procedure below is mechanical — it can be delegated to the
`forge-archivist` agent (haiku-pinned) with the unit number/name, the session note,
and the next-up unit; it follows this file exactly and reports the file operations
performed. Steps 5, 8, and 9 involve judgment (what changed, what generalizes, what repeats) — decide
those in-session and pass the conclusions to the archivist, or run the steps
yourself if the agent is unavailable.

## Steps

1. **Update the tracker.** In `context/progress-tracker.md`: move the unit to
   "Completed", set the next unit as "Next Up", and add a **one- to two-line**
   Session Note (what shipped + any decision). Keep notes terse — this file is
   read on every resume/build, so every line costs tokens. **Clear the unit's
   attempt log** (the `attempt N:` lines under its In Progress entry) — it served
   its purpose; a recurring root cause becomes a lesson (step 8) before the log
   goes.
2. **Rotate the tracker if it has grown** past the active window above: move the
   oldest Completed entries and Session Notes into `context/progress-archive.md`
   (create it if absent; append newest-first). Pure token saving — no loss of
   active context.
3. **Archive the spec.** Move `context/specs/NN-feature-name.md` into
   `context/specs/archived/` (create the folder if it doesn't exist). The active
   `context/specs/` folder must only contain specs for units still pending.
4. **Tidy the build plan.** In `context/specs/00-build-plan.md`, move this unit's
   line out of the active `## Units` list into the `## Completed` section at the
   bottom (add the date and, once shipped, the PR/branch).
5. **Sync the context files.** If implementation changed the architecture, scope,
   or standards, update the relevant file (`architecture.md` / `code-standards.md`
   / `project-overview.md`) before continuing.
6. **Refresh the retrieval index** (if the project has one — `.index.db` in the
   context dir): run
   `bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/forge-index.sh" build` —
   one cheap command, so the just-archived spec and new decisions stay findable.
7. **Refresh the digest.** In `context/context-digest.md` (if the project has one),
   update the **State** section (phase, last completed, next up) — a three-line
   edit. If step 5 changed what the digest summarizes (stack, invariants, key
   conventions), update those digest lines too, keeping it within its ~2.5 KB
   budget.
8. **Capture lessons.** If the user corrected the agent's approach during this unit
   in a way that generalizes beyond it (a rejected pattern, a misunderstood
   convention, a diagnosis that cost real effort), distill it to one line and append
   it to `context/lessons.md` per
   `${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md` — show the user
   the line. Most units produce no lesson; don't force one.
9. **Register the pattern.** If this unit established an implementation shape that
   sibling features will repeat (the first CRUD feature, the first list screen, the
   first API route), add an entry to `context/patterns.md` (create from the
   forge-init template if absent): pattern name, this unit's files as the
   **exemplar**, and 3–5 must-match bullets. Show the user the entry. This is what
   keeps feature #2..#n in the same dialect as feature #1.

## Shipping

Shipping is `forge-pr`'s job — branch `feat/NN-feature-name`, conventional commit,
PR with a spec-derived summary. Do not push or open PRs from the close step itself;
suggest `forge-pr` to the user instead.
