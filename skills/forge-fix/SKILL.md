---
name: forge-fix
description: >
  This skill should be used when a bug is reported in already-built work in a
  Six-File Context Methodology project — phrases like "forge-fix", "there's a bug
  in X", "fix this bug", "X is broken", "this stopped working", or "users report
  an error in Y". It intakes and reproduces the bug, triages it (fix directly when
  the cause is obvious; hand off to forge-debug when it isn't), and closes with the
  same discipline as a build unit — tracker updated, lesson captured, shipped via
  forge-pr. NOT for being stuck after repeated failed fixes (that is forge-debug)
  or for correcting the unit currently being built (that is forge-build's loop).
metadata:
  version: "0.15.0"
---

# forge-fix

The intake for bug reports in shipped work. A bug fix is a small unit of work and
gets the same discipline as one — scoped, verified, recorded — just without the
ceremony of a full spec. Without this, fixes happen outside the methodology and the
tracker, lessons, and scope rules all leak.

## Argument

Text after the command is the bug report (e.g. `/forge-fix login button does nothing
on page A`) — use it as the intake description and don't re-ask what the bug is; ask
only for missing specifics (exact error, where, since when). No argument → ask for
the symptom.

## 1. Intake

Load Tier 1: the digest (or entry point) and `context/lessons.md` — **check lessons
first**; the bug may already be a known lesson with a known rule. State the failure
precisely: expected vs actual, the exact error/wrong output, where it happens, and —
if identifiable — which unit/change introduced it (`git log`, the build plan's
`## Completed` section, and `context/progress-archive.md` can help date it).

## 2. Reproduce

Establish the smallest repeatable reproduction before changing anything. If it can't
be reproduced, that's the first job — not fixing.

## 3. Triage — one decision

- **Obvious cause, small blast radius** (one boundary, no invariant in question) →
  fix it here, in scope. Read the Tier 2 context file(s) the fix touches
  (`code-standards.md` nearly always; `ui-context.md` for UI; `architecture.md` if a
  boundary is involved).
- **Cause non-obvious, multiple candidate layers, an invariant may be violated, or a
  fix attempt already failed twice** → STOP and run `forge-debug`. Do not guess-fix.
  One diagnosis engine, not two.

## 4. Fix, in scope

Smallest change that addresses the root cause — never a workaround layered over a
symptom. No drive-by refactors or "improvements"; anything out of scope goes to the
tracker as an open question or to `forge-feature`. Protected files stay protected.

## 5. Verify

Re-run the reproduction (it must now pass), the project's real build/typecheck/lint,
and — if the fix touched a completed unit's behavior — that unit's "Verify when
done" checklist from its spec in `context/specs/archived/`.

## 6. Close with discipline

- Update `context/progress-tracker.md`: one-line entry for the fix (what + root
  cause), per the close-unit procedure in
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-build/references/close-unit.md` (steps 1–2, 5–7
  apply; there is no spec to archive unless the fix was promoted to a full unit).
- If the root cause is likely to recur, distill **one lesson line** into
  `context/lessons.md` per
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md`.
- If the bug exposed a wrong or missing rule, fix the rule at its source
  (`code-standards.md` / `architecture.md`); if it changed an architectural
  decision, log it via `forge-decision`.
- Suggest shipping via `forge-pr` with a `fix/NN-short-name` branch and a
  `fix:` conventional commit.

## Boundaries

- Stuck / going in circles → `forge-debug` (this skill hands off, never thrashes).
- Bug found while building the current unit → stay in `forge-build`'s correct step.
- "Bug" that is actually a behavior change request → `forge-feature` (scope change,
  not a fix).
- A fix so large it needs design decisions → promote it to a real unit via
  `forge-spec` and build it with `forge-build`.
