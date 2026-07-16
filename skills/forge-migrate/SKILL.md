---
name: forge-migrate
description: >
  This skill should be used to move a project's context directory from context/ to
  .forge/ — phrases like "forge-migrate", "migrate to .forge", "move the context
  dir to .forge", "move my context dir", "hide the context folder", or "my
  framework needs the context folder". It previews the migration, confirms, runs the bundled script
  (git mv with history, entry-point path rewrite, .gitignore guard), and offers the
  commit.
metadata:
  version: "0.24.0"
---

# forge-migrate

One-command migration of the context directory `context/` → `.forge/`, wrapping the
bundled script so the user never has to locate or run it by hand.

## Argument

No argument needed. `--dry-run` semantics are built into the flow below; text after
the command is treated as intent confirmation context only.

## Steps

### 1. Preview (always first)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/migrate-to-forge.sh" --dry-run
```

Show the user what would happen. The script refuses unsafe states on its own
(a framework's `context/` folder without the methodology files, or `.forge/`
already populated) — if it refuses, relay the reason and stop; do not work around
it.

### 2. Confirm, then run

On the user's yes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/migrate-to-forge.sh"
```

The script does everything atomically-enough: `git mv` (history preserved),
`context/` → `.forge/` path rewrite in `CLAUDE.md`/`AGENTS.md`, and the
`.gitignore` guard (hypothetical-new-file probe; appends `!.forge/` when needed —
relay its WARNING if a later rule still overrides).

### 3. Verify and close

Run the detector and confirm `context_dir_path: .forge`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-init/scripts/detect.sh"
```

Then show `git status --short` and offer to commit:
`chore: move context dir to .forge/`. Remind the user that detection is automatic
from now on — every skill, hook, and agent will use `.forge/`.

## Rules

- Never migrate without the preview + explicit yes — this moves the project's
  memory.
- Never bypass the script's refusals.
- One direction only (`context/` → `.forge/`). Moving back is a manual
  `git mv .forge context` plus reverting the entry-point paths — say so if asked.
