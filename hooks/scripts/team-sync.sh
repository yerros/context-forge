#!/usr/bin/env bash
# SessionStart hook — team knowledge sync, zero model tokens.
# Fetches origin and reports the lessons / decisions / patterns your teammates
# committed to the default branch since this machine last saw it. Prints a few
# lines to stdout (injected as session context) only when something is new;
# silent everywhere else (non-forge project, no remote, offline, first run).
#
# Watermark: ~/.context-forge/team-sync/<repo-id> holds the origin/<default>
# SHA at the last report — per machine, never written into the repo.
#
# Usage: team-sync.sh [--no-fetch]   (--no-fetch: tests / offline use)

set -u

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -f "$CTX/context-digest.md" ] || [ -f "$CTX/progress-tracker.md" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0

if [ "${1:-}" != "--no-fetch" ]; then
  # Bounded fetch: never hang a session start on a slow network.
  GIT_TERMINAL_PROMPT=0 git fetch --quiet origin >/dev/null 2>&1 &
  fpid=$!
  for _ in $(seq 1 16); do
    kill -0 "$fpid" 2>/dev/null || break
    sleep 0.5
  done
  kill "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
fi

# Default branch: origin/HEAD, else main, else master.
def=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
def=${def#origin/}
if [ -z "$def" ]; then
  for b in main master; do
    git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null 2>&1 && { def=$b; break; }
  done
fi
[ -n "$def" ] || exit 0
head=$(git rev-parse -q --verify "refs/remotes/origin/$def" 2>/dev/null) || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
mark_dir="$HOME/.context-forge/team-sync"
mark="$mark_dir/$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
mkdir -p "$mark_dir" 2>/dev/null || exit 0

if [ ! -f "$mark" ]; then
  # First run on this machine: set the watermark, report nothing.
  printf '%s\n' "$head" > "$mark"
  exit 0
fi
last=$(cat "$mark" 2>/dev/null)
[ "$last" = "$head" ] && exit 0
git cat-file -e "$last^{commit}" 2>/dev/null || { printf '%s\n' "$head" > "$mark"; exit 0; }

# Added lines only; skip blanks, headings, and diff metadata. Cap the noise.
added=$(git diff --no-color "$last" "$head" -- "$CTX/lessons.md" "$CTX/decisions.md" "$CTX/patterns.md" 2>/dev/null \
  | grep -E '^\+' | grep -vE '^\+\+\+ ' | cut -c2- \
  | grep -vE '^\s*$' | grep -vE '^#' | head -20)
commits=$(git rev-list --count "$last..$head" 2>/dev/null || echo 0)
behind=$(git rev-list --count "HEAD..$head" 2>/dev/null || echo 0)

printf '%s\n' "$head" > "$mark"
[ -n "$added" ] || exit 0

printf '%s\n' "[Context Forge] Team sync: origin/$def moved $commits commit(s) since your last session; new lessons/decisions/patterns from the team (already in $CTX/ once you pull; local branch is $behind commit(s) behind):"
printf '%s\n' "$added"
