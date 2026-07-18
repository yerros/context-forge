#!/usr/bin/env bash
# Agent-status recorder — deterministic, zero model tokens, never blocks.
# Tracks which subagents are currently running so external consumers (status
# lines, the forge-office dashboard) can show live agent activity. Same
# contract as skill-status.sh: writes NOTHING to stdout, always exits 0.
#
# Usage (from hooks.json):
#   agent-status.sh start   # PreToolUse,  matcher Task — a subagent is spawning
#   agent-status.sh stop    # PostToolUse, matcher Task — that Task call finished
#
# State file: ~/.claude/forge-status/<session_id>.agents
#   one line per active agent: "<agent-name> <epoch>"  (stack order: oldest first)
# PostToolUse carries the same tool_input as PreToolUse, so stop knows EXACTLY
# which agent finished and removes that entry (oldest instance of the name).
# If the payload unexpectedly has no agent name, it falls back to popping the
# newest entry. Entries older than 2 h are pruned as a crash safety net.
#
# Also emits opt-in metrics events (agent_started / agent_stopped) via
# metrics.sh — a no-op unless ~/.claude/forge-metrics/enabled exists.

set -u
mode=${1:-start}
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
state="$dir/$sid.agents"

metrics="$(dirname "$0")/metrics.sh"
emit() { [ -f "$metrics" ] && bash "$metrics" record "$@" 2>/dev/null; return 0; }

# Prune: drop entries older than 2 h (crashed/abandoned subagent sessions).
prune() {
  [ -f "$state" ] || return 0
  now=$(date +%s)
  tmp="$state.tmp.$$"
  while read -r a t; do
    [ -n "${t:-}" ] || continue
    [ $((now - t)) -lt 7200 ] && printf '%s %s\n' "$a" "$t"
  done < "$state" > "$tmp" 2>/dev/null
  mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
}

# Both modes need the subagent type from tool_input (defensive key list).
agent=""
for key in subagent_type subagentType agent_type agentType; do
  v=$(jfield "$key")
  if [ -n "$v" ]; then
    # Strip any plugin prefix ("context-forge:forge-reviewer" -> "forge-reviewer").
    agent=${v##*:}
    break
  fi
done
case "$agent" in *[!A-Za-z0-9._-]*) agent="" ;; esac

if [ "$mode" = "stop" ]; then
  prune
  [ -s "$state" ] || exit 0
  if [ -n "$agent" ] && grep -q "^$agent " "$state"; then
    # Precise removal: drop the OLDEST entry for this agent name.
    awk -v a="$agent" '($1 == a && !done) { done = 1; next } { print }' \
      "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    emit agent_stopped "agent=$agent"
  else
    # Fallback (payload without a name): pop the newest entry.
    last=$(tail -1 "$state")
    agent=${last%% *}
    n=$(wc -l < "$state" | tr -d ' ')
    if [ "$n" -le 1 ]; then : > "$state"; else
      head -n $((n - 1)) "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    fi
    [ -n "$agent" ] && emit agent_stopped "agent=$agent"
  fi
  exit 0
fi

# start
[ -z "$agent" ] && exit 0
prune
printf '%s %s\n' "$agent" "$(date +%s)" >> "$state"
emit agent_started "agent=$agent"
exit 0
