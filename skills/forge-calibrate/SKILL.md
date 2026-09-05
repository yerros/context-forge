---
name: forge-calibrate
description: >
  This skill should be used to measure how reliable the project's code review is —
  phrases like "forge-calibrate", "calibrate the reviewer", "how consistent is
  forge-review", "is the review flaky", "test the reviewer", or "review golden
  set". It runs forge-review's lenses several times over a golden set of small
  diffs with known findings, scores recall (did it find what's planted) and
  run-to-run agreement (does it find the same things twice), and names the blind
  spots. Reports numbers; changes nothing.
metadata:
  version: "0.1.0"
---

# forge-calibrate

A reviewer you have never measured is a reviewer you are trusting on vibes. This
skill turns "the review feels inconsistent" into two numbers — **recall** against
planted findings and **agreement** between repeated runs — and a list of what the
reviewer never sees. Run it before and after changing a lens, an agent prompt, a
rule card, or the confidence gate; without the before/after pair, a prompt change
is a guess.

## Argument

- `--runs N` — how many times each case is reviewed (default 3; 5 for a decision
  you'll act on).
- `--case <name>` — only that golden case.
- `--focus=<lenses>` — passed through to the review.
- `seed` — copy the bundled golden set into the project (see Golden set) and stop.

## Golden set

A case is a directory with `before/` and `after/` trees (the diff is
`diff -ruN before after`), an `expected.txt` of finding keys
(`<lens>:<file>:<tag>`, one per line, `#` comments allowed), and optionally a
`context/` with the spec / standards / `rules.txt` the case depends on.

- Bundled: `${CLAUDE_PLUGIN_ROOT}/skills/forge-calibrate/golden/` — eight cases, one
  per failure class: swallowed error, scope creep + unrequested config, hollow
  test, silent breakage of an untouched caller, rule-card violation that step 0
  must catch by ID; and three **gate cases** for `forge-gatekeeper` — hardcoded
  live token (step 0 must catch it), missing object-level authorization (IDOR),
  irreversible migration shipped with its code change.
- Project: `<context-dir>/review-golden/` — created by `seed` from the bundled
  set. **Grow it from real misses**: every finding a human caught that
  `forge-review` didn't becomes a case (minimal before/after + the key). The
  golden set is the reviewer's regression suite.

Use the project set when it exists, else the bundled one, and say which.

## Steps

1. **Resolve cases** (`--case` or all) and `--runs`. Print the plan: N cases ×
   R runs, which set.
2. **Per case, per run** — in a scratch directory (never the project tree):
   copy `after/` as the working tree over a git repo whose HEAD is `before/`, copy
   the case's `context/` if present, then run **exactly** the pipeline the case
   targets: keys prefixed `security:`/`prod:` → `forge-gatekeeper` (step 0
   `security-check.sh`, scope, the gatekeeper agent); every other key →
   `forge-review` (step 0 `rules-check.sh`, inventory, lenses, confidence gate). Same
   agents, same prompts, same gate — a calibration that runs a lighter review
   measures nothing. Runs are independent: no ledger carried between them, no
   hints from a previous run's output.
3. **Map findings to keys.** For each run, write `run-<n>.txt` with one key per
   finding: the expected key it matches (same file, same root cause — this is a
   judgment call; be strict, a finding at the right file for a different reason is
   not a match), or `extra:<file>:<short-tag>` for a finding not in
   `expected.txt`. Keep the raw finding text alongside for the report.
4. **Score** with the bundled scorer per case, then overall:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-calibrate/scripts/score.sh" <case-scratch-dir>
   ```

   It prints per-run recall, mean recall, mean pairwise Jaccard (agreement), the
   keys **never found** (blind spots) and **found only sometimes** (unstable).
5. **Report** — one table: case · mean recall · agreement · blind spots · unstable
   · mean extras. Then the three lines that matter:
   - **Blind spots** → which lens owns each, and whether the miss is a prompt gap
     (fix the agent's hunt list) or a mechanizable rule (add to `rules.txt` —
     recall goes to 100% and stays there).
   - **Unstable keys** → the lens is guessing; candidates for a stricter hunt
     list, a ✗/✓ example on the rule card, or — last resort — a consensus run.
   - **Extras** → false-positive pressure; many extras with low agreement means
     the confidence gate is letting opinions through.
6. Leave the scratch dirs' `run-*.txt` + `expected.txt` next to the report path
   you name, so the user can re-score or diff runs. Change nothing in the project.

## Reading the numbers

- Recall < 100% on a bundled case is a bug in the review, not in the case — the
  plants are unambiguous by design.
- Agreement is the honesty metric. 100% recall with 60% agreement means the
  reviewer finds the plants but pads each run with different opinions; tighten
  the gate before adding lenses.
- A case caught by step 0 (`T`-finding) should be at 100/100 by construction; if
  it isn't, `rules.txt` isn't being run or the file glob is wrong.

## Boundaries

- Read-only for the project. Everything happens in scratch directories.
- Does not fix the reviewer. It tells you where and how much; the fix is a prompt,
  a rule card, or a `rules.txt` line — and then a re-run of this skill.
- Not a test of the code under review — the golden diffs are deliberately wrong.
