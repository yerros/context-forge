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
# TWO-SIGNAL STOP PROTOCOL. Every subagent instance produces exactly two
# stop-ish events, in an order that depends on how it ran:
#   foreground:  SubagentStop (true end)  then  PostToolUse (named, same moment)
#   background:  PostToolUse (named, AT SPAWN — the tool returns immediately)
#                then  SubagentStop (true end, possibly minutes later)
# So neither event alone is correct: PostToolUse knows WHO but (for background
# agents) not WHEN; SubagentStop knows WHEN but not WHO. The protocol: the
# FIRST signal for an instance only MARKS it (P), the SECOND removes it.
# In both orders, removal lands on the true completion. Entries older than
# 2 h are pruned as a crash safety net (a lost signal cannot pin a ghost).
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
  if [ -n "$agent" ]; then
    # Named signal (PostToolUse). Second signal for this name -> remove the
    # oldest MARKED instance; first signal -> mark the oldest UNMARKED one.
    if grep -q "^$agent [0-9]* P$" "$state"; then
      awk -v a="$agent" '($1 == a && $3 == "P" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      emit agent_stopped "agent=$agent"
    elif grep -q "^$agent " "$state"; then
      awk -v a="$agent" '($1 == a && NF == 2 && !done) { done = 1; print $0 " P"; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    fi
  else
    # Unnamed signal (SubagentStop). Second signal -> remove the oldest marked
    # entry; first signal -> mark the NEWEST entry (the agent that just ended).
    if grep -q " P$" "$state"; then
      done_agent=$(awk '$3 == "P" { print $1; exit }' "$state")
      awk '($3 == "P" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      [ -n "$done_agent" ] && emit agent_stopped "agent=$done_agent"
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
