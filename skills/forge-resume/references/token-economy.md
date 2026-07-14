# Token economy (shared reference)

The single source of truth for how context-forge keeps context loading cheap.
Used by `forge-resume` (tiered loading), `forge-build` / `forge-build-all` (load
step), `forge-compact` (budgets), `forge-audit` (budget check), and the close-unit
procedure (digest refresh). If budgets or tiers change, change them HERE only.

## Context directory

Two supported locations, resolved by one deterministic rule (`detect.sh` reports it
as `context_dir_path`): **`.forge/` wins when it exists** (hidden, tidy, no clash
with framework `context/` folders); otherwise **`context/`** (default, visible).
Every `context/...` path in the skills, agents, and references means "the resolved
context dir" — substitute `.forge/` throughout when the project uses it. The entry
point and the `SessionStart` hook state the resolved dir explicitly, so no session
has to guess.

## Principle

Context files exist so the agent never guesses — but re-reading everything every
session is the main token cost of the methodology. So: **always know a little
(the digest), read the rest only when the task needs it, and never guess** — if a
decision depends on a file you haven't read, read it before deciding.

## The digest

`context/context-digest.md` is a compact brief (~400–600 tokens) of the whole
context set: project one-liner, stack shape, top invariants, key conventions,
current state, and a tier map pointing to the full files. It is:

- created by `forge-init` (from the filled six files),
- refreshed in the **State** section at every close-unit,
- regenerated fully by `forge-compact` (and checked by `forge-audit`),
- injected automatically by the `SessionStart` hook (instead of the full tracker).

The digest **summarizes** the six files; it never replaces them as the source of
truth. When the digest and a full file disagree, the full file wins — and the
digest should be regenerated.

## Loading tiers

- **Tier 1 — always (cheap):** the entry point (`CLAUDE.md`/`AGENTS.md`), the
  digest, and — when starting implementation work — `context/progress-tracker.md`
  for live state. Cost ≈ 1.5–2.5 K tokens.
- **Tier 2 — per task:** only the full file(s) the task touches:

  | Task involves | Read |
  | --- | --- |
  | building or debugging | `context/lessons.md` first (tiny — known mistakes & rules) |
  | UI, styling, components | `context/ui-context.md` |
  | architecture, boundaries, storage, new dependencies | `context/architecture.md` |
  | writing/reviewing code | `context/code-standards.md` |
  | scope, features, product questions | `context/project-overview.md` |
  | workflow/process questions | `context/ai-workflow-rules.md` |
  | building a unit | the unit's spec + the files its sections touch |

- **Tier 3 — everything:** all six files in full. Reserved for `forge-init`
  (adopt/repair), `forge-audit`, `forge-compact`, and architectural decisions
  with cross-cutting impact.

Prompt-cache note: read stable files before volatile ones (tracker last) so the
unchanged prefix stays cacheable across sessions.

## Soft budgets (canonical)

| File | Budget |
| --- | --- |
| `context/context-digest.md` | ~2.5 KB / ~600 tokens |
| `context/lessons.md` | ~1.5 KB / ~400 tokens (memory contract: forge-lesson's memory.md) |
| `context/ideas.md` | ~1.5 KB / ~400 tokens (parking lot — never auto-read; forge-brainstorm) |
| `context/patterns.md` | ~2 KB / ~500 tokens (exemplar registry — read by architect/build for sibling features) |
| `context/progress-tracker.md` | ~6 KB / ~1,500 tokens (active window; see close-unit.md) |
| `architecture.md`, `ui-context.md`, `code-standards.md`, `project-overview.md`, `ai-workflow-rules.md` | ~10 KB / ~2,500 tokens each |
| Entry point (`CLAUDE.md`/`AGENTS.md`) | keep lean; big tables/reference blocks go in on-demand files |

Approximation: tokens ≈ bytes / 4. Measure with:

```bash
for f in CLAUDE.md AGENTS.md context/*.md; do
  [ -f "$f" ] && printf '%-34s %6s bytes  ~%5s tok\n' "$f" "$(wc -c <"$f")" "$(( $(wc -c <"$f") / 4 ))"
done
```

Over budget ⇒ tracker: rotate (close-unit.md); digest: regenerate tighter; core
files: tighten prose or split detail into an on-demand `context/reference/` file;
or run `forge-compact` for a guided pass. The `Stop` hook (`track.sh`) also flags
over-budget files in `context/.last-session.md` — zero tokens until read.

## Subagent & background cost

Context tokens aren't the only cost — usage quota counts every model call,
including subagents and background workers:

- **Tiered review**: a full `forge-reviewer` run is a whole subagent session. It's
  automatic only for `[complexity: high]` / invariant-touching units; standard
  units are reviewed in-session against the same hunt list (see forge-verify).
- **Quiet verification output**: run tests/linters with quiet or failures-only
  reporters. A green suite should cost one summary line, not thousands of passing
  lines re-read on every verify-loop iteration.
- **claude-mem interop**: if the claude-mem plugin is active, its `PostToolUse`
  hook sends every tool output to a background AI compression worker — on a heavy
  build day that's hundreds of extra model calls against the same quota, invisible
  in the session context. The two plugins coexist fine (context-forge is curated
  memory, claude-mem is episodic recall; on conflict the context files win), but
  for long `forge-build`/`forge-build-all` runs consider disabling claude-mem and
  re-enabling it for exploratory sessions — this plugin's tracker, lessons, and
  archives already record the build trail deterministically at zero token cost.

## Rules

- Never guess to save tokens — reading a Tier 2 file is always cheaper than a
  wrong implementation.
- Never trim meaning: compression (by `forge-compact` or by hand) rewrites for
  density, it does not drop facts, invariants, or decisions without user approval.
- Specs and archives (`specs/archived/`, `progress-archive.md`) are never
  auto-read and never count against session cost — don't load them unless asked.
