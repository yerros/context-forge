#!/usr/bin/env bash
# Stop hook — deterministic activity recorder + budget guard, zero model tokens.
# If code changed (per git) without the tracker being updated, refresh
# context/.last-session.md with a timestamp, the changed-file list, and any
# context files that are over their soft token budget.
# Overwrites (never grows), writes nothing to stdout (never re-wakes the model).

set -u

[ -f context/progress-tracker.md ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Uncommitted changes, excluding the tracker and our own activity file.
changed=$(git status --porcelain -uall 2>/dev/null \
  | cut -c4- \
  | grep -vE '(^|/)context/progress-tracker\.md$' \
  | grep -vE '(^|/)context/\.last-session\.md$')

[ -z "$changed" ] && exit 0

# Soft budgets in bytes (canonical values: token-economy.md; tokens ≈ bytes/4).
# Output lines only for files that are OVER budget.
budget_report=""
check_budget() { # $1=file $2=budget_bytes $3=fix hint
  [ -f "$1" ] || return 0
  size=$(wc -c <"$1" | tr -d ' ')
  if [ "$size" -gt "$2" ]; then
    budget_report="${budget_report}- $1 is ${size} bytes (~$((size / 4)) tokens), over its ~$(($2 / 1024)) KB budget — $3
"
  fi
}
check_budget "context/progress-tracker.md" 6144  "rotate old entries into context/progress-archive.md (or run forge-compact)"
check_budget "context/context-digest.md"   2560  "regenerate a tighter digest (or run forge-compact)"
for f in architecture ui-context code-standards project-overview ai-workflow-rules; do
  check_budget "context/$f.md" 10240 "tighten prose or split detail into an on-demand reference file (or run forge-compact)"
done

{
  printf '# Last session activity\n\n'
  printf 'Updated: %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf 'Changed files (uncommitted):\n\n'
  printf '%s\n' "$changed" | sed 's/^/- /'
  printf '\nReminder: record this work in context/progress-tracker.md if it is not already captured.\n'
  if [ -n "$budget_report" ]; then
    printf '\nContext files over their token budget:\n\n'
    printf '%s' "$budget_report"
  fi
} > context/.last-session.md

exit 0
