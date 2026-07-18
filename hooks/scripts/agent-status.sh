#!/usr/bin/env bash
# Agent-status recorder — deterministic, zero model tokens, never blocks.
# Tracks which subagents are currently running so external consumers (status
# lines, the forge-office dashboard) can show live agent activity. Same
# contract as skill-status.sh: writes NOTHING to stdout, always exits 0.
#
# Usage (from hooks.json):
#   agent-status.sh start   # PreToolUse,   matcher Task — a subagent is spawning
#   agent-status.sh stop    # PostToolUse (named) AND SubagentStop (unnamed)
#
# State file: ~/.claude/forge-status/<session_id>.agents
#   one line per active agent: "<agent-name> <epoch>[ P]"  (oldest first;
#   trailing P = one stop signal already seen)
#
# STOP PROTOCOL. Signals per instance depend on how it ran:
#   foreground:  SubagentStop (true end) then PostToolUse (named, same moment)
#                -> two signals: first MARKS (P), second removes.
#   background:  PostToolUse fires AT SPAWN (the tool returns "Backgrounded
#                agent..."), and a spurious SubagentStop ECHO can fire moments
#                later — the real SubagentStop only comes at the true end.
# Background is detected from the PostToolUse tool_response ("backgrounded"):
# the entry is stamped "B<epoch>". A SubagentStop within ECHO_S seconds of the
# stamp is consumed as the spawn echo (entry becomes "B0"); the NEXT
# SubagentStop is the true completion and removes it. Foreground keeps the
# plain two-signal P protocol. Entries older than 2 h are pruned as a crash
# safety net (a lost signal cannot pin a ghost).
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
# Keeps lines intact — the optional trailing "P" marker must survive.
prune() {
  [ -f "$state" ] || return 0
  now=$(date +%s)
  tmp="$state.tmp.$$"
  awk -v now="$now" 'NF >= 2 && ($2 + 0) > now - 7200' "$state" > "$tmp" 2>/dev/null \
    && mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
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
  now=$(date +%s)
  ECHO_S=15
  if [ -n "$agent" ]; then
    # Named signal (PostToolUse).
    if printf '%s' "$input" | grep -qi 'backgrounded' \
       && grep -q "^$agent [0-9]*$" "$state"; then
      # Background handoff: the tool returned immediately — the agent is STILL
      # RUNNING. Stamp it B<now> so the imminent SubagentStop echo is absorbed.
      awk -v a="$agent" -v s="B$now" \
        '($1 == a && NF == 2 && !done) { done = 1; print $1, $2, s; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    elif grep -q "^$agent [0-9]* P$" "$state"; then
      # Second signal for a foreground instance -> remove the oldest marked.
      awk -v a="$agent" '($1 == a && $3 == "P" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      emit agent_stopped "agent=$agent"
    elif grep -q "^$agent [0-9]*$" "$state"; then
      # First signal -> mark the oldest unmarked instance.
      awk -v a="$agent" '($1 == a && NF == 2 && !done) { done = 1; print $0 " P"; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    fi
  else
    # Unnamed signal (SubagentStop).
    # 1) Absorb a background spawn echo: a fresh B<epoch> stamp within ECHO_S.
    fresh=$(awk -v now="$now" -v w="$ECHO_S" \
      'substr($3,1,1)=="B" && $3!="B0" && now - substr($3,2) < w { print NR; exit }' "$state")
    if [ -n "$fresh" ]; then
      awk -v n="$fresh" 'NR==n { print $1, $2, "B0"; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    # 2) True completion of a background agent (echo consumed or stamp aged).
    elif grep -qE ' B[0-9]*$' "$state"; then
      done_agent=$(awk 'substr($3,1,1)=="B" { print $1; exit }' "$state")
      awk '(substr($3,1,1)=="B" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      [ -n "$done_agent" ] && emit agent_stopped "agent=$done_agent"
    # 3) Foreground: second signal removes the marked entry…
    elif grep -q " P$" "$state"; then
      done_agent=$(awk '$3 == "P" { print $1; exit }' "$state")
      awk '($3 == "P" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      [ -n "$done_agent" ] && emit agent_stopped "agent=$done_agent"
    # 4) …or the first signal marks the newest entry.
    else
      awk 'NR==FNR { last = FNR; next } { if (FNR == last && NF == 2) print $0 " P"; else print }' \
        "$state" "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    fi
  fi
  exit 0
fi

# start
[ -z "$agent" ] && exit 0
prune
printf '%s %s\n' "$agent" "$(date +%s)" >> "$state"
emit agent_started "agent=$agent"
exit 0
