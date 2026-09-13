#!/usr/bin/env bash
# lesson-candidates.sh — UserPromptSubmit: catch corrections as lesson candidates.
#
# A correction ("no, don't retry on 4xx, only on 5xx") is the raw material of
# lessons.md, but it is only captured when someone remembers /forge-lesson.
# This hook applies a coarse, language-agnostic shape test to every prompt:
#   starts with a negation/correction cue (en/id), has a clause separator,
#   15–500 characters, contains letters, is not a question
# and appends hits to <ctx>/.lesson-candidates.md (deduped). Nothing is promoted
# automatically: /forge-lesson reads the file, the Stop hook counts it. The
# file is local and disposable. Writes nothing to stdout. Always exits 0.

set -u
input=$(cat 2>/dev/null || true)

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -f "$CTX/progress-tracker.md" ] || exit 0

prompt=$(printf '%s' "$input" \
  | grep -oE '"prompt"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' \
  | head -1 \
  | sed -E 's/^"prompt"[[:space:]]*:[[:space:]]*"(.*)"$/\1/; s/\\n/ /g; s/\\"/"/g; s/\\\\/\\/g')
[ -z "$prompt" ] && exit 0
case "$prompt" in \<*) exit 0 ;; esac            # system/tool envelopes, slash-command expansions
case "$prompt" in /*) exit 0 ;; esac             # slash commands

len=${#prompt}
[ "$len" -ge 15 ] && [ "$len" -le 500 ] || exit 0
case "$prompt" in *\?*) exit 0 ;; esac
printf '%s' "$prompt" | grep -q '[[:alpha:]]' || exit 0
printf '%s' "$prompt" | grep -q '[,;:]' || exit 0
head=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | cut -c1-12)
printf '%s' "$head" | grep -qE "^(no[,. ]|no\b|nope|don'?t|do not|not |never|stop |wrong|instead|actually|jangan|bukan|salah|tidak|jgn |ganti|harusnya|seharusnya|mestinya|bukannya)" || exit 0

f="$CTX/.lesson-candidates.md"
[ -f "$f" ] || printf '# Lesson candidates (auto-captured corrections — review with /forge-lesson)\n\n' > "$f"
line="- $(date '+%Y-%m-%d') $prompt"
grep -qxF -- "$line" "$f" 2>/dev/null && exit 0
grep -qF -- " $prompt" "$f" 2>/dev/null && exit 0
printf '%s\n' "$line" >> "$f"
exit 0
