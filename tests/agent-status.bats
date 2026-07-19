#!/usr/bin/env bats
# agent-status.sh — live subagent tracking for status lines / dashboards.

load helpers/common

AGENT_STATUS="$PLUGIN_ROOT/hooks/scripts/agent-status.sh"

setup() {
  setup_project
  STATE_DIR="$HOME/.claude/forge-status"
}

start_json() { printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s","prompt":"x"}}' "$1" "$2"; }
bg_json() { printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s"},"tool_response":{"content":"Backgrounded agent (use TaskOutput to monitor)"}}' "$1" "$2"; }

@test "agent-status: start records the subagent with epoch" {
  run bash "$AGENT_STATUS" start <<< "$(start_json s1 forge-reviewer)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  read -r a t < "$STATE_DIR/s1.agents"
  [ "$a" = "forge-reviewer" ]
  [ "$t" -gt 0 ]
}

@test "agent-status: plugin-prefixed subagent type is stripped" {
  bash "$AGENT_STATUS" start <<< "$(start_json s2 "context-forge:forge-scout")"
  read -r a _ < "$STATE_DIR/s2.agents"
  [ "$a" = "forge-scout" ]
}

@test "agent-status: multiple starts stack in order" {
  bash "$AGENT_STATUS" start <<< "$(start_json s3 forge-reviewer)"
  bash "$AGENT_STATUS" start <<< "$(start_json s3 forge-tester)"
  [ "$(wc -l < "$STATE_DIR/s3.agents" | tr -d ' ')" -eq 2 ]
  [ "$(tail -1 "$STATE_DIR/s3.agents" | cut -d' ' -f1)" = "forge-tester" ]
}

@test "agent-status: FOREGROUND — SubagentStop is a no-op, the named Post removes" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4 forge-reviewer)"
  # SubagentStop (unnamed) may arrive first -> ignored, entry untouched
  bash "$AGENT_STATUS" stop <<< '{"session_id":"s4"}'
  [ "$(wc -l < "$STATE_DIR/s4.agents" | tr -d ' ')" -eq 1 ]
  grep -qE '^forge-reviewer [0-9]+$' "$STATE_DIR/s4.agents"
  # PostToolUse (named) = the tool returned = the agent is done -> removed
  bash "$AGENT_STATUS" stop <<< "$(start_json s4 forge-reviewer)"
  [ ! -s "$STATE_DIR/s4.agents" ]
}

@test "agent-status: FOREGROUND — named Post alone removes (no SubagentStop ever)" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4b forge-reviewer)"
  bash "$AGENT_STATUS" stop <<< "$(start_json s4b forge-reviewer)"
  [ ! -s "$STATE_DIR/s4b.agents" ]
}

@test "agent-status: PARALLEL distinct-name agents all clear (dashboard ghost regression)" {
  # 7 agents spawned in one parallel batch — the exact shape that used to
  # leave permanent "working" ghosts in the forge-office dashboard.
  agents="frontend-agent forge-reviewer forge-tester forge-failure-hunter forge-typer forge-commenter general-purpose"
  for a in $agents; do
    bash "$AGENT_STATUS" start <<< "$(start_json s4c $a)"
  done
  [ "$(wc -l < "$STATE_DIR/s4c.agents" | tr -d ' ')" -eq 7 ]
  # worst-case signal order: every SubagentStop fires before any named Post
  for a in $agents; do
    bash "$AGENT_STATUS" stop <<< '{"session_id":"s4c"}'
  done
  [ "$(wc -l < "$STATE_DIR/s4c.agents" | tr -d ' ')" -eq 7 ]   # untouched
  for a in $agents; do
    bash "$AGENT_STATUS" stop <<< "$(start_json s4c $a)"
  done
  [ ! -s "$STATE_DIR/s4c.agents" ]                              # ALL cleared
}

