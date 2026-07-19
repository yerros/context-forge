#!/usr/bin/env bash
# Agent-status recorder — deterministic, zero model tokens, never blocks.
# Tracks which subagents are currently running so external consumers (status
# lines, the forge-office dashboard) can show live agent activity. Same
# contract as skill-status.sh: writes NOTHING to stdout, always exits 0.
#
# Usage (from hooks.json):
#   agent-status.sh start   # PreToolUse,   matcher Task — a subagent is spawning
#   agent-status.sh stop    # PostToolUse (named) AND SubagentStop (unnamed)
#   agent-status.sh turnend # Stop — the main turn ended: every foreground
#                           # subagent has returned, so clear this session's
#                           # foreground entries (keep B = background), and
#                           # sweep orphaned session files older than 2 h
#   agent-status.sh end     # SessionEnd — the session is gone: delete its file
#
# State file: ~/.claude/forge-status/<session_id>.agents
#   one line per active agent: "<agent-name> <epoch>[ B<epoch>|B0]"  (oldest
#   first; trailing B* = running in background)
#
# STOP PROTOCOL (single-signal; safe under PARALLEL spawns).
#   foreground:  the named PostToolUse means the Task/Agent tool RETURNED —
#                the subagent is done. Remove its oldest entry immediately.
#                No second signal needed; SubagentStop is ignored for
#                foreground (it carries no agent name, so under parallel
#                distinct-name agents any guess corrupts the state — the
#                cause of the "agents never stop" dashboard ghosts).
#   background:  PostToolUse fires AT SPAWN (response says "Backgrounded
#                agent…" AND arrives within SPAWN_S of the start entry) —
#                the entry is stamped B<epoch>, the agent stays live. A
#                SubagentStop within ECHO_S of the stamp is consumed as the
#                spawn echo (stamp becomes B0); a later SubagentStop is the
#                true completion and removes the oldest B entry.
# Both conditions must hold for the background stamp, so a foreground agent
# whose OUTPUT merely mentions "backgrounded agent" is not misclassified
# (its Post arrives long after SPAWN_S). Entries older than 2 h are pruned
# as a crash safety net (a lost signal cannot pin a ghost).
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
# Keeps lines intact — the optional trailing "B*" marker must survive.
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

if [ "$mode" = "end" ]; then
  # SessionEnd: the session (and any subagent in it) no longer exists.
  rm -f "$state"
  exit 0
fi

if [ "$mode" = "turnend" ]; then
  # Stop hook: the main turn ended, so every FOREGROUND subagent's tool has
  # returned — any plain entry left here is a missed signal, not a live agent.
  # Background (B*) entries survive: those agents may outlive the turn.
  if [ -s "$state" ]; then
    awk 'NF >= 3 && substr($3,1,1) == "B"' "$state" > "$state.tmp.$$" \
      && mv "$state.tmp.$$" "$state" || rm -f "$state.tmp.$$"
    [ -s "$state" ] || rm -f "$state"
  fi
  # Sweep ORPHANED session files (their session died without SessionEnd —
  # nothing will ever touch them again, so the per-session prune can't help).
  find "$dir" -maxdepth 1 -name '*.agents' -mmin +120 -delete 2>/dev/null
  exit 0
fi

if [ "$mode" = "stop" ]; then
  prune
  [ -s "$state" ] || exit 0
  now=$(date +%s)
  ECHO_S=15
  SPAWN_S=15
  if [ -n "$agent" ]; then
    # Named signal (PostToolUse) — the Task/Agent tool returned.
    started=$(awk -v a="$agent" '$1 == a && NF == 2 { print $2; exit }' "$state")
    if [ -n "$started" ] \
       && printf '%s' "$input" | grep -qi 'backgrounded agent' \
       && [ $((now - started)) -le "$SPAWN_S" ]; then
      # Background handoff: the tool returned AT SPAWN — the agent is STILL
      # RUNNING. Stamp it B<now> so the imminent SubagentStop echo is absorbed.
      awk -v a="$agent" -v s="B$now" \
        '($1 == a && NF == 2 && !done) { done = 1; print $1, $2, s; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    elif grep -q "^$agent " "$state"; then
      # Foreground completion: the tool returned, the subagent is done.
      # Remove the oldest entry for this agent — single signal, no pairing.
      awk -v a="$agent" '($1 == a && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      emit agent_stopped "agent=$agent"
    fi
  else
    # Unnamed signal (SubagentStop) — meaningful only for BACKGROUND agents.
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
    fi
    # 3) No B entries -> foreground SubagentStop: IGNORE. The named
    # PostToolUse handles foreground removal; guessing here by position
    # corrupts the state under parallel distinct-name agents.
  fi
  exit 0
fi

# start
[ -z "$agent" ] && exit 0
prune
printf '%s %s\n' "$agent" "$(date +%s)" >> "$state"
emit agent_started "agent=$agent"
exit 0
