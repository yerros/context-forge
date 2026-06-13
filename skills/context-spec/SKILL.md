---
name: context-spec
description: >
  This skill should be used for spec-driven development on a project that uses the
  Six-File Context Methodology — phrases like "context-spec", "create a build plan",
  "break this into units", "write a spec for this feature", "generate a spec file",
  or "plan the build". It decomposes a project into ordered, verifiable build units
  and writes detailed per-feature spec files into context/specs/ that a coding agent
  implements exactly.
metadata:
  version: "0.1.0"
---

# context-spec

Turn features into spec-driven, buildable units. Two jobs: produce the **build plan**
(once per project) and write a **spec file** for each unit (right before building it).

Read `context/project-overview.md` and `context/architecture.md` first for context.
Specs live in `context/specs/`. Create that folder if it doesn't exist.

## Job A: the build plan (once)

When the user wants to plan the whole build, decompose the feature set into units.

A **unit** is a single, scoped, verifiable piece of work — small enough for one
focused session, concrete enough that "done" is unambiguous. "Build the project
sidebar with My Projects / Shared tabs, empty states, and open/close behavior, no API
calls yet" is a unit. "Build the dashboard" is a phase, not a unit.

Rules for a good unit:

- Produces one visible, verifiable result.
- Stays within one system boundary (don't mix UI + DB + background work in one unit).
- Has a checklist of conditions that must be true before it's complete.
- Doesn't require decisions that belong to another unit.

Ordering rules (apply all):

- **Dependencies first** — if B needs A, A comes first.
- **Security before functionality** — auth/access control before the features they protect.
- **Backend before frontend wiring** — build API routes, then wire the UI.
- **UI shells before real data** — component structure with placeholders, then connect.
- **Install dependencies just in time** — only when a package first unlocks real behavior.

Validate the order: for each unit, confirm everything it depends on exists in an
earlier unit; merge adjacent units that always ship together with no standalone result.

Write the result to `context/specs/00-build-plan.md` as a numbered list in build order.
For each unit: number, name, what it builds, and dependencies that must exist first.

## Job B: a feature spec (per unit)

When the user is ready to build a unit, write its spec file. Use the bundled template
at `${CLAUDE_PLUGIN_ROOT}/skills/context-spec/templates/spec-template.md`. Name the
file `context/specs/NN-feature-name.md` matching the build plan numbering.

If anything about the unit is unclear, ask the user before writing the spec — a vague
spec produces vague code.

A spec has five sections:

1. **Goal** — one or two sentences, concrete. Bad: "Create the auth pages." Good:
   "Create sign-in and sign-up pages using Clerk components with a two-panel layout on
   desktop and form-only on mobile. Use proxy.ts for route protection, not middleware.ts."
2. **Design** — visual/structural decisions for this unit; reference `ui-context.md`
   tokens so the agent makes zero visual guesses.
3. **Implementation** — broken into sub-sections, one per component or boundary, with
   enough detail that "done" is unambiguous.
4. **Dependencies** — packages this unit needs that aren't installed yet, listed
   explicitly with the reason.
5. **Verify when done** — specific conditions that must be true (plus the standard
   checks: no type errors, no console errors, responsive, build passes).

One feature may need one spec or several — let complexity decide, not a fixed rule.

## The three-prompt build loop (share with the user)

Once a spec exists, the build runs as:

- **Implement**: "Read context/specs/NN-feature-name.md. Mark it in progress in
  context/progress-tracker.md. Implement it exactly as specified. Do not go beyond scope."
- **Correct**: "The [element] does not match the spec. Expected: [X]. Current: [Y]. Fix
  only this. Do not change anything else."
- **Close**: "Implementation is complete and verified. Mark unit NN complete in
  context/progress-tracker.md. Push branch feat/NN-feature-name."
