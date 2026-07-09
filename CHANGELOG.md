# Changelog

All notable changes to the **context-forge** plugin are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.10.1] — 2026-07-10

### Fixed
- **README brought back in sync**: version badge 0.8.0 → current, duplicate/broken Hooks
  table header removed, leftover "context-\* skills" label renamed to `forge-*`, and the
  0.9.0/0.10.0 features (`context/specs/archived/`, `context/progress-archive.md`,
  tracker rotation, `forge-audit` budget check) are now documented in Features and
  "The six files".
- **`marketplace.json` version drift** (was still 0.9.0 while the plugin was 0.10.0);
  both manifests now carry the same version.
- **`templates/AGENTS.md` synced with `templates/CLAUDE.md`** — the lean-window /
  `progress-archive.md` note now appears in both entry-point templates.
- **`detect.sh` accuracy**: `spec_files` no longer counts `00-build-plan.md` as a spec,
  and the placeholder counter no longer matches markdown links `[text](url)` or task
  checkboxes `[ ]`/`[x]` — fixing false REPAIR verdicts on fully filled files.
- **Shipping is one door again**: the Close step of `forge-build` and the three-prompt
  loop in `forge-spec` now point to `forge-pr` instead of instructing a raw branch push
  (also fixes the "suggest the suggested git step" typo).
- **`guard.sh`**: project-relative globs in `context/protected-paths` (e.g.
  `src/generated/*`) now also match when the tool sends an absolute path, and the guard
  reads `notebook_path` too; the `PreToolUse` matcher now covers `NotebookEdit`.
- `forge-audit`: `ai-workflow-rules.md` now has a soft budget like the other core files;
  minor formatting fix in the Output section.

### Changed
- **Close-unit logic deduplicated.** The full procedure (tracker update + rotation, spec
  archival, build-plan tidy, context-file sync) now lives once in
  `skills/forge-build/references/close-unit.md`; `forge-build`, `forge-build-all`, and
  `forge-pr` reference it instead of each carrying their own copy. The active-window
  numbers (~10 Completed / ~8 Session Notes / ~6 KB) are defined there canonically.
- All skill `metadata.version` values bumped to match the plugin version.

## [0.10.0] — 2026-06-15

### Added (token efficiency)
- **Automatic progress-tracker rotation.** The tracker now holds an *active window* only
  (current phase/goal, In Progress, Next Up, Open Questions, the ~10 most recent Completed
  units, and the ~8 most recent Session Notes). When a unit closes and the tracker grows
  past that window — or past ~6 KB / ~1,500 tokens — `forge-build`, `forge-build-all`, and
  `forge-pr` move the oldest Completed entries and Session Notes into a new
  `context/progress-archive.md` (history; appended newest-first). Because the tracker is
  re-read on every `forge-resume` / `forge-build`, this caps a file that previously grew
  unbounded — a pure token saving with no loss of active context. The archive is **not**
  auto-read.
- **Compact session notes.** Close steps now write a one- to two-line Session Note instead
  of an open-ended paragraph, keeping the recurring read cost low.
- **Context budget check in `forge-audit`.** The audit now measures each context file's
  size (bytes / approx tokens) against soft budgets and recommends trimming or rotating
  when a file is over — the tracker (~1,500 tokens) and core files (~2,500 tokens each).
- **Prompt-cache-friendly read order** documented in `forge-resume`: stable files first,
  the volatile tracker last, so the unchanged prefix stays cacheable across sessions.

### Changed
- `forge-init` templates (`progress-tracker.md`, `CLAUDE.md`) now declare the lean active
  window and the `progress-archive.md` convention, so new projects start token-efficient.

## [0.9.0] — 2026-06-15

### Changed (breaking)
- **All commands renamed from `context-*` to `forge-*`** for a shorter, faster-to-type
  prefix tied to the plugin name. `context-build` → `forge-build`, `context-spec` →
  `forge-spec`, and so on for all twelve skills (`forge-audit`, `forge-build`,
  `forge-build-all`, `forge-debug`, `forge-decision`, `forge-feature`, `forge-init`,
  `forge-pr`, `forge-prompt`, `forge-resume`, `forge-spec`, `forge-verify`). The
  **methodology name ("Six-File Context Methodology") and the `context/` data directory
  are unchanged** — only the command/skill names moved.