@test "agent-status: REAL background flow — bg Post is the spawn ack (agent stays live)" {
  bash "$AGENT_STATUS" start <<< "$(start_json bg1 forge-architect)"
  # PostToolUse returns ~1s later: the spawn ack. The agent must STAY.
  bash "$AGENT_STATUS" stop <<< "$(bg_json bg1 forge-architect)"
  grep -qE '^forge-architect [0-9]+ B[0-9]+$' "$STATE_DIR/bg1.agents"
  # the real completion arrives on the dedicated SubagentStop mode, and it is
  # NAMED (subagent_type sits deep in the payload) -> exact removal
  bash "$AGENT_STATUS" subagent-stop <<< '{"session_id":"bg1","subagent_type":"forge-architect"}'
  [ ! -s "$STATE_DIR/bg1.agents" ]
  grep -q agent_stopped "$HOME/.claude/forge-metrics/events.ndjson"
}

@test "agent-status: SubagentStop removes the NAMED agent, not the oldest (real trace replay)" {
  # 5 parallel background agents, completing out of spawn order — the exact
  # scenario recorded by hook-logger on 2026-07-20.
  for a in forge-reviewer forge-tester forge-failure-hunter forge-typer forge-commenter; do
    printf '{"session_id":"tr","tool_name":"Agent","tool_input":{"subagent_type":"%s","run_in_background":true}}' "$a" \
      | bash "$AGENT_STATUS" start
    printf '{"session_id":"tr","tool_name":"Agent","tool_input":{"subagent_type":"%s","run_in_background":true},"tool_response":"launched"}' "$a" \
      | bash "$AGENT_STATUS" stop
  done
  [ "$(wc -l < "$STATE_DIR/tr.agents" | tr -d ' ')" -eq 5 ]
  # commenter finishes FIRST — the oldest entry (reviewer) must survive
  bash "$AGENT_STATUS" subagent-stop <<< '{"session_id":"tr","subagent_type":"context-forge:forge-commenter"}'
  [ "$(wc -l < "$STATE_DIR/tr.agents" | tr -d ' ')" -eq 4 ]
  ! grep -q '^forge-commenter ' "$STATE_DIR/tr.agents"
  grep -q '^forge-reviewer ' "$STATE_DIR/tr.agents"
  for a in forge-tester forge-failure-hunter forge-typer forge-reviewer; do
    printf '{"session_id":"tr","subagent_type":"%s"}' "$a" | bash "$AGENT_STATUS" subagent-stop
  done
  [ ! -s "$STATE_DIR/tr.agents" ]
}

@test "agent-status: a background spawn ack never removes the agent (v0.40.1 regression)" {
  printf '{"session_id":"bg2","tool_name":"Agent","tool_input":{"subagent_type":"forge-architect","run_in_background":true}}' \
    | bash "$AGENT_STATUS" start
  for _ in 1 2 3; do
    printf '{"session_id":"bg2","tool_name":"Agent","tool_input":{"subagent_type":"forge-architect","run_in_background":true},"tool_response":"launched"}' \
      | bash "$AGENT_STATUS" stop
  done
  [ "$(wc -l < "$STATE_DIR/bg2.agents" | tr -d ' ')" -eq 1 ]
}

@test "agent-status: foreground output mentioning 'backgrounded' is not misclassified" {
  bash "$AGENT_STATUS" start <<< "$(start_json bg3 forge-scout)"
  # age the entry past SPAWN_S — a genuine bg handoff Post fires within seconds
  sed -i.bak -E 's/ [0-9]+$/ 1000000000/' "$STATE_DIR/bg3.agents" && rm -f "$STATE_DIR/bg3.agents.bak"
  bash "$AGENT_STATUS" stop <<< "$(bg_json bg3 forge-scout)"                # Post whose text contains "Backgrounded"
  [ ! -s "$STATE_DIR/bg3.agents" ]                                          # removed, not stuck as B
}

