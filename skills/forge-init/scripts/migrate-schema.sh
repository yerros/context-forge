#!/usr/bin/env bash
# migrate-schema.sh — stepwise, idempotent migration of the context-file SCHEMA.
# (forge-migrate/migrate-to-forge.sh moves the folder; THIS script evolves the
# format of what's inside.)
#
#   migrate-schema.sh            # migrate to the current schema
#   migrate-schema.sh --dry-run  # show what would change, write nothing
#   migrate-schema.sh --auto     # SessionStart mode: apply AUTO-SAFE migrations
#                                # silently, never fail, never block a session
#
# One version number for the whole context dir — the files migrate together, so
# per-file tags would only add token cost and a new drift source. The marker is
# <context-dir>/.schema-version (a single integer; commit it with the rest).
#
#   pre-schema (no marker)  everything up to plugin 0.25.x
#   1                       marker introduced; layout otherwise identical
#
# AUTO-SAFE = additive-only: creates new files/markers, never rewrites existing
# content. Only such steps run under --auto (the SessionStart hook); a future
# content-rewriting migration will instead inject a one-line notice so the user
# runs the migration deliberately. Manual rules stay the same as
# migrate-to-forge.sh: idempotent, refuses ambiguity, never auto-commits.

set -eu

CURRENT_SCHEMA=1
AUTO_SAFE_STEPS=" 0:1 "   # space-delimited "from:to" pairs that may run unattended

dry=0; auto=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --auto)    auto=1 ;;
    *) printf 'migrate-schema: unknown option %s\n' "$a" >&2; exit 1 ;;
  esac
done

say() { [ "$auto" = 1 ] && return 0; printf '%s\n' "$*"; }
notice() { printf '%s\n' "$*"; }   # the one thing --auto may emit (hook-injected)
die() {
  # In auto mode nothing may fail or nag a session that isn't ready — forge-init
  # owns incomplete projects. Manual mode keeps loud, refusing behavior.
  [ "$auto" = 1 ] && exit 0
  printf 'migrate-schema: %s\n' "$*" >&2; exit 1
}
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
  if [ "$auto" = 1 ]; then
    case "$AUTO_SAFE_STEPS" in
      *" $v:$next "*) ;;   # additive-only step — safe unattended
      *)
        notice "[Context Forge] context schema is $v; schema $next needs a deliberate migration — run: migrate-schema.sh --dry-run, then migrate-schema.sh"
        exit 0
        ;;
    esac
  fi
  "migrate_${v}_to_${next}"
  v=$next
done

if [ "$dry" = 1 ]; then
  say "dry-run complete — nothing was written"
elif [ "$auto" = 1 ]; then
  notice "[Context Forge] context schema stamped: $CTX/.schema-version = $CURRENT_SCHEMA (auto, additive-only) — commit it with your context files."
else
  say "done — commit $marker together with your context files"
fi
