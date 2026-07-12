---
name: forge-build
description: >
  This skill should be used to implement one build unit in a project that uses the
  Six-File Context Methodology — phrases like "forge-build", "build unit NN", "run
  the build loop", "implement the next unit", or "build the next spec". It runs the
  disciplined implement → verify → close loop for a single spec'd unit and keeps the
  progress tracker in sync.
metadata:
  version: "0.16.1"
---

# forge-build

Run the three-prompt build loop for ONE unit, end to end, without scope drift. This is
the execution engine of the methodology: the spec defines the work, this loop does
exactly that work and nothing more.

## Preconditions

- The project has `context/` and an entry point (`CLAUDE.md`/`AGENTS.md`).
- The target unit has a spec at `context/specs/NN-feature-name.md`. If it doesn't,
  stop and tell the user to run `forge-spec` first.

## Argument

Text after the command selects the unit (e.g. `/forge-build unit 04` or
`/forge-build the auth pages`) — match it against the build plan. No argument →
read `context/progress-tracker.md` and pick the "Next Up" unit. Either way, confirm
the target unit with the user before starting.

**Model recommendation:** if the unit's build-plan line carries
`[complexity: high]`, say so at confirmation and recommend switching to a stronger
model for this unit (`/model opus`) before implementing — a failed verify loop plus
a debug session costs more than the model-price difference. The user decides;
proceed either way.

## The loop

### 1. Load (tiered — don't read what the unit doesn't touch)

Read, in order: the entry point, `context/context-digest.md` (project brief + top
invariants; fall back to `context/architecture.md` if there is no digest),
`context/lessons.md` (if present — small, and it prevents repeating known mistakes),
and the unit's spec file. The spec is the source of truth for what to build.

Then read only the full context files this unit touches: `context/code-standards.md`
when writing code (nearly always), `context/ui-context.md` for UI work, and the full
`context/architecture.md` when the unit touches boundaries, storage, or dependencies.
Never guess — if the spec references something you haven't read, read that file first.
(Tier definitions: `${CLAUDE_PLUGIN_ROOT}/skills/forge-resume/references/token-economy.md`.)

### 2. Mark in progress

Update `context/progress-tracker.md`: move this unit into "In Progress", set "Current
Goal" to the unit's goal.

### 3. Implement — exactly the spec, nothing more

- Build only what the spec's Implementation section describes.
- **Write the unit's tests as you build** — the spec's Tests section is part of the
  implementation, not an afterthought. If the spec says "none — [reason]", skip;
  if the spec has no Tests section at all (older spec), propose the obvious tests
  and confirm with the user.
- Use the tokens and patterns in `ui-context.md` and `code-standards.md` — make no
  visual or structural guesses.
- Install only the dependencies the spec lists, and only when first needed.
- Do NOT touch protected files listed in `ai-workflow-rules.md`. Do NOT add features,
  refactors, or "improvements" outside this unit's scope. If you discover work that
  belongs to another unit, note it as an open question in the tracker instead of doing it.

### 4. Verify — an explicit loop with a hard escape

Run, in order: the unit's tests, the **full test suite** (regression gate — earlier
units must stay green), the project's real build/typecheck/lint, and every item in
the spec's "Verify when done" section. For a deeper pass, run the `forge-verify`
skill.

Then loop:

- **All green** → go to Close.
- **Something fails** → correct it precisely, staying in scope:
  > "The [element] does not match the spec. Expected: [X]. Current: [Y]. Fix only this."

  …then **re-run the verification from the top** (a fix can break something else).
- **The same check fails after two fix attempts** → STOP. Do not try a third blind
  fix — switch to `forge-debug` (stop-and-diagnose). Resume this loop only after the
  root cause is fixed.

### 5. Close

Only when every verification item passes, run the close-unit procedure in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-build/references/close-unit.md`: update and (if
needed) rotate the tracker, archive the spec to `context/specs/archived/`, tidy the
build plan, and sync any changed context files.

Then tell the user the unit is complete and verified, and suggest shipping it with
`forge-pr` (branch, conventional commit, and PR).

## Hard rules

- One unit per loop. Never combine units.
- Never expand scope beyond the spec.
- Never mark a unit complete with failing checks or partial implementation.
- A closed unit's spec belongs in `context/specs/archived/`, not the active `specs/` folder.
- The tracker must reflect reality before the loop ends.
