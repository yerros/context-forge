# Unit rules (shared reference)

The single source of truth for what a good build unit is and how units are ordered.
Used by `forge-spec` (Job A) and `forge-feature` (decompose step). If the rules
change, change them HERE only.

## What a unit is

A **unit** is a single, scoped, verifiable piece of work — small enough for one
focused session, concrete enough that "done" is unambiguous. "Build the project
sidebar with My Projects / Shared tabs, empty states, and open/close behavior, no
API calls yet" is a unit. "Build the dashboard" is a phase, not a unit.

## Rules for a good unit (apply all)

- Produces one visible, verifiable result.
- Stays within one system boundary (don't mix UI + DB + background work in one unit).
- Has a checklist of conditions that must be true before it's complete — including
  the automated tests it ships with (or an explicit "none — [reason]").
- Doesn't require decisions that belong to another unit.

## Ordering rules (apply all)

- **Dependencies first** — if B needs A, A comes first.
- **Security before functionality** — auth/access control before the features they
  protect.
- **Backend before frontend wiring** — build API routes, then wire the UI.
- **UI shells before real data** — component structure with placeholders, then
  connect.
- **Install dependencies just in time** — only when a package first unlocks real
  behavior.

## Complexity marker (per unit, in the build plan)

Assess each unit when planning and mark it in its build-plan line:

- **`[complexity: high]`** — any of: logic crossing multiple boundaries at once,
  concurrency / state machines / subtle data migrations, a large multi-file
  refactor, or a spec that cannot be made fully unambiguous (exploratory work).
  Add a short reason in parentheses.
- Everything else — no marker (standard is the default; don't label it).

The marker drives a model recommendation at build time: high-complexity units are
where a stronger implementation model pays for itself (a failed verify loop + a
debug session costs more than the model-price difference). It is a recommendation,
never a gate — the user always chooses.

## Validate the order

For each unit, confirm everything it depends on exists in an earlier unit. Merge
adjacent units that always ship together with no standalone result. When inserting
units into an existing plan (adding a feature), place them at the correct position
relative to existing units — never just append if there are dependencies either way;
renumber if necessary and note the renumbering.
