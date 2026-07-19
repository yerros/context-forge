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

@test "agent-status: REAL background flow — bg Post stamps B, echo SubagentStop absorbed, next SubagentStop removes" {
  bash "$AGENT_STATUS" start <<< "$(start_json bg1 forge-architect)"
  # PostToolUse returns immediately with a "Backgrounded agent" response
  bash "$AGENT_STATUS" stop <<< "$(bg_json bg1 forge-architect)"
  grep -qE '^forge-architect [0-9]+ B[0-9]+$' "$STATE_DIR/bg1.agents"
  # the spurious SubagentStop echo (seconds after spawn) must NOT remove it
  bash "$AGENT_STATUS" stop <<< '{"session_id":"bg1"}'
  grep -qE '^forge-architect [0-9]+ B0$' "$STATE_DIR/bg1.agents"
  [ ! -f "$HOME/.claude/forge-metrics/events.ndjson" ] || ! grep -q agent_stopped "$HOME/.claude/forge-metrics/events.ndjson"
  # minutes later, the REAL SubagentStop ends it
  bash "$AGENT_STATUS" stop <<< '{"session_id":"bg1"}'
  [ ! -s "$STATE_DIR/bg1.agents" ]
  grep -q agent_stopped "$HOME/.claude/forge-metrics/events.ndjson"
}

@test "agent-status: background with NO echo — aged stamp is removed by the true-end SubagentStop" {
  bash "$AGENT_STATUS" start <<< "$(start_json bg2 forge-architect)"
  bash "$AGENT_STATUS" stop <<< "$(bg_json bg2 forge-architect)"
  # age the stamp beyond the echo window (simulates a long-running agent)
  sed -i.bak -E 's/ B[0-9]+$/ B100/' "$STATE_DIR/bg2.agents" && rm -f "$STATE_DIR/bg2.agents.bak"
  bash "$AGENT_STATUS" stop <<< '{"session_id":"bg2"}'
  [ ! -s "$STATE_DIR/bg2.agents" ]
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
