#!/usr/bin/env bash
# Agent-status recorder — deterministic, zero model tokens, never blocks.
# Tracks which subagents are currently running so external consumers (status
# lines, the forge-office dashboard) can show live agent activity. Same
# contract as skill-status.sh: writes NOTHING to stdout, always exits 0.
#
# Usage (from hooks.json):
#   agent-status.sh start          # PreToolUse ^(Task|Agent)$ — spawning
#   agent-status.sh stop           # PostToolUse ^(Task|Agent)$ — tool returned
#   agent-status.sh subagent-stop  # SubagentStop — a subagent FINISHED
#   agent-status.sh turnend        # Stop — main turn ended: drop leftover
#                                  # foreground entries, sweep orphan files
#   agent-status.sh end            # SessionEnd — delete this session's file
#
# State file: ~/.claude/forge-status/<session_id>.agents
#   one line per active agent: "<agent-name> <epoch>[ B<epoch>]"  (oldest
#   first; trailing B* = running in background)
#
# STOP PROTOCOL — derived from recorded hook traces (hook-logger, 2026-07-20),
# not from assumptions. What the trace proved:
#   * PostToolUse for a BACKGROUND agent fires AT SPAWN, 0-1 s after start
#     (pre Agent 00:14:12 -> post Agent 00:14:13).
#   * SubagentStop fires at REAL COMPLETION (49 s+ after start) and DOES carry
#     subagent_type — it names the agent that finished, and every observed
#     stop matched the correct line.
#   * There is no "spawn echo" SubagentStop; the absorber that assumed one was
#     eating genuine completions.
# Therefore each signal has ONE unambiguous meaning and lives in its own mode:
#   stop (PostToolUse)  : plain entry -> foreground finished -> remove.
#                         B entry     -> spawn ack           -> leave alone.
#   subagent-stop       : always a completion -> remove that agent's entry
#                         exactly (prefer its B line); unnamed payloads fall
#                         back to dropping the oldest B entry.
# TTLs remain as a crash safety net: 20 min for B entries (a lost signal must
# not pin a ghost), 2 h for the rest.
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

# Prune. Two TTLs:
#   plain (foreground) entries: 2 h safety net (turnend sweeps them anyway)
#   B* (background) entries: 20 min — Claude Code does not reliably deliver a
#     completion signal for background agents, so a hard TTL is the only
#     guaranteed ghost-killer; long multi-lens reviews finish well within it.
prune() {
  [ -f "$state" ] || return 0
  now=$(date +%s)
  tmp="$state.tmp.$$"
  awk -v now="$now" '
    NF >= 3 && substr($3,1,1) == "B" { if (($2 + 0) > now - 1200) print; next }
    NF >= 2 { if (($2 + 0) > now - 7200) print }' "$state" > "$tmp" 2>/dev/null \
    && mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
}

# DEFENSE IN DEPTH: only the spawn tools may mutate state. Unanchored hook
# matchers ("Task|Agent") also fire for tools like TaskOutput — whose named
# PostToolUse carries NO agent name and previously fell through to the
# unnamed branch, deleting a LIVE background agent per output poll (the
# "5 agents spawned, dashboard shows 0" bug). SubagentStop has no tool_name,
# so an empty tool passes; any other named tool is ignored outright.
tool_name=$(jfield "tool_name")
if [ -n "$tool_name" ]; then
  case "$tool_name" in Task|Agent) ;; *) exit 0 ;; esac
fi

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

if [ "$mode" = "subagent-stop" ]; then
  # SubagentStop = a subagent FINISHED. Evidence (hook-logger, 2026-07-20):
  # the payload DOES carry subagent_type (deeper than 4 KB, which is why the
  # logger showed it empty), and it names the agent that actually completed —
  # every observed stop matched the right line. So removal is EXACT here, no
  # positional guessing. Foreground subagents are already removed by their
  # named PostToolUse, so a leftover plain entry is only hit as a fallback.
  prune
  [ -s "$state" ] || exit 0
  if [ -n "$agent" ] && grep -q "^$agent " "$state"; then
    # remove this agent's oldest entry, preferring a background (B) line
    if awk -v a="$agent" '$1 == a && NF >= 3 && substr($3,1,1) == "B" { f = 1 } END { exit !f }' "$state"; then
      awk -v a="$agent" '($1 == a && NF >= 3 && substr($3,1,1) == "B" && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    else
      awk -v a="$agent" '($1 == a && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    fi
    emit agent_stopped "agent=$agent"
  elif grep -qE ' B[0-9]*$' "$state"; then
    # unnamed fallback (older CC wording): drop the oldest background entry
    done_agent=$(awk 'NF >= 3 && substr($3,1,1)=="B" { print $1; exit }' "$state")
    awk '(NF >= 3 && substr($3,1,1)=="B" && !done) { done = 1; next } { print }' \
      "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    [ -n "$done_agent" ] && emit agent_stopped "agent=$done_agent"
  fi
  [ -s "$state" ] || rm -f "$state"
  exit 0
fi

if [ "$mode" = "stop" ]; then
  # PostToolUse for Task/Agent. For FOREGROUND agents the tool returns when
  # the subagent is done (remove). For BACKGROUND agents it returns AT SPAWN,
  # 0-1 s after the start entry (keep — completion arrives via SubagentStop).
  prune
  [ -s "$state" ] || exit 0
  now=$(date +%s)
  SPAWN_S=15
  if [ -n "$agent" ]; then
    # Named signal (PostToolUse) — the Task/Agent tool returned.
    started=$(awk -v a="$agent" '$1 == a && NF == 2 { print $2; exit }' "$state")
    if [ -n "$started" ] \
       && printf '%s' "$input" | grep -qi 'backgrounded agent' \
       && [ $((now - started)) -le "$SPAWN_S" ]; then
      # Background handoff (phrase heuristic): the tool returned AT SPAWN —
      # the agent is STILL RUNNING. Stamp B<now> so the imminent
      # SubagentStop echo is absorbed.
      awk -v a="$agent" -v s="B$now" \
        '($1 == a && NF == 2 && !done) { done = 1; print $1, $2, s; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
    elif [ -n "$started" ]; then
      # Foreground completion: the tool returned, the subagent is done.
      # Remove the oldest PLAIN entry for this agent — never a B entry
      # (a background agent's spawn ack must not kill it).
      awk -v a="$agent" '($1 == a && NF == 2 && !done) { done = 1; next } { print }' \
        "$state" > "$state.tmp.$$" && mv "$state.tmp.$$" "$state"
      emit agent_stopped "agent=$agent"
    fi
    # A B-stamped entry with no plain twin = the background spawn ack. Leave
    # it untouched: the agent is still running and SubagentStop will end it.
    # (v0.40.1 "refreshed" the stamp here, which also swallowed the real
    # completion signal once it turned out SubagentStop is named too.)
  fi
  # Unnamed PostToolUse cannot identify anything — ignore it outright.
  [ -s "$state" ] || rm -f "$state"
  exit 0
fi

# start
[ -z "$agent" ] && exit 0
prune
# STRUCTURAL background detection: run_in_background:true in tool_input means
# this agent is background from birth — stamp B<epoch> immediately instead of
# sniffing response phrasing later (phrasing changes across CC versions).
if printf '%s' "$input" | grep -qE '"(run_in_background|runInBackground)"[[:space:]]*:[[:space:]]*true'; then
  now=$(date +%s)
  printf '%s %s B%s\n' "$agent" "$now" "$now" >> "$state"
else
  printf '%s %s\n' "$agent" "$(date +%s)" >> "$state"
fi
emit agent_started "agent=$agent"
exit 0