@test "agent-status: mixed names — each named Post removes exactly its own agent" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4d forge-reviewer)"
  bash "$AGENT_STATUS" start <<< "$(start_json s4d forge-tester)"
  bash "$AGENT_STATUS" stop <<< '{"session_id":"s4d"}'                 # unnamed: ignored
  bash "$AGENT_STATUS" stop <<< "$(start_json s4d forge-tester)"       # removes tester only
  [ "$(wc -l < "$STATE_DIR/s4d.agents" | tr -d ' ')" -eq 1 ]
  [ "$(cut -d' ' -f1 "$STATE_DIR/s4d.agents")" = "forge-reviewer" ]
}

@test "agent-status: turnend clears leftover foreground entries, keeps background" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4e forge-reviewer)"    # fg, signal lost
  bash "$AGENT_STATUS" start <<< "$(start_json s4e forge-architect)"
  bash "$AGENT_STATUS" stop  <<< "$(bg_json s4e forge-architect)"      # bg, still running
  bash "$AGENT_STATUS" turnend <<< '{"session_id":"s4e"}'
  [ "$(wc -l < "$STATE_DIR/s4e.agents" | tr -d ' ')" -eq 1 ]
  grep -qE '^forge-architect [0-9]+ B' "$STATE_DIR/s4e.agents"
  # all-foreground leftovers -> file removed entirely
  bash "$AGENT_STATUS" start <<< "$(start_json s4f forge-scout)"
  bash "$AGENT_STATUS" turnend <<< '{"session_id":"s4f"}'
  [ ! -e "$STATE_DIR/s4f.agents" ]
}

@test "agent-status: turnend sweeps orphaned session files older than 2h" {
  mkdir -p "$STATE_DIR"
  printf 'forge-scout 1000\n' > "$STATE_DIR/dead-session.agents"
  touch -d '3 hours ago' "$STATE_DIR/dead-session.agents" 2>/dev/null \
    || touch -t "$(date -d '3 hours ago' +%Y%m%d%H%M 2>/dev/null || date -v-3H +%Y%m%d%H%M)" "$STATE_DIR/dead-session.agents"
  bash "$AGENT_STATUS" start <<< "$(start_json s4g forge-reviewer)"    # fresh file untouched
  bash "$AGENT_STATUS" turnend <<< '{"session_id":"s4g"}'
  [ ! -e "$STATE_DIR/dead-session.agents" ]
}

@test "agent-status: SessionEnd deletes the session's state file" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4h forge-reviewer)"
  bash "$AGENT_STATUS" stop  <<< "$(bg_json s4h forge-reviewer)"       # even a live bg entry
  bash "$AGENT_STATUS" end <<< '{"session_id":"s4h"}'
  [ ! -e "$STATE_DIR/s4h.agents" ]
}

@test "agent-status: stop on empty state is a silent no-op" {
  run bash "$AGENT_STATUS" stop <<< '{"session_id":"s5"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "agent-status: entries older than 2h are pruned" {
  mkdir -p "$STATE_DIR"
  printf 'forge-scout 1000\n' > "$STATE_DIR/s6.agents"   # epoch 1000 = long dead
  bash "$AGENT_STATUS" start <<< "$(start_json s6 forge-reviewer)"
  [ "$(wc -l < "$STATE_DIR/s6.agents" | tr -d ' ')" -eq 1 ]
  [ "$(cut -d' ' -f1 "$STATE_DIR/s6.agents")" = "forge-reviewer" ]
}

@test "agent-status: missing session_id / unsafe id / no agent key -> silent no-op" {
  run bash "$AGENT_STATUS" start <<< '{"tool_input":{"subagent_type":"forge-scout"}}'
  [ "$status" -eq 0 ]
  run bash "$AGENT_STATUS" start <<< '{"session_id":"../evil","tool_input":{"subagent_type":"x"}}'
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/evil.agents" ]
  run bash "$AGENT_STATUS" start <<< '{"session_id":"s7","tool_input":{"prompt":"no type"}}'
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_DIR/s7.agents" ]
}

