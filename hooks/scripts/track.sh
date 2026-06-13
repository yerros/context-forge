#!/usr/bin/env bash
# Stop hook — deterministic activity recorder, zero model tokens.
# If code changed (per git) without the tracker being updated, refresh
# context/.last-session.md with a timestamp and the changed-file list.
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

{
  printf '# Last session activity\n\n'
  printf 'Updated: %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf 'Changed files (uncommitted):\n\n'
  printf '%s\n' "$changed" | sed 's/^/- /'
  printf '\nReminder: record this work in context/progress-tracker.md if it is not already captured.\n'
} > context/.last-session.md

exit 0
