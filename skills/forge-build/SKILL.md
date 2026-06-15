---
name: forge-build
description: >
  This skill should be used to implement one build unit in a project that uses the
  Six-File Context Methodology — phrases like "forge-build", "build unit NN", "run
  the build loop", "implement the next unit", or "build the next spec". It runs the
  disciplined implement → verify → close loop for a single spec'd unit and keeps the
  progress tracker in sync.
metadata:
  version: "0.1.0"
---

# forge-build

Run the three-prompt build loop for ONE unit, end to end, without scope drift. This is
the execution engine of the methodology: the spec defines the work, this loop does
exactly that work and nothing more.

## Preconditions

- The project has `context/` and an entry point (`CLAUDE.md`/`AGENTS.md`).
- The target unit has a spec at `context/specs/NN-feature-name.md`. If it doesn't,
  stop and tell the user to run `forge-spec` first.

If no unit is specified, read `context/progress-tracker.md` and pick the "Next Up"
unit. Confirm the target unit with the user before starting.

## The loop

### 1. Load

Read, in order: the entry point, `context/architecture.md` (invariants),
`context/code-standards.md`, `context/ui-context.md`, and the unit's spec file. The
spec is the source of truth for what to build.

### 2. Mark in progress

Update `context/progress-tracker.md`: move this unit into "In Progress", set "Current
Goal" to the unit's goal.

### 3. Implement — exactly the spec, nothing more

- Build only what the spec's Implementation section describes.
- Use the tokens and patterns in `ui-context.md` and `code-standards.md` — make no
  visual or structural guesses.
- Install only the dependencies the spec lists, and only when first needed.
- Do NOT touch protected files listed in `ai-workflow-rules.md`. Do NOT add features,
  refactors, or "improvements" outside this unit's scope. If you discover work that
  belongs to another unit, note it as an open question in the tracker instead of doing it.

### 4. Verify against the checklist

Check every item in the spec's "Verify when done" section. Run the project's real
build/typecheck/lint command. If any check fails, fix only what's needed to pass —
stay in scope. For a deeper pass, run the `forge-verify` skill.

If something built doesn't match the spec, correct it precisely:
> "The [element] does not match the spec. Expected: [X]. Current: [Y]. Fix only this."

### 5. Close

Only when every verification item passes:

- Update `context/progress-tracker.md`: move the unit to "Completed", set the next unit
  as "Next Up", and add a **one- to two-line** Session Note (what shipped + any decision).
  Keep notes terse — this file is read on every resume/build, so every line costs tokens.
- **Rotate the tracker if it has grown.** The tracker holds an *active window* only:
  current phase/goal, In Progress, Next Up, Open Questions, the ~10 most recent Completed
  units, and the ~8 most recent Session Notes. When closing pushes it past that window (or
  past ~6 KB / ~1,500 tokens), move the oldest Completed entries and Session Notes into
  `context/progress-archive.md` (create it if absent; append newest-first). The archive is
  history — it is NOT read on resume/build, so rotating it out is a pure token saving with
  no loss of active context.
- **Archive the spec.** Move `context/specs/NN-feature-name.md` into
  `context/specs/archived/` (create the folder if it doesn't exist). The active
  `context/specs/` folder should now contain only specs for units still pending.
- **Tidy the build plan.** In `context/specs/00-build-plan.md`, move this unit's line out
  of the active `## Units` list into the `## Completed` section at the bottom (add the
  date and, once shipped, the PR/branch). This keeps the active list short and current.
- If implementation changed the architecture, scope, or standards, update the relevant
  context file (`architecture.md` / `code-standards.md` / `project-overview.md`).
- Tell the user the unit is complete and verified, and suggest the suggested git step:
  `push branch feat/NN-feature-name`.

## Hard rules

- One unit per loop. Never combine units.
- Never expand scope beyond the spec.
- Never mark a unit complete with failing checks or partial implementation.
- A closed unit's spec belongs in `context/specs/archived/`, not the active `specs/` folder.
- The tracker must reflect reality before the loop ends.
