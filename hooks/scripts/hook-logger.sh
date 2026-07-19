#!/usr/bin/env bash
# hook-logger.sh — diagnostic recorder for Claude Code hook events.
#
# PURPOSE: the plugin's agent detection infers subagent lifecycles from hook
# side-effects. When detection misbehaves, guessing is worthless — this logger
# records the GROUND TRUTH: every hook event, its raw payload (truncated), and
# a snapshot of every .agents state file at that instant. One real multi-agent
# run produces a complete trace to design fixes from facts.
#
# OPT-IN (off by default; payloads may contain prompt text):
#   enable : mkdir -p ~/.claude/forge-debug && touch ~/.claude/forge-debug/enabled
#   disable: rm ~/.claude/forge-debug/enabled
#   report : bash hook-logger.sh report          # summary + recent timeline
#   raw    : ~/.claude/forge-debug/hooks.ndjson  # one JSON object per line
#
# Contract: writes NOTHING to stdout in hook mode (hook stdout is injected as
# model context), always exits 0, ~1 file-stat when disabled.
#
# Log line fields:
#   ts / epoch   wall time of the event
#   event        hook name as registered (pre / post / subagent-stop / stop /
#                user-prompt / session-start / session-end)
#   sid          session_id from the payload
#   tool         tool_name from the payload ("" for lifecycle events)
#   agent        raw subagent_type (unstripped, "" if absent)
#   bg           "1" if tool_input contains run_in_background:true
#   states       snapshot of EVERY ~/.claude/forge-status/*.agents file
#                ("<sid>=<line>,<line>;...") — catches cross-session writes
#   payload      first 4000 bytes of the raw hook JSON (escaped)

set -u
dir="${HOME}/.claude/forge-debug"
log="$dir/hooks.ndjson"
status_dir="${HOME}/.claude/forge-status"

# ---------------------------------------------------------------- report ----
if [ "${1:-}" = "report" ]; then
  if [ ! -s "$log" ]; then echo "hook-logger: no log at $log (enable + run a session first)"; exit 0; fi
  echo "== hook-logger report — $(wc -l < "$log" | tr -d ' ') events =="
  echo
  echo "-- events by type/tool --"
  sed -n 's/.*"event":"\([^"]*\)".*"tool":"\([^"]*\)".*/\1 \2/p' "$log" | sort | uniq -c | sort -rn
  echo
  echo "-- sessions seen (by event) --"
  sed -n 's/.*"event":"\([^"]*\)","sid":"\([^"]*\)".*/\1 \2/p' "$log" | sort -u
  echo
  echo "-- agent lifecycle events (pre/post Task|Agent + subagent-stop) --"
  grep -E '"event":"(pre|post|subagent-stop)"' "$log" | tail -n 60 | sed -E \
    's/.*"ts":"([^"]*)".*"event":"([^"]*)","sid":"([^"]*)","tool":"([^"]*)","agent":"([^"]*)","bg":"([^"]*)","states":"([^"]*)".*/\1  \2 sid=\3 tool=\4 agent=\5 bg=\6\n           states: \7/'
  echo
  echo "-- last 25 events (all) --"
  tail -n 25 "$log" | sed -E 's/.*"ts":"([^"]*)".*"event":"([^"]*)","sid":"([^"]*)","tool":"([^"]*)","agent":"([^"]*)".*/\1  \2  sid=\3 tool=\4 agent=\5/'
  exit 0
fi

# ------------------------------------------------------------- hook mode ----
if [ ! -f "$dir/enabled" ]; then cat > /dev/null 2>&1; exit 0; fi
mkdir -p "$dir" 2>/dev/null || exit 0

event=${1:-unknown}
# Read the FULL payload (fields like subagent_type can sit far beyond the
# first few KB — truncating first once made SubagentStop look unnamed and
# sent a whole investigation down the wrong path). Only the STORED copy is
# truncated; field extraction always scans everything.
full=$(cat)
input=$(printf '%s' "$full" | head -c 4000)

jfield() {
  printf '%s' "$full" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

esc() {
  printf '%s' "$1" \
    | tr -d '\000-\010\013\014\016-\037' \
    | tr '\n\t' '  ' \
    | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sid=$(jfield "session_id")
tool=$(jfield "tool_name")
agent=$(jfield "subagent_type")
[ -z "$agent" ] && agent=$(jfield "subagentType")
bg=0
printf '%s' "$full" | grep -qE '"(run_in_background|runInBackground)"[[:space:]]*:[[:space:]]*true' && bg=1
bytes=$(printf '%s' "$full" | wc -c | tr -d ' ')

# snapshot of every session's agent state at this instant
states=""
if [ -d "$status_dir" ]; then
  for f in "$status_dir"/*.agents; do
    [ -f "$f" ] || continue
    states="${states}$(basename "$f" .agents)=$(tr '\n' ',' < "$f" 2>/dev/null);"
  done
fi

printf '{"ts":"%s","epoch":%s,"event":"%s","sid":"%s","tool":"%s","agent":"%s","bg":"%s","bytes":%s,"states":"%s","payload":"%s"}\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S')" "$(date +%s)" \
  "$(esc "$event")" "$(esc "$sid")" "$(esc "$tool")" "$(esc "$agent")" "$bg" "${bytes:-0}" \
  "$(esc "$states")" "$(esc "$input")" >> "$log" 2>/dev/null

# rotation: cap ~8 MB, keep the newest 4000 events
if [ "$(wc -c < "$log" 2>/dev/null || echo 0)" -gt 8000000 ]; then
  tail -n 4000 "$log" > "$log.t.$$" 2>/dev/null && mv "$log.t.$$" "$log" 2>/dev/null
fi
exit 0
