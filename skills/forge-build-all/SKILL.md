---
name: forge-build-all
description: >
  This skill should be used to build every remaining unit in a Six-File Context
  Methodology project in one continuous run — phrases like "forge-build-all", "build
  all units", "run the whole build", "build everything", "loop until the build plan is
  done", "finish all the specs", or "autonomous build". It runs the implement → verify →
  close loop for each pending unit in order, updating the tracker after each, and stops
  on the first failure.
metadata:
  version: "0.1.0"
---

# forge-build-all

Run the build loop across ALL remaining units, in order, until the build plan is complete
or a unit fails. This is the autonomous, multi-unit version of `forge-build`.

Because this runs many units without a human checkpoint between each, it is deliberately
conservative: it builds strictly to each spec, verifies every unit, and **stops at the
first failure** rather than barreling ahead on a broken foundation.

## Preconditions

- The project is set up (run the detector via `forge-init` if unsure) and has a build
  plan at `context/specs/00-build-plan.md`.
- Read the entry point, `architecture.md` (invariants), `code-standards.md`,
  `ui-context.md`, and `progress-tracker.md` once at the start for shared context.

If there is no build plan, stop and tell the user to run `forge-spec` first.

## Scope of the run

By default, build every unit that is not yet complete, in build-plan order. Honor an
optional user-specified scope when given, e.g. "build units 3 through 7" or "build the
next 3 units" or "build until unit 10". Confirm the resolved scope (which units, in what
order) with the user before starting the run.

## The loop (repeat per unit, in order)

For each pending unit N:

1. **Check the spec.** Require `context/specs/NN-*.md`. If it is missing, STOP the run and
   tell the user to generate it with `forge-spec` (do not invent a spec).
2. **Mark in progress** in `context/progress-tracker.md`.
3. **Implement exactly the spec** — only what its Implementation section describes. Use
   the tokens/patterns in `ui-context.md` and `code-standards.md`. Install only the
   dependencies the spec lists. Do not touch protected files. Do not expand scope or pull
   work from other units; note any discovered out-of-scope work as an open question.
4. **Verify** against the spec's "Verify when done" checklist and run the project's real
   build/typecheck/lint. For deeper checking, apply the `forge-verify` logic.
5. **Decide:**
   - **Pass** → mark the unit complete in `progress-tracker.md`, set the next unit as
     "Next Up", add a **one- to two-line** Session Note, **rotate the tracker** if it has
     grown past its active window (~10 recent Completed, ~8 recent Session Notes, or
     ~6 KB / ~1,500 tokens) by moving the oldest entries into `context/progress-archive.md`
     (append newest-first; the archive is never read on resume/build), **move its spec
     `context/specs/NN-*.md` into `context/specs/archived/`, and move its line in
     `context/specs/00-build-plan.md` from the active `## Units` list into the
     `## Completed` section**, then continue to the next unit.
   - **Fail / ambiguous / invariant violation** → **STOP the entire run.** Leave the unit
     as "In Progress", record exactly what failed and why in the tracker, and report to
     the user. Do not proceed to later units.

## Stop conditions (any of these ends the run)

- A unit's verification fails or its build/typecheck/lint does not pass.
- A required spec file is missing.
- The spec is ambiguous or would require a decision that belongs in another unit.
- An `architecture.md` invariant would be violated.
- All units in scope are complete (successful completion).

## After the run

Report a summary: which units were completed this run, where it stopped (and why, if it
stopped early), and the clear next step. Suggest the user review the changes and, per
unit or in a batch, ship them with `forge-pr`.

## Hard rules

- One unit fully complete (built AND verified) before starting the next.
- Never expand a unit's scope; never merge units silently.
- Never mark a unit complete with failing checks or partial work.
- Archive each completed unit's spec to `context/specs/archived/` as you go, so the active
  `specs/` folder always shows only what's left.
- Stop on the first failure — do not continue building on an unverified unit.
- Do not auto-push or open PRs as part of this run; leave shipping to `forge-pr` so the
  user keeps control of git history.
- Keep `progress-tracker.md` accurate AND lean after every unit — rotate old Completed/
  Session Notes into `context/progress-archive.md` so the active tracker never bloats.
