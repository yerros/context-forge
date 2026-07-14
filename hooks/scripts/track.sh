#!/usr/bin/env bash
# Stop hook — deterministic activity recorder + budget guard, zero model tokens.
# If code changed (per git) without the tracker being updated, refresh
# context/.last-session.md with a timestamp, the changed-file list, and any
# context files that are over their soft token budget.
# Overwrites (never grows), writes nothing to stdout (never re-wakes the model).

set -u

# Context dir resolution (same rule as detect.sh).
CTX=context
[ -f .forge/progress-tracker.md ] && CTX=.forge

[ -f "$CTX/progress-tracker.md" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Uncommitted changes, excluding the tracker and our own activity file.
changed=$(git status --porcelain -uall 2>/dev/null \
  | cut -c4- \
  | grep -vE "(^|/)$CTX/progress-tracker\.md$" \
  | grep -vE "(^|/)$CTX/\.last-session\.md$")

[ -z "$changed" ] && exit 0

# Soft budgets in bytes (canonical values: token-economy.md; tokens ≈ bytes/4).
# Output lines only for files that are OVER budget.
budget_report=""
check_budget() { # $1=file $2=budget_bytes $3=budget label $4=fix hint
  [ -f "$1" ] || return 0
  size=$(wc -c <"$1" | tr -d ' ')
  if [ "$size" -gt "$2" ]; then
    budget_report="${budget_report}- $1 is ${size} bytes (~$((size / 4)) tokens), over its ~$3 budget — $4
"
  fi
}
check_budget "$CTX/progress-tracker.md" 6144  "6 KB"   "rotate old entries into $CTX/progress-archive.md (or run forge-compact)"
check_budget "$CTX/context-digest.md"   2560  "2.5 KB" "regenerate a tighter digest (or run forge-compact)"
check_budget "$CTX/lessons.md"          1536  "1.5 KB" "merge/promote lessons via forge-lesson (or run forge-compact)"
check_budget "$CTX/ideas.md"            1536  "1.5 KB" "drop dead ideas / promote ripe ones via forge-brainstorm or forge-compact"
for f in architecture ui-context code-standards project-overview ai-workflow-rules; do
  check_budget "$CTX/$f.md" 10240 "10 KB" "tighten prose or split detail into an on-demand reference file (or run forge-compact)"
done

{
  printf '# Last session activity\n\n'
  printf 'Updated: %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf 'Changed files (uncommitted):\n\n'
  printf '%s\n' "$changed" | sed 's/^/- /'
  printf '\nReminder: record this work in %s/progress-tracker.md if it is not already captured.\n' "$CTX"
  if [ -n "$budget_report" ]; then
    printf '\nContext files over their token budget:\n\n'
    printf '%s' "$budget_report"
  fi
} > "$CTX/.last-session.md"

exit 0
