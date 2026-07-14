---
name: forge-verify
description: >
  This skill should be used to verify a build unit before closing it in a project that
  uses the Six-File Context Methodology — phrases like "forge-verify", "verify this
  unit", "check the unit is done", "run the verification checklist", or "review before
  I close this". It runs the spec's verification checklist plus build/typecheck/lint and
  an adversarial review, then reports pass/fail.
metadata:
  version: "0.18.1"
---

# forge-verify

Confirm a unit is truly done before it's marked complete. "Done" means the spec's
checklist passes, the project builds clean, and an adversarial review finds no
in-scope problems.

## Argument

Text after the command selects the unit to verify (e.g. `/forge-verify unit 04`). No
argument → verify the unit currently "In Progress" (or just built) per the tracker;
confirm if ambiguous.

## Inputs

The unit's spec at `context/specs/NN-feature-name.md` (its "Verify when done" section)
and `context/architecture.md` (invariants).

## What to run

### 1. Spec checklist

Go through every item in the spec's "Verify when done" section and check it explicitly.
Mark each pass/fail with evidence.

### 2. The unit's tests

Check the spec's **Tests** section: every listed test must exist and pass. If the spec
defined tests but they were never written, that is a **FAIL** — implementation isn't
complete without them. (A spec that explicitly says "none — [reason]" passes this
check; an older spec with no Tests section gets a Warning recommending tests be
added.)

### 3. Automated checks (incl. regression gate)

Run the project's real commands (detect from `package.json` scripts / Makefile / etc.):

- type check (e.g. `tsc --noEmit` or `npm run typecheck`)
- lint (e.g. `npm run lint`)
- build (e.g. `npm run build`)
- the **full test suite** (e.g. `npm test`) — not just this unit's tests; earlier
  units' tests staying green is the regression gate for closing this one.

Report exact failures with file/line where available.

### 4. Invariant check

Confirm the implementation honors every invariant in `architecture.md` and didn't
modify protected files from `ai-workflow-rules.md`.

### 5. Adversarial review — tiered by risk

A full `forge-reviewer` run costs a whole subagent session, so match the review to
the stakes:

- **Spawn `forge-reviewer`** (sonnet-pinned, read-only) when the unit is marked
  `[complexity: high]` in the build plan, touches an invariant-adjacent area or
  protected files, changes code other units depend on, or the user asks for a deep
  review. Give it the unit's spec path and the diff base; it returns findings by
  severity (Critical / Warning / Info) with file:line and a `RECOMMEND PASS/FAIL`
  verdict.
- **Otherwise (standard units): review in-session** — walk the diff yourself
  against the reviewer's hunt list (spec mismatch, invariant violations,
  missing/hollow tests, silent breakage, edge cases, convention drift) and report
  the same severity format. No subagent, no extra session cost.

If the agent is unavailable for a high-risk unit, spawn a general-purpose subagent
with the same instructions.

## Output

A concise verdict:

- **PASS** — every checklist item passes, automated checks are green, no invariant
  violations, no Critical/Warning findings. Recommend closing the unit (or running
  `forge-build`'s close step).
- **FAIL** — list exactly what failed and the minimal fix needed. Do not fix here
  beyond confirming the problem; stay within the unit's scope when fixing.

Never report PASS with failing checks, partial implementation, or unresolved Critical
findings.
