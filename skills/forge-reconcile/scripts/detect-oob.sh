#!/usr/bin/env bash
# detect-oob.sh — deterministic detector of out-of-band (OOB) work: commits made
# outside the Context Forge process since the methodology was adopted.
# Read-only: never writes anything. Zero model tokens when the repo is clean.
#
# Modes:
#   detect-oob.sh          line-based report parsed by the forge-reconcile skill
#   detect-oob.sh --hook   compact SessionStart warning; prints NOTHING when clean
#
# A commit is IN-BAND (part of the process) when ANY of:
#   - its message references a unit or spec (e.g. "Implements unit NN",
#     context/specs/ or .forge/specs/ paths, or "forge-reconcile")
#   - its diff touches files under the context dir (tracker/spec bookkeeping)
#   - it is a merge commit (merges of in-band branches)
# A commit is EXCLUDED (already handled) when:
#   - a later commit lists its short sha on a "Reconciles:" line — the marker
#     written by forge-reconcile's bookkeeping commit
#   - its short sha appears in $CTX/.reconcile-ignore (user chose to dismiss)
# Everything else newer than the ADOPTION EPOCH (the commit that first added the
# tracker) is OOB. Pre-adoption history is never flagged.

set -u

MODE=report
[ "${1:-}" = "--hook" ] && MODE=hook

# Scan window cap — keeps the hook cheap on huge histories.
WINDOW="${FORGE_RECONCILE_WINDOW:-200}"

# --- context dir resolution (same rule as forge-init/scripts/detect.sh) ---
if [ -f ".forge/progress-tracker.md" ] || [ -f ".forge/project-overview.md" ]; then
  CTX=".forge"
else
  CTX="context"
fi
CTX_RE=$(printf '%s' "$CTX" | sed 's/\./\\./g')

say() { printf '%s\n' "$1"; }

bail() { # $1 = verdict; silent no-op in hook mode
  if [ "$MODE" = "report" ]; then
    say "context_dir: $CTX"
    say "verdict: $1"
  fi
  exit 0
}

[ -f "$CTX/progress-tracker.md" ] || bail NO_CONTEXT
command -v git >/dev/null 2>&1 || bail NO_GIT
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || bail NO_GIT

# --- adoption epoch: the commit that first added the tracker ---
epoch=$(git log --diff-filter=A --format=%H -- "$CTX/progress-tracker.md" 2>/dev/null | tail -1)
[ -n "$epoch" ] || bail NO_EPOCH   # tracker never committed -> no reliable baseline

range="$epoch..HEAD"

# --- exclusion set: reconciled + ignored short shas (one space-separated blob) ---
handled=$(git log -n "$WINDOW" "$range" --format=%b 2>/dev/null \
  | grep -iE '^Reconciles?:' \
  | tr -s ' :' '\n' \
  | grep -E '^[0-9a-f]{7,40}$' \
  | cut -c1-7 | tr '\n' ' ')
if [ -f "$CTX/.reconcile-ignore" ]; then
  ignored=$(grep -oE '^[0-9a-f]{7,40}' "$CTX/.reconcile-ignore" 2>/dev/null \
    | cut -c1-7 | tr '\n' ' ')
  handled="$handled $ignored"
fi

# --- classification ---
oob_list=""
count=0
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  short=$(printf '%s' "$sha" | cut -c1-7)
  case " $handled " in *" $short "*) continue ;; esac

  msg=$(git log -1 --format='%s%n%b' "$sha" 2>/dev/null)
  if printf '%s' "$msg" | grep -qiE "Implements unit [0-9]+|forge-reconcile|Reconciles?:|chore\(forge\)|(context|\.forge)/specs/"; then
    continue
  fi
  if git show --format= --name-only "$sha" 2>/dev/null | grep -qE "^$CTX_RE/"; then
    continue
  fi

  cdate=$(git log -1 --format=%ad --date=short "$sha")
  subject=$(git log -1 --format=%s "$sha")
  nfiles=$(git show --format= --name-only "$sha" 2>/dev/null | grep -c .)
  oob_list="${oob_list}${short}|${cdate}|${subject}|${nfiles}
"
  count=$((count + 1))
done < <(git log -n "$WINDOW" --no-merges --format=%H "$range" 2>/dev/null)

# --- output ---
if [ "$MODE" = "report" ]; then
  say "context_dir: $CTX"
  say "epoch: $(printf '%s' "$epoch" | cut -c1-7)"
  dirty=$(git status --porcelain -uall 2>/dev/null | cut -c4- \
    | grep -vE "(^|/)$CTX_RE/" || true)
  if [ -n "$dirty" ]; then
    say "dirty_tree: yes"
    printf '%s\n' "$dirty" | sed 's/^/dirty: /'
  else
    say "dirty_tree: no"
  fi
  if [ "$count" -eq 0 ]; then
    say "verdict: CLEAN"
  else
    say "verdict: OOB"
    say "oob_count: $count"
    # oob: <short_sha>|<date>|<subject>|<n_files>
    printf '%s' "$oob_list" | sed 's/^/oob: /'
  fi
else
  [ "$count" -eq 0 ] && exit 0
  more=""
  [ "$count" -gt 3 ] && more=" (+$((count - 3)) more)"
  printf '[Context Forge] %s commit(s) made outside the forge process — work not captured in the tracker/specs%s:\n' "$count" "$more"
  printf '%s' "$oob_list" | head -3 | awk -F'|' '{printf "  %s  %s (%s)\n", $1, $3, $2}'
  printf 'Run /forge-reconcile to analyze and adopt them (retro-spec + tracker), or list shas in %s/.reconcile-ignore to dismiss.\n' "$CTX"
fi
exit 0
