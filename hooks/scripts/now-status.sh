#!/usr/bin/env bash
# now-status.sh — realtime "what is Claude Code doing right now" recorder.
# Same contract as skill-status.sh / agent-status.sh: deterministic, zero
# model tokens, writes NOTHING to stdout, always exits 0, never blocks.
#
# Usage (from hooks.json):
#   now-status.sh tool    # PreToolUse, matcher "" — record tool + target
#   now-status.sh clear   # Stop — the turn ended, session is idle
#
# State files consumed by the forge-office dashboard:
#   ~/.claude/forge-status/<session_id>.now     current: "<epoch>\t<tool>\t<detail>"
#   ~/.claude/forge-status/<session_id>.stream  rolling log of the same lines —
#     the dashboard's realtime work timeline. Appended per tool call, trimmed
#     to the last 80 entries once it passes 200 (O(1) per call otherwise).

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

line="$(date +%s)	$tool	$detail"
printf '%s\n' "$line" > "$state" 2>/dev/null
stream="$dir/$sid.stream"
printf '%s\n' "$line" >> "$stream" 2>/dev/null
# rotation keeps the stream bounded (wc on a ≤200-line file is ~free)
if [ "$(wc -l < "$stream" 2>/dev/null || echo 0)" -gt 200 ]; then
  tail -n 80 "$stream" > "$stream.t.$$" 2>/dev/null && mv "$stream.t.$$" "$stream" 2>/dev/null
fi
exit 0
