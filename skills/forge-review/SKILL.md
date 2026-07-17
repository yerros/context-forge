---
name: forge-review
description: >
  This skill should be used to run a comprehensive, multi-lens code review of a pull
  request, a branch, or the local working changes in a Context Forge methodology
  project — phrases like "forge-review", "review this PR", "review my diff",
  "review the branch before I push", or "review PR 42". It resolves the review scope,
  loads the project's context files, reviews across quality lenses (spec, standards,
  tests, errors, types, comments, simplicity), gates on confidence, and reports
  findings ranked by severity. Read-only — reviews and reports, never fixes.
metadata:
  version: "0.25.2"
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
Context Forge inputs.

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
  lens, cheap ones (`forge-commenter` is haiku) staying cheap.
- **`parallel`** — same set, launched concurrently rather than sequentially. Faster
  for a big diff; same token cost.

Title each spawn with the agent's persona from its description — e.g.
"Giuseppe — multi-lens review of PR 42", "Karen — tests lens on PR 42" — so the task
list reads like a crew at work; each agent opens and signs with that persona.

Each agent returns its own `RECOMMEND PASS/FAIL`; collapse them into the single
verdict below (any agent FAIL, or any surviving Critical/Important, → overall
`RECOMMEND CHANGES`).

If a bundled agent is unavailable, spawn a general-purpose subagent with that agent's
hunt list, or walk the diff in-session against the lens table.

## Confidence gate

Report only findings with **confidence ≥ 80**. A finding below that bar is noise in a
review meant to be acted on. When a lens produces nothing above the bar, say the lens
ran clean — don't manufacture Advisory items to fill space.

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

End with a one-line verdict: `RECOMMEND MERGE` (no Critical/Important) or
`RECOMMEND CHANGES: <the single most important reason>`. Never soften a Critical into
Important because the code "mostly works". After changes land, re-run the affected
lenses to confirm.

## Boundaries

- Read-only — never edit. Hand fixes to `forge-fix` (bugs in shipped work) or the
  open unit's `forge-build`.
- Not a replacement for `forge-verify`'s close gate — that stays the authority for
  closing a unit. `forge-review` is the wider, unit-optional sweep, e.g. reviewing a
  teammate's PR or your own branch before pushing.
