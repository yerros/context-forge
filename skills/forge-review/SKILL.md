---
name: forge-review
description: >
  This skill should be used to run a comprehensive, multi-lens code review of a pull
  request, a branch, or the local working changes in a Context Forge methodology
  project — phrases like "forge-review", "review this PR", "review my diff",
  "review the branch before I push", or "review PR 42". It resolves the review scope,
  loads the project's context files, builds a mechanical inventory of the diff,
  reviews across quality lenses (spec, standards, tests, errors, types, comments,
  simplicity) with per-item coverage tracked in a persistent review ledger, gates
  on confidence, and reports findings ranked by severity. With --until-clean it
  loops review → fix → re-review until one full pass finds nothing. Read-only —
  reviews and reports, never fixes.
metadata:
  version: "0.27.0"
---

# forge-review

A comprehensive, multi-perspective review for a change that is about to ship — a PR,
a branch, or the uncommitted working tree. Where `forge-verify` is the pre-close gate
for **one spec'd unit** (checklist + build + tests + tiered review, hard PASS/FAIL),
`forge-review` is the broader **quality sweep** over an arbitrary diff: many lenses,
confidence-gated, severity-ranked, no unit required.

Read-only. This skill reviews and reports; it never edits code. Route fixes back
through `forge-fix` / `forge-build`.

## Argument

Text after the command sets the scope and the lenses:

- **PR** — a number or URL (`/forge-review 42`, `/forge-review https://github.com/…/pull/42`)
  → review that PR's diff.
- **No PR** → review the current branch's open PR if one exists (`gh pr view`);
  otherwise review the branch's diff vs its base; otherwise the local working changes
  (`git diff` + staged + untracked).
- **`--focus=<lenses>`** — comma-separated, limits the review to those lenses
  (see the lens table). No focus → run every applicable lens.
- **`parallel`** — fan the lenses out across subagents instead of one in-session pass
  (see Execution). Default is the cheaper single pass.
- **`--until-clean`** — don't stop at the report: loop review → fix (via
  `forge-fix`) → re-review until one full pass finds no Critical/Important
  (see Convergence). The flag is the user's consent to route fixes automatically.

Confirm the resolved scope (which diff, which base) before spending review tokens.

## Inputs

Load the project's context so the review judges against the system, not from memory:

- `context/architecture.md` — invariants and protected boundaries.
- `context/code-standards.md` (+ `context/ui-context.md` for UI) — conventions.
- `context/lessons.md` — a violated lesson is a finding.
- If the diff maps to a unit, its spec (`context/specs/NN-*.md` or
  `context/specs/archived/NN-*.md`) — enables the spec-mismatch lens.
- Only the module context(s) (`context/modules/<area>.md`) the diff touches, if any.

If there is no `context/` (or `.forge/`) directory, say so and review against
`CLAUDE.md` + repo conventions only — the lenses still apply, just without the
Context Forge inputs (the ledger then lives at `.forge-reviews/<scope-id>.md`).

## Inventory first — coverage is explicit, never assumed

"Find bugs in this diff" is a random walk: each pass notices different things,
which is exactly why a second review keeps finding what the first missed. So
before any lens runs, enumerate the diff **mechanically** into a numbered
inventory — every changed file, broken into hunks named by function/section —
recorded in the review ledger
(`${CLAUDE_PLUGIN_ROOT}/skills/forge-review/references/review-ledger.md`; format
and rules there).

Every lens then walks the inventory item by item and marks each cell: clean, or
a finding number. **An unmarked item is an unreviewed item** — no verdict may be
reported while any due item×lens cell is unmarked. Spawned agents receive the
inventory (their slice of items) in the prompt and must return per-item verdicts,
which the orchestrator writes back to the ledger.

If this is not the first pass on this scope, the ledger already exists: read it
first and follow its rules — re-verify previously fixed findings with fresh
evidence, dedupe against known findings, and add the hunks new since the last
pass as new inventory items (a fix is new code and gets full review, not a
lighter one).

## Lenses

Each lens is a review dimension. `--focus` names them; the aliases match the
external `/review-pr` focus flags so existing muscle memory carries over.

Each lens is owned by a **bundled** agent — every one ships with this plugin, so the
review runs identically on any machine with no globally-installed agents required.

| Lens | Alias | Agent | What it hunts |
| ---- | ----- | ----- | ------------- |
| **spec** | — | `forge-reviewer` | Built what the spec doesn't say, or spec'd but missing (scope creep is a finding even when the extra code is good). Skipped if the diff maps to no unit. |
| **standards** | `code` | `forge-reviewer` | Diff walked against `code-standards.md` + `lessons.md` **rule by rule, from the files** — any explicit-rule violation is Critical. |
| **invariants** | — | `forge-reviewer` | Breaks an `architecture.md` rule or touches a protected file. |
| **simplify** | `simplify` | `forge-reviewer` | Overengineering — abstractions wrapping single-use code, configurability nobody asked for, 200 lines where 50 do. Advisory unless it hides a bug. |
| **silent-breakage** | — | `forge-reviewer` | Changed behavior other call sites rely on (search other uses of changed functions/components). |
| **tests** | `tests` | `forge-tester` | Spec'd tests missing, tests that assert nothing, tests bent to pass instead of code fixed. |
| **errors** | `errors` | `forge-failure-hunter` | Silent failures — swallowed catches, bad fallbacks, error paths that never surface. |
| **types** | `types` | `forge-typer` | Type design: encapsulation, invariants expressed in the type, illegal states left representable. |
| **comments** | `comments` | `forge-commenter` | Comment accuracy vs code, comment rot, stale docs. |

