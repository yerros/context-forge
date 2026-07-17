---
name: forge-resume
description: >
  This skill should be used at the start of a work session on a project that uses the
  Context Forge methodology — phrases like "forge-resume", "resume the project",
  "where did we leave off", "pick up where we stopped", "restore context", or "read
  the context files and continue". It restores project context tier by tier (digest
  and tracker first, full files only as the task requires) so work continues without
  drift and without burning tokens.
metadata:
  version: "0.25.2"
---

# forge-resume

Restore project context in one step and continue the build without re-explaining the
project. This solves the "AI has no memory between sessions" problem — without paying
for context the session doesn't need. Loading follows the tier system defined in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-resume/references/token-economy.md`.

## Argument

Text after the command sets the session's focus (e.g. `/forge-resume unit 05` or
`/forge-resume the payment bug`) — resume as below, then steer step 4 to that focus
and load its Tier 2 file(s). No argument → standard resume to whatever is Next Up.

## What to do

0. Confirm the project is set up. Run the deterministic detector (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/detect.sh"
   ```

   If the `verdict` is `SETUP`, there's nothing to resume — suggest `forge-init`. If
   `REPAIR` (incomplete), mention which files are missing and suggest `forge-init`'s
   reconcile flow, then resume with what exists.

1. **Tier 1 — always.** Read the entry point (`CLAUDE.md` or `AGENTS.md`), then
   `context/context-digest.md` (if present), then `context/progress-tracker.md` —
   stable files first, the volatile tracker last, so the unchanged prefix stays
   prompt-cache-friendly across sessions.

   If there is **no digest** (project pre-dates it), fall back to reading the six
   files in full, in order: project-overview, architecture, ui-context,
   code-standards, ai-workflow-rules, progress-tracker — and suggest generating a
   digest with `forge-compact` so future resumes are cheaper.

   If `context/` doesn't exist, tell the user and suggest running `forge-init` first.

   **Tier 2 — per task.** Do NOT read the remaining context files now. Once the next
   task is known (step 4), read only the file(s) that task touches, per the tier map
   in the digest / token-economy.md. Never guess: if a decision depends on a file you
   haven't read, read it first.

   **History via the index, not grep.** When the session's focus needs past
   context (a related decision, an archived spec, an old lesson) and the project
   has a retrieval index (`.index.db` in the context dir), query it —
   `bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/forge-index.sh" query "<focus terms>"`
   — and read only the hits. Zero tokens for the search itself.

   Do **not** read `context/progress-archive.md` or `context/specs/archived/` — that
   is rotated-out history, not active context; open it only if the user explicitly
   asks about past work.

1b. **Post-parallel reconciliation.** If parallel worktrees were in play (claims
   exist in `$(git rev-parse --git-common-dir)/forge-claims/`, or recently-merged
   `feat/NN` branches touched the tracker), reconcile once on main: refresh the
   digest's State section from the merged tracker, rebuild the retrieval index
   (`forge-index.sh build`), and surface stale claims (worktrees finished but never
   `done`d) to the user.

2. From `progress-tracker.md`, extract: current phase, current goal, what's completed,
   what's in progress, what's next up, and any open questions or recent architecture
   decisions. If `context/.last-session.md` exists (written by the Stop hook), read it too
   for a deterministic list of the most recently changed files — useful when the tracker
   wasn't updated by hand.

3. Give the user a short status briefing: where the project stands, what was last done,
   and the next unit to build. Surface any open questions that need a decision before
   continuing.

4. If a "Next Up" unit exists and has a spec in `context/specs/`, offer to start it
   using the implement prompt. If it has no spec yet, suggest running `forge-spec` to
   write one first. (Completed units' specs live in `context/specs/archived/`; the active
   `context/specs/` folder lists only the units still pending — so what's there is the
   remaining work.)

## Rules while resuming

- Honor `ai-workflow-rules.md`: one unit at a time, stay within scope, don't invent
  behavior that isn't in the context files.
- Respect the invariants in `architecture.md` and the protected files list.
- Update `progress-tracker.md` after each meaningful change, and update the relevant
  context file if implementation changes the architecture, scope, or standards.
