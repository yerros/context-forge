---
name: forge-spec
description: >
  This skill should be used for spec-driven development on a project that uses the
  Six-File Context Methodology — phrases like "forge-spec", "create a build plan",
  "break this into units", "write a spec for this feature", "generate a spec file",
  or "plan the build". It decomposes a project into ordered, verifiable build units
  and writes detailed per-feature spec files into context/specs/ that a coding agent
  implements exactly.
metadata:
  version: "0.16.2"
---

# forge-spec

Turn features into spec-driven, buildable units. Two jobs: produce the **build plan**
(once per project) and write a **spec file** for each unit (right before building it).

Read `context/project-overview.md` and `context/architecture.md` first for context.
Specs live in `context/specs/`. Create that folder if it doesn't exist.

**Delegate the thinking to `forge-architect`** (the plugin's opus-pinned agent):
once the target and any user clarifications are settled, spawn `forge-architect`
with the job (build plan, or spec for unit NN) and the relevant user answers. It
reads the context files, applies unit-rules.md and the spec template, writes the
spec file(s), and returns a summary plus any open questions — relay those to the
user. Spec quality is the highest-leverage point of the whole methodology, which is
why this one step gets the strongest model. If the agent (or the opus model) is
unavailable, do the same work in-session following the same references.

## Argument

Text after the command names the target (e.g. `/forge-spec the notifications
feature` → Job B for that unit; `/forge-spec build plan` → Job A). No argument → if
no build plan exists, do Job A; otherwise offer to spec the next unspec'd unit in
the plan.

### Specs folder layout

- `context/specs/00-build-plan.md` — the build plan (see Job A).
- `context/specs/NN-feature-name.md` — the spec for each **active or pending** unit.
- `context/specs/archived/` — specs for **completed** units. When a unit closes it is
  moved here (by `forge-build` / `forge-build-all` / `forge-pr`) so the active `specs/`
  folder only ever lists work that is still pending. Create the folder on first archive.

At any moment, the spec files directly inside `context/specs/` are exactly the units
left to build; everything finished lives under `archived/`.

## Job A: the build plan (once)

When the user wants to plan the whole build, decompose the feature set into units
following the shared rules in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-spec/references/unit-rules.md` — what a unit is,
the four rules for a good unit, the five ordering rules, and how to validate the
order. Read that file before decomposing.

Write the result to `context/specs/00-build-plan.md` as a numbered list in build order.
For each unit: number, name, what it builds, dependencies that must exist first, and —
where unit-rules.md's criteria apply — a `[complexity: high]` marker with a short
reason (it drives the model recommendation in `forge-build`/`forge-build-all`).

Give the build plan two sections so it stays readable as work progresses:

- `## Units` — the active, in-build-order list of units **not yet complete**. This is the
  working list and should stay short and current.
- `## Completed` (at the bottom) — units that have shipped, moved down here when they
  close, kept for history with their date and PR/branch. New plans start with this
  section empty.

Keeping completed units out of the active list (and their specs under `specs/archived/`)
is what keeps the build plan clean.

## Job B: a feature spec (per unit)

When the user is ready to build a unit, write its spec file. Use the bundled template
at `${CLAUDE_PLUGIN_ROOT}/skills/forge-spec/templates/spec-template.md`. Name the
file `context/specs/NN-feature-name.md` matching the build plan numbering.

If anything about the unit is unclear, ask the user before writing the spec — a vague
spec produces vague code.

A spec has six sections:

1. **Goal** — one or two sentences, concrete. Bad: "Create the auth pages." Good:
   "Create sign-in and sign-up pages using Clerk components with a two-panel layout on
   desktop and form-only on mobile. Use proxy.ts for route protection, not middleware.ts."
2. **Design** — visual/structural decisions for this unit; reference `ui-context.md`
   tokens so the agent makes zero visual guesses.
3. **Implementation** — broken into sub-sections, one per component or boundary, with
   enough detail that "done" is unambiguous.
4. **Dependencies** — packages this unit needs that aren't installed yet, listed
   explicitly with the reason.
5. **Tests** — the automated tests this unit ships with (level + behavior each must
   prove), written *during* implementation, not after. Match the project's real test
   stack from `code-standards.md`. "None — [reason]" is allowed for pure-visual or
   config-only units, but must be stated, never implied.
6. **Verify when done** — specific conditions that must be true, plus the standard
   checks: this unit's tests green, **full suite green (regression gate)**, no type
   errors, no console errors, responsive, build passes.

One feature may need one spec or several — let complexity decide, not a fixed rule.

## The three-prompt build loop (share with the user)

Once a spec exists, the build runs as:

- **Implement**: "Read context/specs/NN-feature-name.md. Mark it in progress in
  context/progress-tracker.md. Implement it exactly as specified. Do not go beyond scope."
- **Correct**: "The [element] does not match the spec. Expected: [X]. Current: [Y]. Fix
  only this. Do not change anything else."
- **Close**: "Implementation is complete and verified. Mark unit NN complete in
  context/progress-tracker.md, move it to the Completed section of
  context/specs/00-build-plan.md, and move its spec to context/specs/archived/. Then
  ship it with forge-pr (branch feat/NN-feature-name, conventional commit, PR)."
