# Context Forge

> A Claude Code plugin that gives your AI agent a persistent, disciplined workflow —
> spec-driven builds, real verification, and project memory that survives every session.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-6C5CE7.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Version](https://img.shields.io/badge/version-0.26.0-blue.svg)](./CHANGELOG.md)

**You are the architect; the AI is the implementation engine.** Context Forge captures
your architectural thinking in a small set of context files, then makes every session —
today's and next month's — execute against that system instead of guessing. The result
is code that stays consistent across features, sessions, and machines.

---

## Table of contents

- [Why](#why)
- [How it works](#how-it-works)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Agents](#agents)
- [Hooks](#hooks)
- [The context directory](#the-context-directory)
- [Token economy](#token-economy)
- [Requirements](#requirements)
- [Repository structure](#repository-structure)
- [Contributing](#contributing)
- [License](#license)

## Why

Three failure modes plague AI-assisted projects:

1. **Vibe-coding collapse** — the agent builds fast for an hour, then starts
   contradicting its own earlier decisions and the codebase begins fighting you.
2. **Feature drift** — you return weeks later and the agent has forgotten every
   architectural decision, "fixing" things that were never broken.
3. **Dialect sprawl** — five similar features, five different implementations,
   because each was written from scratch with no memory of its siblings.

All three share one root cause: the agent has no documented system to work within and
no memory between sessions. Context Forge fixes that — a foundation the agent reads
before it writes anything, a build loop that verifies before it ships, and memory
that turns every correction into a permanent rule.

## How it works

The workflow runs in four phases:

1. **Foundation** (`/forge-init`) — scaffold or adopt the project's context files:
   overview, architecture (with hard invariants), UI tokens, code standards, workflow
   rules, and a living progress tracker. Brownfield projects are analyzed from real
   evidence; nothing is written without your confirmation.
2. **Planning** (`/forge-spec`, `/forge-brainstorm`, `/forge-feature`) — an
   opus-pinned architect agent decomposes work into small, ordered, verifiable units
   and writes a six-section spec per unit (goal, design, implementation,
   dependencies, tests, verification) with complexity markers for risky ones.
3. **Build loop** (`/forge-build`, `/forge-build-all`) — implement one unit exactly
   to its spec, tests written during implementation, then an explicit verify loop:
   unit tests → full suite (regression gate) → build/typecheck/lint → spec checklist.
   Same failure twice → mandatory stop-and-diagnose (`/forge-debug`), never a third
   blind fix. Ship per unit with `/forge-pr`.
4. **Maintenance** (`/forge-audit`, `/forge-align`, `/forge-health`,
   `/forge-compact`) — keep docs honest against the code, keep sibling features in
   one dialect, keep aggregate quality (tests, error handling, security hygiene)
   healthy, keep the recurring token cost under budget.

Code discipline is enforced at every point code can be born: minimum code that
satisfies the spec (no speculative abstractions, no unrequested configurability),
surgical changes only (every changed line traces to the spec; orphaned imports
cleaned, pre-existing dead code untouched), and ambiguity surfaced instead of
silently resolved.

## Installation

Context Forge is distributed via this repository, which doubles as a plugin
marketplace.

Inside Claude Code:

```shell
/plugin marketplace add yerros/context-forge
/plugin install context-forge@yerros
```

Or from your terminal:

```bash
claude plugin marketplace add yerros/context-forge
claude plugin install context-forge@yerros
```

Restart Claude Code after installing (hooks and agents register at startup). Verify
with `/plugin`. For local development, clone the repo and
`/plugin marketplace add ./context-forge`. Update later with
`/plugin marketplace update yerros`.

## Quick start

From inside any project:

```shell
/forge-init        # set up (or adopt) the context files — detects your stack
/forge-spec        # plan the build; the architect writes specs per unit
/forge-build       # implement one unit through the verify loop, strictly in scope
/forge-verify      # confirm the unit is truly done (tests, regression, review)
/forge-pr          # ship it: branch, conventional commit, pull request
```

In later sessions `/forge-resume` restores context tier by tier — the `SessionStart`
hook already injects a compact digest automatically. As the project grows:
`/forge-brainstorm` for grounded ideation, `/forge-feature` for new features,
`/forge-fix` for bug reports, `/forge-debug` when stuck, `/forge-align` when similar
features drift apart, `/forge-decision` for ADRs, `/forge-lesson` to remember
corrections, `/forge-audit` and `/forge-compact` for upkeep.

> Skills are namespaced by the plugin. If a bare name is ambiguous, use the fully
> qualified form, e.g. `/context-forge:forge-init`.

## Commands

| Command | What it does |
| ------- | ------------ |
| `forge-init` | Reads project state first, then sets up fresh or **adopts & reconciles** an existing setup (fills gaps only, never overwrites). Stack-aware; brownfield analysis from real evidence, confirmed before writing. |
| `forge-brainstorm` | Grounded ideation: diverges into options, stress-tests each against scope, invariants, and lessons, converges, and routes the outcome — build it, log it as a decision, or park it in `ideas.md`. Planning only. |
| `forge-prompt` | Sharpens a rough request into a precise, context-aligned prompt or spec — goal, scope, constraints, acceptance — without changing your intent. |
| `forge-spec` | Builds the ordered build plan and writes a six-section spec per unit (goal, design, implementation, dependencies, tests, verification), delegated to the opus architect. |
| `forge-feature` | Adds a feature to a working project: updates scope, inserts correctly-ordered units into the build plan, generates specs — without breaking existing work. |
| `forge-build` | The disciplined implement → verify → close loop for one spec'd unit: tests written during implementation, full-suite regression gate, 2-failure escalation to `forge-debug`. |
| `forge-build-all` | The autonomous multi-unit version: builds every remaining unit in order, verifying each, **stopping at the first failure**. |
| `forge-verify` | The pre-close gate: spec checklist + the unit's tests + full suite + build/typecheck/lint + tiered adversarial review, with a hard PASS/FAIL verdict. |
| `forge-review` | Comprehensive multi-lens review of a PR, branch, or working diff (spec, standards, tests, errors, types, comments, simplicity) — confidence-gated, severity-ranked, read-only. The wide sweep to `forge-verify`'s unit close-gate. |
| `forge-fix` | Intake for bug reports in shipped work: reproduce, triage (fix directly when obvious; hand off to `forge-debug` when not), verify, close with tracker + lesson + `fix/` branch. |
| `forge-debug` | Stop-and-diagnose when stuck or after repeated failures: reproduce, isolate, re-read invariants, present root-cause options — no guess-fixing. |
| `forge-align` | Finds and fixes consistency drift between similar features: maps feature families, registers canonical patterns with exemplars, and turns approved alignments into refactor units. |
| `forge-health` | Whole-codebase QA pass across five dimensions — test-suite health, error handling on critical paths, basic security hygiene, performance smells, dead code — with evidence-backed findings routed into the normal fix/refactor pipeline. |
| `forge-pr` | Ships a verified unit: branch (`feat/NN`, `fix/NN`), conventional commit, PR with a spec-derived summary. |
| `forge-decision` | Logs an Architecture Decision Record to `decisions.md` and keeps `architecture.md` in sync. |
| `forge-lesson` | "Remember this / forget that": distills corrections into one-line lessons (per project) or preferences (cross-project), within budget, promoting recurring ones into real standards. |
| `forge-resume` | Restores context tier by tier at session start (digest + tracker first, full files per task) and briefs you on where things stand. |
| `forge-audit` | Detects drift between the context files (including the digest) and the actual codebase, checks token budgets, and offers doc updates. |
| `forge-compact` | Token-maintenance pass: measures every context file against its budget, compresses with approval, rotates history, (re)generates the digest. |
| `forge-worktree` | Parallel builds across terminals: one unit = one git worktree = one branch. Dependency-gates the unit, claims it atomically (visible to every terminal), creates the worktree, and hands you the commands for the new terminal. `list` / `done` manage claims. Bundles `forge-lock.sh` — portable mkdir-based locks + in-place unit claims for multi-engineer setups without worktrees. |
| `forge-migrate` | Moves the context directory `context/` → `.forge/`: preview, confirm, git-history-preserving move, entry-point rewrite, `.gitignore` guard. |

## Agents

Nine bundled subagents route each kind of work to the right model — maximum
intelligence at the highest-leverage, lowest-frequency point, cheap models for bulk
work. An agent's reading never enters the main session's context; only its
conclusions do.

| Agent | Model | Role |
| ----- | ----- | ---- |
| `forge-architect` ("DevTeam") | **opus** | Decomposes features into units and writes the specs; deep ADR analysis. Runs rarely; its output steers every downstream token. |
| `forge-reviewer` ("Giuseppe") | **sonnet** | Adversarial, read-only diff-vs-spec review: scope creep, invariant violations, missing tests, silent breakage, overengineering, orthogonal edits. Verdict: `RECOMMEND PASS/FAIL`. |
| `forge-aligner` ("Tatti") | **sonnet** | Consistency checker: compares sibling features across eight dimensions (naming, layout, error handling, validation, data access, state, tests, implementation style) against the registered exemplar. |
| `forge-scout` ("Tim") | **haiku** | Read-many-conclude-little sweeps: stack & structure mapping, drift evidence, failure isolation. Compact findings with file:line evidence. |
| `forge-archivist` ("Tooba") | **haiku** | Mechanical bookkeeping: tracker rotation, spec archival, build-plan tidying, digest refresh, budget measurement. No judgment calls. |
| `forge-tester` ("Karen") | **sonnet** | `forge-review`'s **tests** lens: behavioral coverage of the diff, untested edge/error paths, hollow or flaky tests. Read-only. |
| `forge-failure-hunter` ("Pat") | **sonnet** | `forge-review`'s **errors** lens: swallowed catches, dangerous fallbacks, broken error propagation — failures that never surface. Read-only. |
| `forge-typer` ("Adam") | **sonnet** | `forge-review`'s **types** lens: encapsulation, invariants expressed in the type, illegal states left representable. Read-only. |
| `forge-commenter` ("Eleonor") | **sonnet** | `forge-review`'s **comments** lens: comment accuracy vs code, rot, stale docs. Read-only. |

`forge-build` deliberately has no pinned agent — intelligence is paid up front in the
spec, execution runs in your session's model (with an opus recommendation for units
marked `[complexity: high]`). Every delegation has an in-session fallback; edit the
`model:` line in `agents/*.md` (e.g. to `inherit`) to change the routing.

## Hooks

Four zero-token command hooks — shell scripts, no model calls, silent in projects
that don't use the plugin:

| Hook | What it does |
| ---- | ------------ |
| `SessionStart` | Injects the compact context digest (~600 tokens) with tiered-loading instructions; falls back to the full tracker in projects that predate the digest. |
| `PreToolUse` | Deterministic guard: denies edits to generated/lock/vendor files and any glob in `protected-paths`. Also records which skill is in use (for the status line). |
| `UserPromptExpansion` | Records `/forge-*` slash-command usage for the status line indicator. |
| `Stop` | If code changed without the tracker being updated, writes `.last-session.md` with the changed files and any context files over their token budget. Marks the skill indicator idle. |

**Local metrics (optional, opt-in):** the hooks can also record anonymous-to-nobody
NDJSON events (skill invocations, stop-with-changes) to
`~/.claude/forge-metrics/events.ndjson` — strictly local, nothing ever leaves the
machine. Enable with `touch ~/.claude/forge-metrics/enabled`; aggregate with
`hooks/scripts/forge-stats.sh [days]` (counts per skill/event/project plus a
debug-per-build "pressure" ratio for data-driven iteration on your own workflow).

**Status line (optional):** a ready-made status line ships at
`statusline/statusline.sh` — skill indicator (`⚒ forge-fix` while running,
`(forge-fix)` dimmed after), model, git branch, cost, context %. Copy it to
`~/.claude/forge-statusline.sh` and point your `statusLine` setting at it
(`refreshInterval: 1000`), or run `/statusline` and ask to merge the indicator into
your existing status line. State file contract:
`~/.claude/forge-status/<session_id>` → `active|idle <skill> <epoch>`.

## The context directory

Lives at **`context/`** (default, visible) or **`.forge/`** (hidden, tidy root, no
clash with framework `context/` folders) — one deterministic rule everywhere:
`.forge/` wins when it exists. Choose at init, or move later with `/forge-migrate`.

```
context/                  # or .forge/ — same layout either way
├── context-digest.md     # ~600-token brief injected every session (Tier 1)
├── project-overview.md   # what & why — goals, flows, features, scope
├── architecture.md       # stack, boundaries, storage, auth, invariants
├── ui-context.md         # colors, typography, components, layout
├── code-standards.md     # language / framework conventions
├── ai-workflow-rules.md  # agent behavior + code discipline rules
├── progress-tracker.md   # living state — active window only
├── patterns.md           # exemplar registry: "how we do X here"
├── modules/              # per-boundary context files (large projects)
├── .index.db             # FTS5 retrieval index (git-ignored, rebuildable)
├── lessons.md            # one-line lessons from corrections & diagnoses
├── ideas.md              # parked ideas from brainstorms (never auto-read)
├── decisions.md          # ADR log
├── specs/                # build plan + specs for pending units
│   └── archived/         # specs of completed units (never auto-read)
└── progress-archive.md   # rotated tracker history (never auto-read)
```

Plus `CLAUDE.md` (or `AGENTS.md`) at the project root — the lean entry point every
session reads first. Everything is plain, budgeted markdown in git: reviewable in
PRs, portable across machines and agents, no external services.

Two memory layers make corrections permanent: `lessons.md` per project
(auto-captured by the build loop and `forge-debug`, managed with `/forge-lesson`)
and `~/.context-forge/preferences.md` across projects (read only by `forge-init`,
written only with approval).

## Token economy

Reading everything every session is the main cost of context-driven workflows, so
Context Forge loads by tier:

- **Tier 1 — always:** the entry point + the digest (~600 tokens). When
  implementation starts, the live tracker too.
- **Tier 2 — per task:** only the file(s) the task touches — `ui-context.md` for UI
  work, `architecture.md` for boundary decisions, the exemplar for sibling
  features. The rule: *never guess to save tokens* — reading a file is always
  cheaper than a wrong implementation.
- **Tier 3 — everything:** reserved for init, audit, and compact.

Every file has a soft budget; history rotates into never-auto-read archives; the
`Stop` hook flags overruns; `/forge-compact` brings an over-budget project back
under. Verification runs with quiet/failures-only reporters, and the adversarial
reviewer is tiered — a full subagent review only where the stakes justify it.

Two mechanisms keep the cost flat as projects grow large:

- **Module contexts** — when the core files can't hold the whole system, each
  boundary gets its own budgeted `context/modules/<area>.md`; the core files
  shrink to the boundary map + global invariants, and a task loads only the
  module(s) it touches.
- **The retrieval index** — `forge-index.sh` builds a SQLite FTS5 index
  (`.index.db`, a git-ignored, rebuildable cache — markdown stays the source of
  truth) over every context artifact *including the never-auto-read archives*.
  Resume, spec, and debug query it for relevant history (`path:line` + snippet,
  ranked) at **zero model-token cost**, then read only the hits — no more blind
  grepping through hundreds of archived files.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) with plugin
  support; `git` (and optionally the [GitHub CLI](https://cli.github.com/)) for
  `forge-pr`.
- No language runtime required by the plugin itself — your project's own
  build/test/lint tooling is used during verification.

## Repository structure

```
context-forge/
├── .claude-plugin/          # plugin + marketplace manifests
├── skills/                  # the 21 forge-* skills (+ bundled templates,
│   └── .../                 #   references, detect/migrate scripts)
├── agents/                  # 9 model-pinned subagents
├── hooks/                   # hooks.json + zero-token shell scripts
├── statusline/              # reference status line with skill indicator
├── tests/                   # bats suite for every shell script + CI fixtures
├── .github/workflows/       # CI: shellcheck, plugin validate, bats (ubuntu+macos), fixture matrix
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Testing

Every deterministic script is covered by a [bats-core](https://github.com/bats-core/bats-core)
suite — hooks (including corrupt/empty/pre-digest context files), the worktree
claim lifecycle, locks, schema migration, and metrics:

```bash
bats tests/                              # the whole suite
bash tests/fixtures/smoke.sh modules     # one CI fixture: brownfield-empty | modules | no-git
```

CI runs shellcheck over every script, `claude plugin validate .`, the bats suite on
Ubuntu **and** macOS (BSD tool portability), and the fixture matrix.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md) for the
workflow, validation (`claude plugin validate .`), and versioning policy.

## License

Released under the [MIT License](./LICENSE).
