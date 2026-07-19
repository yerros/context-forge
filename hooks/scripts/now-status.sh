#!/usr/bin/env bash
# now-status.sh — realtime "what is Claude Code doing right now" recorder.
# Same contract as skill-status.sh / agent-status.sh: deterministic, zero
# model tokens, writes NOTHING to stdout, always exits 0, never blocks.
#
# Usage (from hooks.json):
#   now-status.sh tool    # PreToolUse, matcher "" — record tool + target
#   now-status.sh clear   # Stop — the turn ended, session is idle
#
# State file: ~/.claude/forge-status/<session_id>.now
#   single line: "<epoch>\t<tool>\t<detail>"
# Consumed by the forge-office dashboard (speech bubbles / live feed).

set -u
mode=${1:-tool}
input=$(cat)

dir="${HOME}/.claude/forge-status"
mkdir -p "$dir" 2>/dev/null || exit 0

jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

sid=$(jfield "session_id")
[ -z "$sid" ] && exit 0
case "$sid" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
state="$dir/$sid.now"

if [ "$mode" = "clear" ]; then
  rm -f "$state" 2>/dev/null
  exit 0
fi

tool=$(jfield "tool_name")
[ -z "$tool" ] && exit 0
case "$tool" in *[!A-Za-z0-9._-]*) exit 0 ;; esac

# Best-effort human detail from tool_input — first matching key wins.
detail=""
for key in file_path notebook_path path pattern skill subagent_type url command description prompt query; do
  v=$(jfield "$key")
  if [ -n "$v" ]; then
    detail=$v
    break
  fi
done
# Shorten paths to their tail and cap length; strip tabs/newlines.
detail=$(printf '%s' "$detail" | tr '\t\n' '  ')
case "$detail" in
  */*/*/*) detail="…/${detail##*/}" ;;
esac
detail=$(printf '%.90s' "$detail")

printf '%s\t%s\t%s\n' "$(date +%s)" "$tool" "$detail" > "$state" 2>/dev/null
exit 0