### Added
- **Completed specs are now archived.** When a unit closes, `forge-build` /
  `forge-build-all` / `forge-pr` move its spec from `context/specs/` into
  `context/specs/archived/`, and move its line in `context/specs/00-build-plan.md` from
  the active `## Units` list into a `## Completed` section at the bottom. The active
  `specs/` folder and build plan therefore only ever show work that is still pending,
  while finished specs stay on disk as a record. `forge-resume` and `forge-audit` are
  aware of the `archived/` folder (resume treats the active `specs/` as the remaining
  work; audit flags archive/build-plan drift).

## [0.8.0] — 2026-06-14

### Added
- **`context-build-all`** skill — runs the implement → verify → close loop across every
  remaining unit in the build plan, in order, updating the tracker after each. It is the
  autonomous, multi-unit counterpart to `context-build`. For safety it builds strictly to
  each spec, verifies every unit, and **stops at the first failure** (missing spec,
  failed verification, ambiguity, or invariant violation) instead of continuing on an
  unverified foundation. It does not auto-push or open PRs — shipping stays with
  `context-pr`. Supports an optional scope (e.g. "build units 3–7").

## [0.7.0] — 2026-06-14

### Changed
- **Both prompt-based hooks are now command-based (zero model tokens).** They run small,
  tested shell scripts instead of per-event model evaluations, removing the recurring
  token/latency cost while keeping the hooks active.
  - `PreToolUse` → `hooks/scripts/guard.sh`: deterministic guard that denies edits to
    generated/lock/vendor files (`node_modules`, `*.lock`, `*-lock.json`, etc.) and to any
    glob listed in an optional `context/protected-paths` file; allows everything else.
  - `Stop` → `hooks/scripts/track.sh`: if code changed (per git) without the tracker being
    updated, writes `context/.last-session.md` (timestamp + changed files). Overwrites, so
    it never grows; writes nothing to stdout, so it never re-wakes the model.
- `context-resume` now also reads `context/.last-session.md` when present.

### Notes
- Semantic/nuanced invariant checking now lives in `context-verify` (run per unit) instead
  of on every edit. Add `context/.last-session.md` to your project's `.gitignore` if you
  don't want to commit it.

## [0.6.2] — 2026-06-13

### Removed
- **`UserPromptSubmit` hook.** A prompt-based `UserPromptSubmit` hook can return a
  `block` decision, and in practice it blocked legitimate user messages it judged
  "not substantive" (e.g. bug reports and in-progress notes) instead of merely adding
  context. Because this hook intercepts every prompt and can block input, it is removed
  for reliability. Prompt optimization remains available, safely and on demand, via the
  **`context-prompt`** skill.

### Notes
- Remaining prompt-based hooks are `PreToolUse` (guards invariants on writes) and `Stop`
  (keeps the tracker in sync); neither blocks user input.

## [0.6.1] — 2026-06-13

### Fixed
- **Hook loading failure** in Claude Code (`Hook load failed: expected record, received
  undefined` at path `hooks`). The plugin's `hooks/hooks.json` listed events at the top
  level; Claude Code requires them wrapped under a top-level `"hooks"` key. All four
  events are now nested correctly under `hooks`.

## [0.6.0] — 2026-06-13

### Added
- **`context-prompt`** skill — an opt-in prompt refiner that turns a rough request into a
  high-quality, context-aligned prompt or spec (goal / scope / constraints / acceptance),
  asking 1–2 clarifying questions only when needed. It never silently changes intent.
- **`UserPromptSubmit`** hook — a conservative, *augmenting* hook: for substantive build
  requests in a `context/` project it injects relevant context pointers and, when the
  request is vague, a suggested sharper phrasing. It never rewrites the user's message and
  stays silent for casual chat and one-line fixes.

### Notes
- The plugin now has three prompt-based hooks (`UserPromptSubmit`, `PreToolUse`, `Stop`).
  Each adds a small evaluation; remove any block from `hooks/hooks.json` to disable it.

## [0.5.0] — 2026-06-13

### Added
- `.claude-plugin/marketplace.json` so the repository is installable as a Claude Code
  plugin marketplace (`/plugin marketplace add yerros/context-forge`).
- Open-source project files: a rewritten OSS-standard `README.md` (English), `LICENSE`
  (MIT), `CONTRIBUTING.md`, and `.gitignore`.

