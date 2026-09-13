---
name: forge-lesson
description: >
  This skill should be used to save or manage persistent memory in a Context Forge
  Methodology project — phrases like "forge-lesson", "remember this", "log a lesson",
  "don't make that mistake again", "note this for next time", "save this as a
  preference", or "forget that lesson". It appends a distilled one-line lesson to
  context/lessons.md (or a cross-project preference to ~/.context-forge/preferences.md
  with approval), keeps both within budget, and promotes recurring lessons into the
  real context files.
metadata:
  version: "0.26.0"
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

### 0. Check the candidates file

If `context/.lesson-candidates.md` exists (the `UserPromptSubmit` hook appends every
prompt shaped like a correction — "no, X; do Y instead"), read it first: each line is
a candidate. Distill the real ones through steps 1–3, discard the noise, then delete
the lines you handled. The file is local and never committed.

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

### 2½. Ratchet — can a tool catch it?

Before writing, ask one question: **is the rule mechanically checkable** (a
banned call, a naming pattern, a forbidden import, a raw literal)? If yes, the
lesson does not stay a lesson:

- Add a line to `context/rules.txt` (`ID|Severity|glob|message|regex`; create
  the file from `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/rules.txt`
  if absent), and a matching rule card in `code-standards.md` marked
  `enforced: tool` — next ID in the section, ✗/✓ pair from the actual incident.
- Or, when the project has a linter with an equivalent rule, propose that config
  change instead.
- The lesson line still goes in (it's the *why*), ending with `→ CS-NNN`.

Show the regex hitting the original offending line before claiming it works.
A lesson the reviewer must remember is re-paid every review; a rule a script
runs is paid once.

### 3. Write (show the line first)

Show the exact line to be added and where; append on approval, newest last. Check
for an existing similar lesson and merge instead of duplicating.

### 4. Enforce the budget

If `lessons.md` is over ~1.5 KB after the write: propose dedupe/generalize merges,
**promote** lessons that have become real conventions into the appropriate context
file (that's the goal — into `code-standards.md` as a rule card with a ✗/✓ pair,
never as a bare bullet), and drop lines about code that no longer exists — with
approval per change.

## Also handles

- **"Forget X" / "that lesson is wrong"** — find and remove or correct the line.
- **"Show my lessons / preferences"** — print the relevant file with line numbers.
- **Promotion requests** — move a lesson into a context file and delete it here.

## Rules

- One line per lesson; never paragraphs.
- Every write is shown to the user first — memory belongs to the user.
- Never store secrets or project-specific facts in the global preferences file.
