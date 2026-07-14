#!/usr/bin/env bash
# migrate-to-forge.sh — move a project's context/ directory to .forge/, safely.
# Run from the project root. Deterministic, idempotent, refuses unsafe states.
#
#   bash migrate-to-forge.sh           # migrate
#   bash migrate-to-forge.sh --dry-run # show what would happen, change nothing
#
# What it does:
#   1. Verifies context/ holds the methodology's files (never moves a framework's
#      context/ folder) and that .forge/ doesn't already hold them.
#   2. Moves the directory — `git mv` when inside a git repo (history preserved),
#      plain `mv` otherwise.
#   3. Rewrites context/ -> .forge/ paths in CLAUDE.md and AGENTS.md.
#   4. Guards .gitignore: if .forge/ would be ignored, appends `!.forge/`.
# It does NOT commit — review the staged changes and commit yourself.

set -eu

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say()  { printf '%s\n' "$*"; }
die()  { printf 'migrate-to-forge: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# --- 1. Safety checks -------------------------------------------------------
[ -d context ] || die "no context/ directory here — nothing to migrate (run from the project root)."

if ! [ -f context/progress-tracker.md ] && ! [ -f context/project-overview.md ]; then
  die "context/ exists but does not contain the methodology's files (progress-tracker.md / project-overview.md). Refusing to move what looks like your framework's context folder."
fi

if [ -f .forge/progress-tracker.md ] || [ -f .forge/project-overview.md ]; then
  die ".forge/ already contains methodology files — resolve that first (nothing was changed)."
fi

in_git=0
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git=1
fi

# --- 2. Move the directory --------------------------------------------------
if [ "$in_git" = 1 ]; then
  say "Moving context/ -> .forge/ (git mv, history preserved)"
  run git mv context .forge
else
  say "Moving context/ -> .forge/ (plain mv — not a git repo; consider git init first)"
  run mv context .forge
fi

# --- 3. Rewrite entry-point paths -------------------------------------------
for entry in CLAUDE.md AGENTS.md; do
  if [ -f "$entry" ] && grep -q 'context/' "$entry"; then
    say "Rewriting context/ -> .forge/ paths in $entry"
    if [ "$DRY" = 1 ]; then
      say "[dry-run] sed -i.bak 's|context/|.forge/|g' $entry"
    else
      sed -i.bak 's|context/|.forge/|g' "$entry" && rm -f "$entry.bak"
      [ "$in_git" = 1 ] && git add "$entry"
    fi
  fi
done

# --- 4. Gitignore guard ------------------------------------------------------
# Probe with a hypothetical NEW path: already-tracked files pass check-ignore
# even when ignored patterns match, but future files (progress-archive.md,
# .last-session.md, new specs) would silently not be committed.
if [ "$in_git" = 1 ]; then
  probe=".forge/zz-new-file-probe.md"
  if [ "$DRY" = 1 ]; then
    if git check-ignore -q "$probe" 2>/dev/null; then
      say "[dry-run] new files in .forge/ would be ignored -> would append '!.forge/' to .gitignore"
    else
      say "[dry-run] .gitignore OK — .forge/ is not ignored"
    fi
  else
    if git check-ignore -q "$probe" 2>/dev/null; then
      say "WARNING: new files in .forge/ would be ignored by .gitignore — appending '!.forge/' so the project's memory stays committed"
      printf '\n# context-forge: the context dir is project memory and must stay committed\n!.forge/\n' >> .gitignore
      git add .gitignore
      git check-ignore -q "$probe" 2>/dev/null \
        && say "WARNING: .forge/ is STILL ignored (a later rule overrides '!.forge/'). Fix .gitignore manually." \
        || say ".gitignore fixed — new files in .forge/ will be tracked."
    fi
  fi
fi

say ""
say "Done. Review with 'git status' and commit (e.g. chore: move context dir to .forge/)."
say "Detection is automatic from now on — skills and hooks will use .forge/."
