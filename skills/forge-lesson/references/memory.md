# Persistent memory (shared reference)

The single source of truth for context-forge's two memory layers. Used by
`forge-lesson` (manual logging), `forge-debug` (auto-capture on resolution), the
close-unit procedure (capture corrections), `forge-init` (global preferences),
`forge-compact` (compression/promotion), and `forge-audit` (staleness check). If the
rules change, change them HERE only.

Memory only saves tokens if it obeys the same token-economy discipline as everything
else: hard budgets, on-demand reads, and aggressive distillation. A memory file that
bloats is worse than no memory at all.

## Layer 1 — project lessons: `context/lessons.md`

**What it is:** corrections and hard-won diagnoses that would otherwise be re-paid in
tokens next session. One line each: `- [area] symptom/trigger → rule`. Examples:

```
- [build] Vite env vars undefined in prod → only VITE_-prefixed vars reach the client
- [db] Drizzle migrate hangs in CI → run with --config at repo root, not cwd
- [review] User rejects barrel files → import directly from the module
```

**Written by (append one line, newest last):**
- `forge-debug` — when a debugging session ends with a confirmed root cause worth
  remembering (not every bug: only ones likely to recur or that cost real effort).
- The close-unit procedure — when the user corrected the agent's approach during the
  unit in a way that generalizes beyond that unit.
- `forge-lesson` — when the user explicitly says "remember this" / "log a lesson".

**Read at Tier 1½:** `forge-build`, `forge-build-all`, and `forge-debug` read it at
load time, right after the digest (it's small). Other skills don't.

**Budget: ~1.5 KB / ~400 tokens (≈ 12–15 lessons).** When full, don't just append:
1. **Dedupe/generalize** — merge lessons that are instances of one rule.
2. **Promote** — a lesson that has become a real convention belongs in
   `code-standards.md` / `ai-workflow-rules.md` / `architecture.md` (invariant);
   move it there and delete the lesson line.
3. **Drop** — lessons about code that no longer exists.
Promotion is the goal: `lessons.md` is a staging area for rules, not a landfill.

**Quality bar for a lesson:** actionable ("→ rule" part is imperative), general
enough to recur, not already covered by a context file, one line. If it needs a
paragraph, it's documentation — put it in the right context file instead.

## Layer 2 — global preferences: `~/.context-forge/preferences.md`

**What it is:** the user's cross-project defaults, so `forge-init` stops re-asking
and mis-guessing on every new project. Same one-line format, grouped:

```
## Tooling
- package manager: pnpm (never npm)
## Conventions
- TypeScript strict always; no `any`
- prefers Tailwind + shadcn/ui for web UI
## Workflow
- commits: conventional, English; PR descriptions short
```

**Read by:** `forge-init` only — at the start of the greenfield conversation or
brownfield draft, to pre-fill defaults. Say so when a preference is applied ("using
pnpm per your saved preferences") so the user can override. Project evidence always
beats a global preference: on brownfield, what the codebase shows wins.

**Written by:** `forge-init` (end of a run) and `forge-lesson` (when a lesson is
clearly cross-project, offer to store it globally instead). **Always ask before
writing** — this file lives outside the repo, is not git-versioned, and is shared
across all the user's projects. Never store secrets, tokens, or project-specific
facts in it.

**Budget: ~2 KB.** Same discipline: dedupe, keep one line per preference.

## Rules

- Every write to either file is shown to the user (the line being added) — memory is
  the user's, not the agent's.
- Never auto-read `~/.context-forge/preferences.md` outside `forge-init` /
  `forge-lesson` — per-session cost must stay near zero.
- On conflict, the more local source wins: code > context files > lessons > global
  preferences.
- Deleting or editing memory is always allowed — `forge-lesson` handles "forget X".
