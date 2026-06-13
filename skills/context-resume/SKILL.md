---
name: context-resume
description: >
  This skill should be used at the start of a work session on a project that uses the
  Six-File Context Methodology — phrases like "context-resume", "resume the project",
  "where did we leave off", "pick up where we stopped", "restore context", or "read
  the context files and continue". It reloads full project context from the six files
  and the progress tracker so work continues without drift.
metadata:
  version: "0.1.0"
---

# context-resume

Restore full project context in one step and continue the build without re-explaining
the project. This solves the "AI has no memory between sessions" problem.

## What to do

0. Confirm the project is set up. Run the deterministic detector (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/context-init/scripts/detect.sh"
   ```

   If the `verdict` is `SETUP`, there's nothing to resume — suggest `context-init`. If
   `REPAIR` (incomplete), mention which files are missing and suggest `context-init`'s
   reconcile flow, then resume with what exists.

1. Read the entry point (`CLAUDE.md` or `AGENTS.md`) at the project root, then read the
   six files **in order**:
   1. `context/project-overview.md`
   2. `context/architecture.md`
   3. `context/ui-context.md`
   4. `context/code-standards.md`
   5. `context/ai-workflow-rules.md`
   6. `context/progress-tracker.md`

   If `context/` doesn't exist, tell the user and suggest running `context-init` first.

2. From `progress-tracker.md`, extract: current phase, current goal, what's completed,
   what's in progress, what's next up, and any open questions or recent architecture
   decisions. If `context/.last-session.md` exists (written by the Stop hook), read it too
   for a deterministic list of the most recently changed files — useful when the tracker
   wasn't updated by hand.

3. Give the user a short status briefing: where the project stands, what was last done,
   and the next unit to build. Surface any open questions that need a decision before
   continuing.

4. If a "Next Up" unit exists and has a spec in `context/specs/`, offer to start it
   using the implement prompt. If it has no spec yet, suggest running `context-spec` to
   write one first.

## Rules while resuming

- Honor `ai-workflow-rules.md`: one unit at a time, stay within scope, don't invent
  behavior that isn't in the context files.
- Respect the invariants in `architecture.md` and the protected files list.
- Update `progress-tracker.md` after each meaningful change, and update the relevant
  context file if implementation changes the architecture, scope, or standards.
