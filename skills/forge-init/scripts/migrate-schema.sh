#!/usr/bin/env bash
# migrate-schema.sh — stepwise, idempotent migration of the context-file SCHEMA.
# (forge-migrate/migrate-to-forge.sh moves the folder; THIS script evolves the
# format of what's inside.)
#
#   migrate-schema.sh            # migrate to the current schema
#   migrate-schema.sh --dry-run  # show what would change, write nothing
#
# One version number for the whole context dir — the files migrate together, so
# per-file tags would only add token cost and a new drift source. The marker is
# <context-dir>/.schema-version (a single integer; commit it with the rest).
#
#   pre-schema (no marker)  everything up to plugin 0.25.x
#   1                       marker introduced; layout otherwise identical
#
# Rules (same discipline as migrate-to-forge.sh): idempotent, refuses when the
# project state is ambiguous, never auto-commits.

set -eu

CURRENT_SCHEMA=1

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

say() { printf '%s\n' "$*"; }
die() { printf 'migrate-schema: %s\n' "$*" >&2; exit 1; }
act() { # $1 = description; rest = command (skipped under --dry-run)
  desc=$1; shift
  if [ "$dry" = 1 ]; then
    say "would: $desc"
  else
    "$@"
    say "did:   $desc"
  fi
}

# --- context dir resolution (same rule as detect.sh) ---
if [ -f ".forge/progress-tracker.md" ] || [ -f ".forge/project-overview.md" ]; then
  CTX=".forge"
elif [ -f "context/progress-tracker.md" ] || [ -f "context/project-overview.md" ]; then
  CTX="context"
else
  die "no Context Forge files found (run forge-init first)"
fi
marker="$CTX/.schema-version"

# --- current version ---
if [ -f "$marker" ]; then
  from=$(tr -cd '0-9' < "$marker")
  [ -n "$from" ] || die "$marker exists but holds no number — fix or delete it, then re-run"
else
  from=0   # pre-schema
fi

if [ "$from" -gt "$CURRENT_SCHEMA" ]; then
  die "context dir is schema $from but this plugin only knows up to $CURRENT_SCHEMA — update the plugin instead"
fi
if [ "$from" -eq "$CURRENT_SCHEMA" ]; then
  say "schema $from — already current, nothing to do"
  exit 0
fi

say "migrating $CTX/: schema $from -> $CURRENT_SCHEMA$( [ "$dry" = 1 ] && printf ' (dry-run)' )"

# --- migrations, one function per step; each ends by stamping its target ---

migrate_0_to_1() {
  # Schema 1 = the 0.25.x layout plus the marker itself. Sanity-check the core
  # files so we never stamp a half-set-up project as "current".
  missing=""
  for f in project-overview architecture code-standards ai-workflow-rules progress-tracker; do
    [ -f "$CTX/$f.md" ] || missing="$missing $f.md"
  done
  [ -z "$missing" ] || die "core files missing:$missing — run forge-init (REPAIR) before migrating"
  act "stamp $marker = 1" bash -c "printf '1\n' > '$marker'"
}

v=$from
while [ "$v" -lt "$CURRENT_SCHEMA" ]; do
  next=$((v + 1))
  "migrate_${v}_to_${next}"
  v=$next
done

if [ "$dry" = 1 ]; then
  say "dry-run complete — nothing was written"
else
  say "done — commit $marker together with your context files"
fi