### Changed
- Renamed the plugin from `six-file-context` to **`context-forge`** for branding.
- Author set to **yerros** (https://github.com/yerros); added homepage.
- No functional changes to skills/hooks — all ten skills, three hooks, and the detector
  are unchanged.

## [0.4.0] — 2026-06-13

### Added
- **Deterministic state detection** (`skills/context-init/scripts/detect.sh`, read-only):
  reports a `verdict` of `SETUP`, `ADOPT`, or `REPAIR` plus the facts behind it (which of
  the six files exist, count of unfilled `[placeholder]` markers, entry point, decisions/
  specs presence, codebase detection). Skills act on facts instead of guessing — this is
  the core robustness fix for "project already has context files".
- **Adopt & reconcile flow** in `context-init` for projects that already use the
  methodology (manual setup or a prior run): recognizes the existing files, fills only
  gaps, **never overwrites real content**, confirms before every write, and is idempotent
  (running it on a healthy project changes nothing).

### Changed
- `context-init` now runs the detector first and branches on the verdict.
- `context-audit` and `context-resume` run the detector first and handle the
  not-set-up / incomplete cases gracefully.

## [0.3.0] — 2026-06-13

### Added
- **`context-feature`** skill — add a feature to a working project: updates scope in
  `project-overview.md`, inserts correctly-ordered units into the build plan, and
  generates the spec(s) without breaking existing work.
- **`context-debug`** skill — stop-and-diagnose strategy for when the agent is stuck or
  keeps getting something wrong (reproduce, isolate, re-read invariants, present options,
  fix root cause in scope).
- **`context-pr`** skill — closes a verified unit with git: branch `feat/NN`, Conventional
  Commit, and a PR with a spec-derived summary (uses `gh` when available).
- **`context-decision`** skill — logs ADRs to `context/decisions.md` and keeps
  `architecture.md` in sync; bundles a `decisions.md` template.
- **Stack profiles** — `context-init` now detects the project type (web / backend-API /
  mobile / CLI-library / data-ML) and adapts which files matter and what each emphasizes
  (e.g. drops or repurposes `ui-context.md` for a pure API). See
  `skills/context-init/references/stack-profiles.md`.

### Changed
- `Stop` hook now also maintains a dated "Resume here:" note in Session Notes.
- README documents ten skills, three hooks, and stack profiles.
- Version bumped to 0.3.0.

### Notes
- A `SessionEnd` LLM summary was considered but not added: the hook system only supports
  prompt-based hooks on `Stop`, `SubagentStop`, `UserPromptSubmit`, and `PreToolUse`.
  The `Stop` hook covers session continuity instead.

## [0.2.0] — 2026-06-13

### Added
- **`context-build`** skill — runs the disciplined implement → verify → close loop for
  a single spec'd unit, strictly in scope, and keeps the progress tracker in sync.
- **`context-verify`** skill — runs the unit's verification checklist plus
  build/typecheck/lint and an adversarial subagent review before a unit is closed.
- **`context-audit`** skill — detects drift between the six context files and the
  actual codebase and offers to update the docs.
- **Hooks** (`hooks/hooks.json`):
  - `SessionStart` — injects `progress-tracker.md` and a reminder to read the context
    files when the project has a `context/` folder; silent otherwise.
  - `Stop` — keeps `progress-tracker.md` in sync after a response that changed code.
  - `PreToolUse` (Write/Edit/MultiEdit) — checks changes against the invariants in
    `architecture.md` and rules in `code-standards.md`; flags or blocks clear violations.

### Changed
- README documents all six skills and the three hooks.
- `plugin.json` description and version bumped to 0.2.0.

### Notes
- The `Stop` and `PreToolUse` hooks are prompt-based and add a small LLM evaluation per
  response / per edit. Remove the relevant block in `hooks/hooks.json` to disable.

## [0.1.0] — 2026-06-13

### Added
- Initial release.
- **`context-init`** skill — scaffolds the `context/` folder (six files) plus the entry
  point (`CLAUDE.md`/`AGENTS.md`). Greenfield mode runs a planning conversation;
  brownfield mode analyzes the existing codebase, drafts files from evidence, and
  confirms before writing.
- **`context-spec`** skill — builds the ordered build plan and writes five-section spec
  files per feature unit.
- **`context-resume`** skill — reloads the six files + progress tracker and briefs the
  user at the start of a session.
- Bundled blank templates for all six context files, the entry point, and a spec file.
