---
name: forge-health
description: >
  This skill should be used for a whole-codebase quality (QA/QC) audit in a Context
  Forge project — phrases like "forge-health", "health check", "QA the codebase",
  "audit code quality", "how healthy is this project", "check test coverage", or
  "security and quality review". It sweeps five dimensions (test-suite health,
  error handling, basic security hygiene, performance smells, dead code) via the
  scout and reviewer agents, and routes findings into the normal fix/refactor
  pipeline. Distinct from forge-audit (docs vs code) and forge-align (consistency):
  this checks the quality of the code itself.
metadata:
  version: "0.21.0"
---

# forge-health

The periodic QA pass for aggregate quality. Every unit passes `forge-verify` on its
own, but nobody owns the aggregate properties — coverage gaps between units, error
handling that thins out across boundaries, a dependency audit nobody ran. This
skill owns them. It detects and prioritizes; fixing always flows through the normal
pipeline.

## Argument

Text after the command scopes the check (e.g. `/forge-health just security and
tests` or `/forge-health src/api`). No argument → all five dimensions,
whole codebase.

## The five dimensions

1. **Test-suite health** — coverage gaps on critical paths (run the project's
   coverage tool if configured), hollow tests (assert nothing meaningful), skipped
   or permanently-failing tests, suites that don't run in CI.
2. **Error handling** — critical paths (auth, payments, data writes, external
   calls) with missing/swallowed errors; user-facing failure states that were never
   designed. Judged against the spec'd error handling in `code-standards.md` — this
   is about *missing* handling on real paths, never speculative handling
   (simplicity first still applies).
3. **Security hygiene (basic)** — secrets committed in code/config, obvious
   injection-prone string building, missing auth checks on mutating routes, and the
   dependency audit (`npm audit` / `pip-audit` / `cargo audit` — whatever the stack
   provides). This is hygiene, not a pentest — say so in the report.
4. **Performance smells** — N+1 query patterns, unbounded queries/lists, heavy work
   in render/hot loops, missing pagination on growing datasets. Smells, not
   benchmarks: flag for measurement, don't guess numbers.
5. **Dead code inventory** — unreferenced exports/files/routes (mention, per the
   orphan rule — deletion is a decision for the user, and removal happens as a
   normal unit).

## How it runs (cheap by design)

1. **Sweep (delegated):** spawn `forge-scout` (haiku) per dimension — or one run
   with the dimension list — to gather evidence with file:line pointers. The
   deterministic parts (coverage tool, dependency audit, grep for skipped tests)
   are commands, not judgment; run them with quiet output.
2. **Judge hotspots:** for the riskiest findings (security candidates, critical-path
   gaps), have `forge-reviewer` (sonnet) confirm or dismiss — scout locates,
   reviewer judges. Everything else is judged in-session.
3. **Report:** a health report grouped by dimension — finding, evidence
   (file:line), severity (Critical / Warning / Info), and the concrete next step.
   Include what was NOT covered so the report never overclaims.
4. **Route, don't fix:** with the user's approval — bugs → `forge-fix`; refactors
   and test-writing work → units via `forge-spec` (zero behavior change, suite
   green); recurring root causes → a lesson line; rules that tooling could enforce
   → recommend the linter/CI config change. **Never mass-edit from this skill.**

## Rules

- Findings need evidence (file:line or command output) — a health report built on
  vibes is worse than none. Label anything uncertain as a hypothesis to verify.
- Respect the division of labor: what a linter/coverage tool/`npm audit` can check
  deterministically, run the tool — model judgment is for what tools can't see.
- Docs drift → `forge-audit`; sibling inconsistency → `forge-align`; this skill
  does not duplicate them (cross-reference instead).
- Recommend a cadence: after each phase of the build plan, or before releases —
  not every session.
