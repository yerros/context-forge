---
name: forge-init
description: >
  This skill should be used when the user wants to set up the Six-File Context
  Methodology in a project — phrases like "init context", "set up context files",
  "scaffold the six files", "forge-init", "create CLAUDE.md and context docs",
  "analyze this project and fill the context templates", or "bootstrap AI context
  for this codebase". Works for both new (greenfield) projects via a planning
  conversation and existing (brownfield) projects by analyzing the codebase and
  filling the templates from real evidence, then confirming with the user before
  writing. Also recognizes projects that already have the context files (manual or prior
  runs) and reconciles gaps without overwriting.
metadata:
  version: "0.2.0"
---

# forge-init

Set up the Six-File Context System in the user's project: the `context/` folder
with six markdown files plus an agent entry point (`CLAUDE.md` or `AGENTS.md`).
The blank templates are bundled at `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/`.

The guiding principle of this methodology: **the user is the architect, the AI is
the implementation engine.** These files capture the architectural thinking so the
agent stays consistent across sessions and never guesses.

## Step 0: Read the state — ALWAYS run this first

Never assume the project is empty. Run the deterministic state detector from the project
root and branch on its `verdict`. This is read-only and never writes anything:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/detect.sh"
```

The report gives a `verdict` plus the facts behind it (which of the six files exist, how
many unfilled `[placeholder]` markers remain, entry point, decisions/specs presence,
whether a codebase was detected). Act on the verdict — do not re-derive these facts by
hand:

- **`SETUP`** — no `context/` and no files. Fresh install → go to the Mode + Profile step.
- **`ADOPT`** — all six files present and substantially filled (the project already uses
  the methodology). → go to the **Adopt & reconcile** flow. **Do not regenerate.**
- **`REPAIR`** — `context/` exists but is incomplete or still mostly blank template. →
  go to the **Adopt & reconcile** flow and fill the gaps.

### Mode + Profile (only when verdict is SETUP)

Determine **greenfield** (empty/near-empty) vs **brownfield** (the report's
`codebase_detected: yes`). Then pick a stack profile: read
`${CLAUDE_PLUGIN_ROOT}/skills/forge-init/references/stack-profiles.md`, detect the
project type (web frontend, backend/API, mobile, CLI/library, data/ML), and apply the
matching profile — it says which files matter and when to drop or repurpose
`ui-context.md`. Tell the user which profile you're applying and why. Keep the entry
point's file list in sync with the files you actually create. Then follow the Greenfield
or Brownfield flow below.

## Adopt & reconcile flow (verdict ADOPT or REPAIR)

The project already has context files with the standard structure. The job is to
recognize them and heal gaps — **never clobber existing content.** This flow is
idempotent: running it on a healthy project changes nothing.

### Rules (non-negotiable)

- **Never overwrite a file that contains real content.** Only create files that are
  missing, and only edit a present file to replace remaining `[placeholder]` markers or
  to fix a clear inconsistency the user approves.
- **Confirm before every write.** Show the plan, get a yes.
- Preserve the user's wording, ordering, and any extra sections they added.

### Steps

1. **Report what exists.** Summarize the detector output for the user in plain language:
   which files are present, which are missing, how filled each is, and whether the entry
   point, `decisions.md`, and `specs/` exist.

2. **Read the present files** in order so you adopt the real project context (stack,
   invariants, current phase). From here on, honor those invariants and standards.

3. **Fill only the gaps** (propose, then write on approval):
   - **Missing files** — create from the bundled templates and fill them using evidence
     from the codebase (brownfield) or a short conversation (greenfield). Match the stack
     profile of the existing setup.
   - **Remaining placeholders** in present files — offer to fill them from real evidence;
     leave anything the user wants to keep as-is.
   - **Entry point** — if missing, create `CLAUDE.md`/`AGENTS.md` from the template. If
     present but `entry_links_context: no`, merge in the "Application Building Context"
     section without disturbing the rest.
   - **Optional pieces** — offer (don't force) to add `context/specs/` + a build plan and
     `context/decisions.md` if absent.

4. **Offer a drift check.** For ADOPT projects with a codebase, recommend running
   `forge-audit` to confirm the existing docs still match the code. Don't auto-rewrite
   accurate content.

5. **Update the tracker** only to reflect this reconcile pass, then stop. Do not start
   building — hand off to `forge-resume` or `forge-build`.

## Brownfield flow — analyze, draft, confirm, then write

This is the default for existing projects. **Never write the files until the user
confirms the draft.**

### 1. Analyze the codebase from evidence (do not guess)

Gather real signals before writing anything:

- **Stack & dependencies**: read `package.json` / `requirements.txt` / `go.mod` /
  `Cargo.toml` / lockfiles. Identify framework, language, UI lib, auth, database,
  ORM, test runner, build tooling.
- **Structure & boundaries**: map the top-level folders and what each owns
  (`find . -maxdepth 3 -type d -not -path '*/node_modules/*' -not -path '*/.git/*'`).
- **Code conventions**: open 3–6 representative source files. Note TypeScript
  strictness, component patterns, API route structure, naming, import style.
- **Styling / UI**: look for a design token file, Tailwind config, theme, or CSS
  variables to seed `ui-context.md`.
- **Existing docs**: read any `README.md`, `CONTRIBUTING.md`, `.cursorrules`, or
  existing `CLAUDE.md`/`AGENTS.md` and reuse what is accurate.
- **Build/verify command**: find the actual build/test/lint scripts.

Cite the evidence in the draft (e.g. "Detected Next.js 15 + TypeScript from
package.json"). Where the code does not reveal intent (product goals, what's
out of scope, success criteria), mark it `[NEEDS INPUT: ...]` rather than inventing it.

### 2. Present a draft summary for confirmation

Before writing files, show the user a concise summary of what each of the six files
will contain, grouped by file. Highlight:

- What was inferred from the code (with the evidence).
- Every `[NEEDS INPUT: ...]` gap that needs the user's product/scope knowledge.

Ask the user to confirm or correct. Resolve the `[NEEDS INPUT]` items through a short
conversation. Do not proceed to writing until the user approves.

### 3. Write the files

Once approved, scaffold and fill (see "Writing the files" below).

## Greenfield flow — the conversation before the code

For new projects, run the planning conversation first. The conversation IS the work.

Ask the user, one topic at a time, pushing back when answers are vague:

- What does this application do in one sentence? Who is the primary user?
- Core user flow from sign-up to core value, step by step.
- The three most important features for v1. What is explicitly **out of scope**?
- Full tech stack and the reason for each choice.
- Where data lives (database / file storage / cache). How auth and ownership work.
- System boundaries — which folder owns what.
- The rules the codebase must never violate (invariants).
- Visual language: colors, typography, component library.

Keep going until the user can answer every question without hesitation, then write
the files from their answers.

## Writing the files

1. Copy the bundled templates into the project:
   - Create a `context/` folder at the project root.
   - Copy the six files from `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/`
     into it: `project-overview.md`, `architecture.md`, `ui-context.md`,
     `code-standards.md`, `ai-workflow-rules.md`, `progress-tracker.md`.
2. Fill each file in, replacing every `[bracketed placeholder]` with concrete,
   specific content. Follow the per-file quality bars below.
3. Create the entry point at the project root. Use the bundled template at
   `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/CLAUDE.md` (for Claude Code /
   Cowork) or `AGENTS.md` (for Codex / Copilot / generic). If one already exists,
   merge the "Application Building Context" section in rather than clobbering it.
4. Leave `progress-tracker.md` mostly empty for greenfield (just Current Phase +
   Next Up). For brownfield, seed "Completed" with what already exists and "Current
   Phase" with the real state.

### Per-file quality bars

- **project-overview.md** — Goals are measurable, not aspirational. User flow has no
  gaps. The out-of-scope list is explicit. Success criteria are verifiable ("a
  signed-in user can create and open a project"), not "looks good".
- **architecture.md** — Complete stack table with a role for every technology. System
  boundaries name exact folders. Storage model is unambiguous. **Invariants are stated
  as hard rules (at least four)**, e.g. "auth is enforced at every mutation boundary".
- **ui-context.md** — Every color is a named token, never a raw hex used ad hoc.
  Layout patterns describe the real app structure. For brownfield, extract from the
  existing theme/tokens.
- **code-standards.md** — Concrete conventions for TypeScript/language, framework
  patterns, API structure, styling, file organization. For brownfield, reflect the
  patterns actually in the code.
- **ai-workflow-rules.md** — Written as imperative rules, not suggestions. Include the
  protected files (e.g. generated UI components) and the real build/verify command.
- **progress-tracker.md** — The living file. Note that it must be updated after every
  meaningful change.

## After completion

Tell the user the files are in place and explain the loop: the agent reads the entry
point at the start of every session, and `progress-tracker.md` is updated after each
unit. Suggest running `forge-spec` next to break the build into spec'd units.
