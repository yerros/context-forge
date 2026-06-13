---
name: context-verify
description: >
  This skill should be used to verify a build unit before closing it in a project that
  uses the Six-File Context Methodology — phrases like "context-verify", "verify this
  unit", "check the unit is done", "run the verification checklist", or "review before
  I close this". It runs the spec's verification checklist plus build/typecheck/lint and
  an adversarial review, then reports pass/fail.
metadata:
  version: "0.1.0"
---

# context-verify

Confirm a unit is truly done before it's marked complete. "Done" means the spec's
checklist passes, the project builds clean, and an adversarial review finds no
in-scope problems.

## Inputs

The unit's spec at `context/specs/NN-feature-name.md` (its "Verify when done" section)
and `context/architecture.md` (invariants). Confirm which unit if ambiguous.

## What to run

### 1. Spec checklist

Go through every item in the spec's "Verify when done" section and check it explicitly.
Mark each pass/fail with evidence.

### 2. Automated checks

Run the project's real commands (detect from `package.json` scripts / Makefile / etc.):

- type check (e.g. `tsc --noEmit` or `npm run typecheck`)
- lint (e.g. `npm run lint`)
- build (e.g. `npm run build`)
- tests if they exist (e.g. `npm test`)

Report exact failures with file/line where available.

### 3. Invariant check

Confirm the implementation honors every invariant in `architecture.md` and didn't
modify protected files from `ai-workflow-rules.md`.

### 4. Adversarial review (subagent)

Spawn a subagent (Task tool, general-purpose) to review the unit's diff against the
spec with a critical eye. Instruct it to look for: scope creep beyond the spec, silent
invariant violations, missing error/edge handling, inconsistent patterns versus
`code-standards.md`, and anything that "works but is wrong". Have it return findings by
severity (Critical / Warning / Info) with file and line.

## Output

A concise verdict:

- **PASS** — every checklist item passes, automated checks are green, no invariant
  violations, no Critical/Warning findings. Recommend closing the unit (or running
  `context-build`'s close step).
- **FAIL** — list exactly what failed and the minimal fix needed. Do not fix here
  beyond confirming the problem; stay within the unit's scope when fixing.

Never report PASS with failing checks, partial implementation, or unresolved Critical
findings.
