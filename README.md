# Context Forge

> A Claude Code plugin that sets up and maintains the **Six-File Context Methodology** in any project — so your AI agent stays consistent across sessions and never guesses.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-6C5CE7.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Version](https://img.shields.io/badge/version-0.13.1-blue.svg)](./CHANGELOG.md)

Context Forge turns a proven workflow into something you install once and run in every
project — no more copying template files by hand. It scaffolds the context files, plans
and builds features spec-by-spec, verifies and debugs, logs decisions, and keeps your
documentation in sync with your code automatically.

The core idea of the methodology: **you are the architect, the AI is the implementation
engine.** A small set of context files captures your thinking up front, so the agent
executes a defined system instead of guessing — and stays consistent across every
session and feature.

---

## Table of contents

- [Why](#why)
- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Hooks](#hooks)
- [The six files](#the-six-files)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Repository structure](#repository-structure)
- [Contributing](#contributing)
- [License](#license)
- [Credits](#credits)

## Why

Two failure modes plague AI-assisted projects:

1. **Vibe-coding collapse** — the agent builds fast for an hour, then starts contradicting
   its own earlier decisions and the codebase begins fighting you.
2. **Feature drift** — you return weeks later and the agent has forgotten every
   architectural decision, "fixing" things that were never broken.

Both have the same root cause: the agent has no documented system to work within, and no
memory between sessions. Context Forge fixes that by giving the agent a foundation to read
before it writes anything, and a living tracker that restores full context in one step.

## Features

- **One-command setup** for new *or* existing projects — install once, use everywhere.
- **Brownfield-aware** — analyzes an existing codebase and drafts the context files from
  real evidence, then confirms with you before writing.
- **Adopt & reconcile** — if a project already has context files (manual or from a prior
  run), it recognizes them and fills only the gaps, never overwriting your content.
- **Stack-aware** — detects web / backend-API / mobile / CLI-library / data-ML projects
  and adapts the files accordingly.
- **Spec-driven build loop** — plan, build, verify, and ship one scoped unit at a time.
- **Self-maintaining docs** — hooks keep the progress tracker in sync and guard your
  architectural invariants on every edit.
- **Token-efficient by design** — a compact `context-digest.md` (~600 tokens) is what
  every session loads by default; the full files are read **per task, by tier**, not
  wholesale. The tracker keeps only an *active window* (older history rotates into
  `context/progress-archive.md`), completed specs are archived into
  `context/specs/archived/`, `forge-audit` checks every file against a soft token
  budget, and `forge-compact` brings an over-budget project back under it.
- **Persistent memory, the plain-text way** — corrections and hard-won diagnoses are
  distilled into one-line lessons in `context/lessons.md` (auto-captured by
  `forge-debug` and the build loop, managed with `forge-lesson`), and cross-project
  preferences in `~/.context-forge/preferences.md` stop `forge-init` from re-asking
  the same questions in every project. No vector store, no external services — just
  budgeted markdown in git.
- **Zero configuration** — no credentials or setup; templates ship inside the plugin.

## Installation

Context Forge is distributed as a Claude Code plugin via this repository, which doubles as
a plugin marketplace.

### From the marketplace (recommended)

Inside Claude Code:

```shell
/plugin marketplace add yerros/context-forge
/plugin install context-forge@yerros
```

Or from your terminal (non-interactive):

```bash
claude plugin marketplace add yerros/context-forge
claude plugin install context-forge@yerros
```

Then restart Claude Code if prompted. Verify with `/plugin` to see Context Forge listed
and enabled.

### Local / from source

Clone the repo and add it as a local marketplace:

```bash
git clone https://github.com/yerros/context-forge.git
```

```shell
/plugin marketplace add ./context-forge
/plugin install context-forge@yerros
```

### Updating

```shell
/plugin marketplace update yerros
```

## Quick start

From inside any project you want to manage:

```shell
/forge-init        # set up (or adopt) the context files — detects your stack
/forge-spec        # plan the build and write a spec for the next unit
/forge-build       # implement that unit through the loop, strictly in scope
/forge-build-all   # or: build every remaining unit in one run, stopping on first failure
/forge-verify      # confirm the unit is truly done
/forge-pr          # ship it: branch, conventional commit, pull request
```

In later sessions, `/forge-resume` restores context tier by tier (the `SessionStart`
hook already injects the compact digest automatically). As the project grows, reach
for `/forge-feature`, `/forge-fix` (bug reports), `/forge-debug` (when stuck),
`/forge-decision`, `/forge-audit`, and — when the context files get heavy —
`/forge-compact`.

> Skills are namespaced by the plugin. If a bare name is ambiguous, use the fully
> qualified form, e.g. `/context-forge:forge-init`.

## Commands

| Command | What it does |
| ------- | ------------ |
| `forge-init` | Reads project state first, then either sets up fresh or **adopts & reconciles** an existing setup (fills gaps only, never overwrites). Detects the stack profile. Greenfield: planning conversation. Brownfield: analyzes the codebase, drafts from real evidence, confirms before writing. |
| `forge-prompt` | Sharpens a rough request into a high-quality, context-aligned prompt or spec — clarifies goal, scope, constraints, and acceptance, then confirms. Never silently changes your intent. |
| `forge-spec` | Spec-driven development: builds the ordered build plan (`context/specs/00-build-plan.md`) and writes a five-section spec file per feature unit. |
| `forge-feature` | Adds a new feature to a working project: updates scope, inserts correctly-ordered units into the build plan, and generates the spec(s) — without breaking existing work. |
| `forge-build` | Runs the disciplined implement → verify → close loop for one spec'd unit, strictly in scope, and keeps the tracker in sync. |
| `forge-build-all` | Runs the build loop across **all** remaining units in order until the plan is complete, verifying each and **stopping at the first failure**. The autonomous, multi-unit version of `forge-build`. |
| `forge-verify` | Runs the unit's verification checklist + build/typecheck/lint + an adversarial subagent review before a unit is closed. |
| `forge-fix` | Intake for bug reports in shipped work: reproduce, triage (fix directly when the cause is obvious; hand off to `forge-debug` when it isn't), verify, and close with tracker + lesson + `fix/` branch. |
| `forge-debug` | Stop-and-diagnose strategy when the agent is stuck or keeps getting something wrong: reproduce, isolate, re-read invariants, present options. |
| `forge-pr` | Closes a verified unit with git: branch `feat/NN`, conventional commit, and a PR with a spec-derived summary. |
| `forge-decision` | Logs an Architecture Decision Record (ADR) to `context/decisions.md` and keeps `architecture.md` in sync. |
| `forge-audit` | Detects drift between the context files (including the digest) and the actual codebase, checks token budgets, and offers to update the docs. |
| `forge-resume` | Restores context tier by tier at the start of a session (digest + tracker first, full files per task) and briefs you on where things stand. |
| `forge-compact` | Token-maintenance pass: measures every context file against its budget, compresses over-budget files with approval, rotates tracker history, and (re)generates `context-digest.md`. |
| `forge-lesson` | Saves a correction or diagnosis as a one-line lesson in `context/lessons.md` (or a cross-project preference in `~/.context-forge/preferences.md`, with approval), keeps memory within budget, and promotes recurring lessons into the real context files. |

## Hooks

These run automatically and are silent in projects that don't use the methodology.

All three hooks are **command-based** — they run small shell scripts, not model calls,
so they add **no token cost**. Each is silent/no-op in projects that don't use the
methodology.

| Hook | What it does |
| ---- | ------------ |
| `SessionStart` | Injects the compact `context-digest.md` (~600 tokens) with tiered-loading instructions; falls back to the full `progress-tracker.md` in projects that predate the digest. |
| `PreToolUse` (Write/Edit) | Deterministic guard: denies edits to generated/lock/vendor files and to any glob listed in `context/protected-paths`. Allows everything else. |
| `Stop` | If code changed (per git) without the tracker being updated, writes `context/.last-session.md` with a timestamp, the changed-file list, and any context files over their token budget. Never re-wakes the model. |

> **Token cost:** because all hooks are command scripts, they don't consume model tokens.
> Nuanced/semantic invariant checking lives in `forge-verify` (run per unit) rather than
> on every edit. To disable a hook, remove its block from `hooks/hooks.json`.

**Optional:** create a `context/protected-paths` file (one glob per line) to extend the
`PreToolUse` guard — for example `src/generated/*` or `*.snap`. Consider adding
`context/.last-session.md` to your project's `.gitignore`.

## The six files

```
context/
├── project-overview.md   # what & why — goals, flows, features, scope
├── architecture.md       # stack, boundaries, storage, auth, invariants
├── ui-context.md         # colors, typography, components, layout
├── code-standards.md     # language / framework conventions
├── ai-workflow-rules.md  # how the agent should behave while building
└── progress-tracker.md   # living state — updated after every change
```

Plus `CLAUDE.md` (or `AGENTS.md`) at the project root — the entry point the agent reads
first, every session — and `context/context-digest.md`, the compact brief that powers
tiered loading. Optional additions: `context/specs/` (build plan + per-unit specs),
`context/decisions.md` (ADR log), `context/specs/archived/` (specs of completed units,
moved there automatically when a unit closes), and `context/progress-archive.md`
(rotated tracker history — written automatically, never auto-read).

### Token economy (tiered loading)

Reading all six files every session is the methodology's main token cost, so
context-forge loads by tier instead:

- **Tier 1 — always:** the entry point + `context-digest.md` (~600 tokens: project
  one-liner, stack shape, top invariants, current state, and a tier map). The
  `SessionStart` hook injects it automatically. When implementation starts, the live
  `progress-tracker.md` is read too.
- **Tier 2 — per task:** only the full file(s) the task touches — `ui-context.md`
  for UI work, `architecture.md` for boundary/storage/dependency decisions, and so
  on. The rule is *never guess to save tokens*: reading a file is always cheaper
  than a wrong implementation.
- **Tier 3 — everything:** reserved for `forge-init`, `forge-audit`, and
  `forge-compact`.

The digest is generated by `forge-init`, refreshed at every unit close, and checked
by `forge-audit`. `progress-tracker.md` holds an **active window** only (~10 recent
Completed units, ~8 recent Session Notes, ~6 KB); older history rotates into
`progress-archive.md` at close. The `Stop` hook flags any file over its soft budget
in `context/.last-session.md`, and `forge-compact` is the guided pass that brings
everything back under budget.

### Persistent memory

Two thin, budgeted memory layers turn one-time corrections into permanent rules —
the cheapest token saving there is, because a remembered lesson never has to be
re-debugged:

- **`context/lessons.md`** (per project, ~1.5 KB) — one line per lesson:
  `- [area] symptom → rule`. Auto-captured when `forge-debug` confirms a root cause
  worth remembering or when a unit close notes a generalizable correction; read by
  `forge-build`/`forge-debug` at load time. When full, lessons are merged or
  **promoted** into `code-standards.md`/`ai-workflow-rules.md` — the lessons file is
  a staging area for rules, not a landfill.
- **`~/.context-forge/preferences.md`** (cross-project, ~2 KB) — tooling and
  convention defaults read only by `forge-init` to pre-fill new projects. Written
  only with explicit approval; project evidence always wins over a preference.

Manage both with `/forge-lesson` ("remember this", "forget that", "show my
lessons"). Every memory write is shown to you first.

## How it works

`forge-init` runs a deterministic, read-only detector first and branches on its verdict,
so it never assumes a project is empty:

- **`SETUP`** — no context files → fresh setup (greenfield conversation or brownfield
  analysis), with a stack profile applied.
- **`ADOPT`** — all six files present and filled → recognizes the existing setup and only
  reconciles gaps. Idempotent: a healthy project is left unchanged.
- **`REPAIR`** — `context/` exists but is incomplete or still a blank template → fills the
  gaps without touching real content.

Everything else follows the spec-driven loop: decompose the build into ordered, verifiable
units; build one unit at a time exactly to its spec; verify against a checklist; ship.
The progress tracker keeps every session grounded in the real state of the project.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) with plugin support.
- `git` (and optionally the [GitHub CLI](https://cli.github.com/) `gh`) for the
  `forge-pr` workflow.
- No language runtime is required by the plugin itself; your project's own build/test
  tooling is used during verification.

## Repository structure

```
context-forge/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # marketplace catalog (makes this repo installable)
├── skills/                  # the forge-* skills
│   ├── forge-init/        # + bundled templates, stack profiles, detect.sh
│   ├── forge-spec/        # + spec template
│   ├── forge-decision/    # + decisions (ADR) template
│   └── ...
├── hooks/
│   ├── hooks.json           # SessionStart, PreToolUse, Stop (all command-based)
│   └── scripts/             # guard.sh (PreToolUse), track.sh (Stop)
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for the
development workflow, how to validate the plugin, and the versioning policy. In short:
open an issue to discuss substantial changes, keep skills focused and imperative, run
`claude plugin validate .`, and bump the version on every release.

## License

Released under the [MIT License](./LICENSE).

## Credits

Context Forge implements the **Six-File Context System**, described in *"From Idea to
Product: The AI-Driven Developer's Playbook"* by
[JavaScript Mastery](https://youtube.com/@javascriptmastery). This plugin is an
independent implementation of that methodology and is not affiliated with or endorsed by
JavaScript Mastery.

Built and maintained by [yerros](https://github.com/yerros).
