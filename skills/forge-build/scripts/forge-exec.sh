#!/usr/bin/env bash
# forge-exec.sh — run a long-output command, keep the log out of the conversation.
#
#   forge-exec.sh [-n LINES] [-g PATTERN] "<command>"
#
# Runs <command> through bash, writes the full combined output to
# <ctx>/.runs/<timestamp>-<slug>.log, and prints only: the exit code, the log
# path with its size, and the last LINES lines (default 40) — or, with -g, the
# lines matching PATTERN (grep -E, case-insensitive) instead of the tail.
# The model then greps the log for specifics instead of paying for all of it.
# Logs older than 7 days are pruned. Exit status = the command's exit status.

set -u
lines=40 pattern=""
while getopts "n:g:" opt; do
  case "$opt" in
    n) lines=$OPTARG ;;
    g) pattern=$OPTARG ;;
    *) echo "usage: forge-exec.sh [-n LINES] [-g PATTERN] \"<command>\"" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
cmd=${1:-}
[ -z "$cmd" ] && { echo "usage: forge-exec.sh [-n LINES] [-g PATTERN] \"<command>\"" >&2; exit 2; }

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -d "$CTX" ] || CTX=.
runs="$CTX/.runs"
mkdir -p "$runs" 2>/dev/null || runs=$(mktemp -d)
find "$runs" -name '*.log' -type f -mtime +7 -delete 2>/dev/null

slug=$(printf '%s' "$cmd" | tr -cs '[:alnum:]' '-' | cut -c1-40 | sed 's/^-//;s/-$//')
log="$runs/$(date '+%Y%m%d-%H%M%S')-${slug:-cmd}.log"

bash -c "$cmd" > "$log" 2>&1
rc=$?

n=$(wc -l < "$log" | tr -d ' '); b=$(wc -c < "$log" | tr -d ' ')
printf 'exit %s — full log: %s (%s lines, %s bytes)\n' "$rc" "$log" "$n" "$b"
if [ -n "$pattern" ]; then
  printf -- '--- lines matching /%s/i (max %s) ---\n' "$pattern" "$lines"
  grep -inE -- "$pattern" "$log" | head -n "$lines"
else
  printf -- '--- last %s lines ---\n' "$lines"
  tail -n "$lines" "$log"
fi
exit "$rc"
