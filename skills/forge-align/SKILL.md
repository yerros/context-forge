---
name: forge-align
description: >
  This skill should be used to find and fix code-consistency drift between similar
  features in a Six-File Context Methodology project — phrases like "forge-align",
  "check code consistency", "these features are written differently", "the CRUD
  features are inconsistent", "unify the patterns", or "why does every feature look
  different". It maps feature families via the forge-aligner agent, reports
  divergences against the exemplar, registers missing patterns in patterns.md, and
  turns approved alignments into refactor units built with the normal discipline.
metadata:
  version: "0.19.0"
---

# forge-align

Fix the classic vibe-coding failure: five CRUD features, five dialects. Detection
is delegated; judgment and the fix pipeline live here. The prevention side (specs
that point at exemplars) lives in `forge-spec`/`forge-build`; this skill is the
detection-and-repair side.

## Argument

Text after the command scopes the check (e.g. `/forge-align the CRUD features` or
`/forge-align src/features`). No argument → whole-codebase family discovery.

## Steps

### 1. Detect (delegated)

Spawn the `forge-aligner` agent (sonnet-pinned, read-only) with the scope. It
discovers feature families, compares siblings against the registered pattern (or
the dominant member), and returns divergences by severity plus proposed
patterns.md entries. Its reading stays out of this session.

### 2. Judge with the user

Present the drift report. For each family, decide together: which pattern is
canonical (the aligner's recommendation is a default, not a verdict — the user may
prefer the minority version), which divergences are worth fixing, and which are
accepted as-is (record a one-line lesson for accepted ones so they stop being
flagged).

### 3. Register the patterns

Write the approved entries into `context/patterns.md` (create from
`${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/patterns.md` if absent):
pattern name, exemplar path, must-match bullets. Keep it within ~2 KB — pointers,
not essays. This is the prevention half: from now on `forge-architect` writes specs
that reference the exemplar and `forge-build` mimics it.

### 4. Fix through the methodology — not a grand refactor

For divergences the user wants fixed, generate **alignment units** via `forge-spec`
(one unit per family or per outlier, goal = "align X to pattern Y, zero behavior
change", Tests = existing suite stays green). They enter the build plan and get
built with `forge-build`'s full discipline. Never mass-edit files directly from
this skill.

## Rules

- Consistency serves the codebase, not aesthetics — behavior-changing "alignments"
  are out of scope here (that's a feature/fix, route accordingly).
- The user picks the canonical pattern; majority is evidence, not authority.
- Accepted divergences get a lesson line so they aren't re-flagged forever.
- patterns.md entries must anchor to a real exemplar file that exists.
