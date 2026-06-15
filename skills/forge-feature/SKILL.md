---
name: forge-feature
description: >
  This skill should be used to add a new feature to an existing project that uses the
  Six-File Context Methodology — phrases like "forge-feature", "add a feature",
  "I want to add X to the app", "plan a new feature", or "extend the build plan". It
  updates scope in project-overview.md, inserts correctly-ordered units into the build
  plan, and generates the spec(s) — without breaking existing work.
metadata:
  version: "0.1.0"
---

# forge-feature

Add a feature to a project that already has its context files, the safe way. The risk
when adding to a working build is breaking what exists; this skill keeps the new work
scoped, ordered, and documented before any code is written.

## Steps

### 1. Load current state

Read `context/project-overview.md`, `context/architecture.md`, the build plan at
`context/specs/00-build-plan.md`, and `context/progress-tracker.md`. Understand what
already exists and what the invariants are. If there's no `context/` folder, tell the
user to run `forge-init` first.

### 2. Clarify the feature

Ask the user what the feature does, who it's for, and how it fits the existing product.
Push back if it conflicts with anything in "Out of Scope" or with an invariant — surface
the conflict and resolve it before continuing.

### 3. Update scope

Add the feature to `project-overview.md` (Features + In Scope, and adjust Out of Scope
if needed). If it introduces a real architectural change (new dependency, new boundary,
new storage), update `architecture.md` too — and log the decision via `forge-decision`.

### 4. Decompose into units and place them in order

Break the feature into units following the methodology's rules (one visible result, one
system boundary, dependencies first, security before functionality, backend before
frontend wiring, UI shells before real data). Insert them into
`context/specs/00-build-plan.md` at the correct position relative to existing units —
do not just append if the feature depends on or is depended on by existing work.
Renumber if necessary and note the renumbering.

### 5. Generate the spec(s)

Write a spec file per new unit using the five-section pattern (delegate to the same
template as `forge-spec`: `${CLAUDE_PLUGIN_ROOT}/skills/forge-spec/templates/spec-template.md`).

### 6. Update the tracker

Set the first new unit as "Next Up" in `progress-tracker.md` and add a Session Note.

## Output

Tell the user: what changed in the docs, the new unit(s) and where they sit in the build
order, and that the spec(s) are ready. Suggest running `forge-build` on the first new
unit.

## Rules

- Never start coding here — this skill plans and documents only.
- Never silently break ordering: new units must respect existing dependencies.
- Always reflect scope changes in `project-overview.md` before specs are written.
