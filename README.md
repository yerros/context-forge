# Context Forge

> A Claude Code plugin that sets up and maintains the **Six-File Context Methodology** in any project — so your AI agent stays consistent across sessions and never guesses.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-6C5CE7.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Version](https://img.shields.io/badge/version-0.7.0-blue.svg)](./CHANGELOG.md)

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
/context-init        # set up (or adopt) the context files — detects your stack
/context-spec        # plan the build and write a spec for the next unit
/context-build       # implement that unit through the loop, strictly in scope
/context-verify      # confirm the unit is truly done
/context-pr          # ship it: branch, conventional commit, pull request
```

In later sessions, `/context-resume` restores full context (the `SessionStart` hook also
does this automatically). As the project grows, reach for `/context-feature`,
`/context-debug`, `/context-decision`, and `/context-audit`.

> Skills are namespaced by the plugin. If a bare name is ambiguous, use the fully
> qualified form, e.g. `/context-forge:context-init`.

## Commands

| Command | What it does |
| ------- | ------------ |
| `context-init` | Reads project state first, then either sets up fresh or **adopts & reconciles** an existing setup (fills gaps only, never overwrites). Detects the stack profile. Greenfield: planning conversation. Brownfield: analyzes the codebase, drafts from real evidence, confirms before writing. |
| `context-prompt` | Sharpens a rough request into a high-quality, context-aligned prompt or spec — clarifies goal, scope, constraints, and acceptance, then confirms. Never silently changes your intent. |
| `context-spec` | Spec-driven development: builds the ordered build plan (`context/specs/00-build-plan.md`) and writes a five-section spec file per feature unit. |
| `context-feature` | Adds a new feature to a working project: updates scope, inserts correctly-ordered units into the build plan, and generates the spec(s) — without breaking existing work. |
| `context-build` | Runs the disciplined implement → verify → close loop for one spec'd unit, strictly in scope, and keeps the tracker in sync. |
| `context-verify` | Runs the unit's verification checklist + build/typecheck/lint + an adversarial subagent review before a unit is closed. |
| `context-debug` | Stop-and-diagnose strategy when the agent is stuck or keeps getting something wrong: reproduce, isolate, re-read invariants, present options. |
| `context-pr` | Closes a verified unit with git: branch `feat/NN`, conventional commit, and a PR with a spec-derived summary. |
| `context-decision` | Logs an Architecture Decision Record (ADR) to `context/decisions.md` and keeps `architecture.md` in sync. |
| `context-audit` | Detects drift between the context files and the actual codebase and offers to update the docs. |
| `context-resume` | Reloads the context files + progress tracker at the start of a session and briefs you on where things stand. |

## Hooks

These run automatically and are silent in projects that don't use the methodology.

| Hook | What it does |
| ---- | ------------ |
All three hooks are **command-based** — they run small shell scripts, not model calls,
so they add **no token cost**. Each is silent/no-op in projects that don't use the
methodology.

| Hook | What it does |
| ---- | ------------ |
| `SessionStart` | If the project has a `context/` folder, injects the current `progress-tracker.md` and a reminder to read the context files first. |
| `PreToolUse` (Write/Edit) | Deterministic guard: denies edits to generated/lock/vendor files and to any glob listed in `context/protected-paths`. Allows everything else. |
| `Stop` | If code changed (per git) without the tracker being updated, writes `context/.last-session.md` with a timestamp and the changed-file list. Never re-wakes the model. |

> **Token cost:** because all hooks are command scripts, they don't consume model tokens.
> Nuanced/semantic invariant checking lives in `context-verify` (run per unit) rather than
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
first, every session. Optional additions: `context/specs/` (build plan + per-unit specs)
and `context/decisions.md` (ADR log).

## How it works

`context-init` runs a deterministic, read-only detector first and branches on its verdict,
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
  `context-pr` workflow.
- No language runtime is required by the plugin itself; your project's own build/test
  tooling is used during verification.

## Repository structure

```
context-forge/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # marketplace catalog (makes this repo installable)
├── skills/                  # the context-* skills
│   ├── context-init/        # + bundled templates, stack profiles, detect.sh
│   ├── context-spec/        # + spec template
│   ├── context-decision/    # + decisions (ADR) template
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