Default run = every lens that applies to the changed files (skip **types** with no
new/changed types, **spec** with no unit, etc.). Say which lenses ran and which were
skipped and why.

## Execution

Fan out to the bundled agents that own the active, applicable lenses. `forge-reviewer`
(sonnet) carries the first five lenses in one pass; each specialist carries one lens.
Two modes:

- **Single pass (default)** — spawn `forge-reviewer` for its five lenses, plus each
  applicable specialist (`forge-tester`, `forge-failure-hunter`, `forge-typer`,
  `forge-commenter`) only when its lens applies to the changed files — skip the
  specialist otherwise (no test files → no `forge-tester`; no type changes → no
  `forge-typer`). This is the normal review: full coverage, one subagent per relevant
  lens, each specialist scoped to its lens.
- **`parallel`** — same set, launched concurrently rather than sequentially. Faster
  for a big diff; same token cost.

Title each spawn with the agent's persona from its description — e.g.
"Giuseppe — multi-lens review of PR 42", "Karen — tests lens on PR 42" — so the task
list reads like a crew at work; each agent opens and signs with that persona.

Each spawn prompt carries the agent's inventory slice (from the ledger); the agent
returns per-item verdicts — clean or a finding — and the orchestrator writes them
back to the ledger. Each agent also returns its own `RECOMMEND PASS/FAIL`; collapse them into the single
verdict below (any agent FAIL, or any surviving Critical/Important, → overall
`RECOMMEND CHANGES`).

If a bundled agent is unavailable, spawn a general-purpose subagent with that agent's
hunt list, or walk the diff in-session against the lens table.

## Confidence gate

Report only findings with **confidence ≥ 80**. A finding below that bar is noise in a
review meant to be acted on. When a lens produces nothing above the bar, say the lens
ran clean — don't manufacture Advisory items to fill space.

## Convergence — `--until-clean`

One review pass cannot promise it found everything — no reviewer can. What CAN be
promised is a **fixed point**: keep reviewing until a full pass finds nothing new.
With `--until-clean`:

1. Run a full pass (inventory + all applicable lenses, ledger updated).
2. Findings above Advisory → route each to `forge-fix` (which pins every bug with
   a red regression test before fixing — the bug can never silently return), then
   mark it `fixed` in the ledger with the fix commit.
   **When the scope is a PR, post one comment per fix round** (`gh pr comment <n>`)
   so the human can follow what the loop changed without reading the ledger:

   ```
   🔧 forge-review pass N — fixes applied
   - F1 `src/auth/login.ts:41` (errors, Critical): catch swallowed TokenError —
     rethrown + regression test `auth.spec.ts:12` (commit abc1234)
   - F3 …
   Still open: F2. Next: re-review (pass N+1).
   ```

   One comment per round — a 3-pass loop leaves 3 comments, a readable audit
   trail of what was found and fixed and when. List each fixed finding with
   file:line, lens/severity, one line of what + root cause, its regression test,
   and the commit. Non-PR scopes (branch/worktree) skip this — the ledger's pass
   log is the trail there.
3. Re-review: the fix diffs become new inventory items (full review), every
   `fixed` finding is re-verified to `verified-fixed` with cited evidence, and
   affected lenses re-run.
4. **Converged** only when one complete pass reports zero Critical/Important and
   every finding is `verified-fixed`. Finding new bugs in pass 2 or 3 is the loop
   working, not the review failing — the failure mode is stopping before clean.
5. **Hard stop: 3 passes without convergence**, or any finding that reopens
   twice → stop, hand the ledger to the user (and `forge-debug` for the reopening
   finding). Endless review-fix cycling on the same root cause is a diagnosis
   problem, not a review problem.

Without the flag, behavior is unchanged: one pass, report, and — after the user
lands changes — re-run to verify, resuming the same ledger. The PR-comment rule
still applies whenever fixes from this review's findings are committed via
`forge-fix`, loop or not: one comment per fix round, same format.

## Output

Dedupe overlapping findings across lenses (same file:line, same root cause → one
entry, note the lenses that flagged it). Rank by severity, each with `file:line`, the
lens, and a one-line why:

- **Critical** — must fix before merge: bugs, security, data loss, spec violation,
  invariant break, missing spec'd test, explicit-rule violation.
- **Important** — should fix: missing tests, real quality problems, silent breakage,
  convention drift, fragile patterns.
- **Advisory** — suggestions; simplifications and polish. Report only when the lens
  was explicitly requested or the finding is cheap and clearly right.

State coverage before the verdict: "N inventory items × M lenses, all cells
marked" (or name the unmarked cells — which make the verdict `INCOMPLETE`, never
a guess). Then the one-line verdict: `RECOMMEND MERGE` (no Critical/Important) or
`RECOMMEND CHANGES: <the single most important reason>`. Never soften a Critical into
Important because the code "mostly works". After changes land, re-run — the ledger
makes the follow-up pass cumulative, not a restart.

## Boundaries

- Read-only — never edit. Hand fixes to `forge-fix` (bugs in shipped work) or the
  open unit's `forge-build`. `--until-clean` doesn't change this: the review
  passes stay read-only; the fixes between passes run through `forge-fix` with
  its full discipline (red regression test, standards gate, close).
- Not a replacement for `forge-verify`'s close gate — that stays the authority for
  closing a unit. `forge-review` is the wider, unit-optional sweep, e.g. reviewing a
  teammate's PR or your own branch before pushing.
