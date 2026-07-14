---
name: forge-lesson
description: >
  This skill should be used to save or manage persistent memory in a Six-File Context
  Methodology project — phrases like "forge-lesson", "remember this", "log a lesson",
  "don't make that mistake again", "note this for next time", "save this as a
  preference", or "forget that lesson". It appends a distilled one-line lesson to
  context/lessons.md (or a cross-project preference to ~/.context-forge/preferences.md
  with approval), keeps both within budget, and promotes recurring lessons into the
  real context files.
metadata:
  version: "0.18.1"
---

# forge-lesson

Turn a correction, diagnosis, or preference into persistent memory — so it's never
re-paid in tokens. The memory contract (formats, budgets, read/write rules) is
defined canonically in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md` — read it first.

## Argument

Text after the command is the lesson or instruction (e.g. `/forge-lesson never use
barrel files here`, `/forge-lesson forget the Vite one`, `/forge-lesson show`) —
distill/act on it directly. No argument → ask what to remember (or manage).

## Steps

### 1. Distill

Reduce what happened to one line: `- [area] symptom/trigger → rule`. The rule part
must be imperative and actionable. If it can't fit one line, it isn't a lesson — it's
documentation; put it in the right context file instead and say so.

### 2. Route

- **Project-specific** (about this codebase, its stack, its conventions) →
  `context/lessons.md`. Create the file from the bundled template
  (`${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/lessons.md`) if absent.
- **Cross-project** (a preference the user would want everywhere: tooling choices,
  style defaults, workflow habits) → offer `~/.context-forge/preferences.md`
  instead. Never write there without explicit approval.
- **Already a rule?** If the lesson duplicates something in `code-standards.md` /
  `ai-workflow-rules.md` / `architecture.md`, don't add it — tell the user it's
  already covered (or fix the context file if it's wrong there).

### 3. Write (show the line first)

Show the exact line to be added and where; append on approval, newest last. Check
for an existing similar lesson and merge instead of duplicating.

### 4. Enforce the budget

If `lessons.md` is over ~1.5 KB after the write: propose dedupe/generalize merges,
**promote** lessons that have become real conventions into the appropriate context
file (that's the goal), and drop lines about code that no longer exists — with
approval per change.

## Also handles

- **"Forget X" / "that lesson is wrong"** — find and remove or correct the line.
- **"Show my lessons / preferences"** — print the relevant file with line numbers.
- **Promotion requests** — move a lesson into a context file and delete it here.

## Rules

- One line per lesson; never paragraphs.
- Every write is shown to the user first — memory belongs to the user.
- Never store secrets or project-specific facts in the global preferences file.
