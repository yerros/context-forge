---
name: context-pr
description: >
  This skill should be used to close out a completed unit with git in a Six-File Context
  Methodology project — phrases like "context-pr", "open a PR for this unit", "ship this
  unit", "commit and push", or "close unit NN". It creates the branch, makes a
  conventional commit, and opens a pull request with a spec-derived summary.
metadata:
  version: "0.1.0"
---

# context-pr

Automate the close step: turn a verified unit into a clean branch, commit, and PR. Only
run this once the unit is implemented AND verified.

## Preconditions

- The unit's verification passed (run `context-verify` first if unsure).
- `progress-tracker.md` shows the unit as complete or ready to close.
- The repo is a git repository with a clean-enough working tree for this unit's changes.

Confirm the unit number/name and the target base branch (default `main`) with the user
before pushing.

## Steps

### 1. Branch

Create/switch to a branch named `feat/NN-feature-name` matching the unit (use `fix/` for
bug-fix units, `chore/` for tooling). Check current branch and status first.

### 2. Stage and commit

Stage the unit's changes. Write a Conventional Commit message:

```
feat(scope): short summary of the unit

- key change 1
- key change 2

Implements unit NN per context/specs/NN-feature-name.md
```

Use `feat:`, `fix:`, `chore:`, `refactor:`, `docs:` as appropriate. Keep the subject
under ~72 chars. Do not bundle unrelated changes — one unit per PR.

### 3. Push and open the PR

Push the branch. Open a PR (via `gh pr create` if the GitHub CLI is available; otherwise
print the commit/branch and the ready-to-paste PR body for the user to open manually).

PR body, derived from the spec:

```
## Summary
<unit goal from the spec>

## Changes
<bullet list of what was built>

## Verification
<the spec's "Verify when done" checklist, with each item checked>

Spec: context/specs/NN-feature-name.md
```

### 4. Record

Note in `progress-tracker.md` that the unit was shipped (branch/PR link), and set the
next unit as "Next Up".

## Rules

- Never push or open a PR for an unverified or partial unit.
- One unit per PR — never combine units.
- Never force-push or rewrite shared history without explicit user instruction.
- If git or `gh` isn't available or auth fails, stop and hand the exact commands to the
  user rather than improvising.