@test "agent-status: metrics — started at spawn, stopped at the named Post" {
  bash "$AGENT_STATUS" start <<< "$(start_json s8 forge-typer)"
  ! grep -q agent_stopped "$HOME/.claude/forge-metrics/events.ndjson"
  bash "$AGENT_STATUS" stop  <<< "$(start_json s8 forge-typer)"    # tool returned -> stopped
  jq -es '[.[] | .event] | index("agent_started") != null and index("agent_stopped") != null' \
    < "$HOME/.claude/forge-metrics/events.ndjson" >/dev/null
  jq -es 'all(.[]; .agent == "forge-typer")' < "$HOME/.claude/forge-metrics/events.ndjson" >/dev/null
}

@test "agent-status: hooks.json wires start (PreToolUse) and both stop signals (PostToolUse + SubagentStop)" {
  run jq -r '.hooks.PreToolUse[] | select(.matcher | test("Task")) | .hooks[0].command' \
    "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'agent-status.sh" start'* ]]
  run jq -r '.hooks.PostToolUse[] | select(.matcher | test("Task")) | .hooks[0].command' \
    "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'agent-status.sh" stop'* ]]
  run jq -r '.hooks.SubagentStop[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'agent-status.sh" stop'* ]]
}

# ---- v0.40.1 regressions: the "5 live agents, dashboard shows 0" bug ------

@test "agent-status: PostToolUse from TaskOutput NEVER touches background entries" {
  # 3 structurally-background agents live
  for a in forge-reviewer forge-tester forge-typer; do
    printf '{"session_id":"s20","tool_name":"Task","tool_input":{"subagent_type":"%s","run_in_background":true}}' "$a" \
      | bash "$AGENT_STATUS" start
  done
  [ "$(wc -l < "$STATE_DIR/s20.agents" | tr -d ' ')" -eq 3 ]
  # output polls (named Post, no subagent name) — the old code deleted one per poll
  for _ in 1 2 3 4; do
    printf '{"session_id":"s20","tool_name":"TaskOutput","tool_input":{"task_id":"x"}}' \
      | bash "$AGENT_STATUS" stop
  done
  [ "$(wc -l < "$STATE_DIR/s20.agents" | tr -d ' ')" -eq 3 ]
}

@test "agent-status: run_in_background:true stamps B at start; spawn ack keeps it live" {
  printf '{"session_id":"s21","tool_name":"Task","tool_input":{"subagent_type":"forge-scout","run_in_background":true}}' \
    | bash "$AGENT_STATUS" start
  grep -qE '^forge-scout [0-9]+ B[0-9]+$' "$STATE_DIR/s21.agents"
  # spawn ack WITHOUT the legacy "backgrounded agent" phrase (new CC wording)
  printf '{"session_id":"s21","tool_name":"Task","tool_input":{"subagent_type":"forge-scout","run_in_background":true},"tool_response":"Async agent launched"}' \
    | bash "$AGENT_STATUS" stop
  grep -qE '^forge-scout [0-9]+ B[0-9]+$' "$STATE_DIR/s21.agents"
}

@test "agent-status: named Post for other tools is ignored even with sloppy matchers" {
  printf '{"session_id":"s22","tool_name":"Task","tool_input":{"subagent_type":"forge-reviewer"}}' \
    | bash "$AGENT_STATUS" start
  printf '{"session_id":"s22","tool_name":"BashOutput","tool_input":{}}' | bash "$AGENT_STATUS" stop
  printf '{"session_id":"s22","tool_name":"AgentOutput","tool_input":{}}' | bash "$AGENT_STATUS" stop
  [ "$(wc -l < "$STATE_DIR/s22.agents" | tr -d ' ')" -eq 1 ]
}
