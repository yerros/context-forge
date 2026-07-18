#!/usr/bin/env bats
# agent-status.sh — live subagent tracking for status lines / dashboards.

load helpers/common

AGENT_STATUS="$PLUGIN_ROOT/hooks/scripts/agent-status.sh"

setup() {
  setup_project
  STATE_DIR="$HOME/.claude/forge-status"
}

start_json() { printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s","prompt":"x"}}' "$1" "$2"; }

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

@test "agent-status: stop removes exactly the named agent (not LIFO)" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4 forge-reviewer)"
  bash "$AGENT_STATUS" start <<< "$(start_json s4 forge-tester)"
  run bash "$AGENT_STATUS" stop <<< "$(start_json s4 forge-reviewer)"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STATE_DIR/s4.agents" | tr -d ' ')" -eq 1 ]
  [ "$(cut -d' ' -f1 "$STATE_DIR/s4.agents")" = "forge-tester" ]
}

@test "agent-status: duplicate agent names — stop removes only one instance" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4b forge-scout)"
  bash "$AGENT_STATUS" start <<< "$(start_json s4b forge-scout)"
  bash "$AGENT_STATUS" stop  <<< "$(start_json s4b forge-scout)"
  [ "$(wc -l < "$STATE_DIR/s4b.agents" | tr -d ' ')" -eq 1 ]
}

@test "agent-status: stop without a name falls back to popping the newest" {
  bash "$AGENT_STATUS" start <<< "$(start_json s4c forge-reviewer)"
  bash "$AGENT_STATUS" start <<< "$(start_json s4c forge-tester)"
  run bash "$AGENT_STATUS" stop <<< '{"session_id":"s4c"}'
  [ "$status" -eq 0 ]
  [ "$(cut -d' ' -f1 "$STATE_DIR/s4c.agents")" = "forge-reviewer" ]
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

@test "agent-status: emits metrics events with the agent name" {
  bash "$AGENT_STATUS" start <<< "$(start_json s8 forge-typer)"
  bash "$AGENT_STATUS" stop  <<< "$(start_json s8 forge-typer)"
  jq -es '[.[] | .event] | index("agent_started") != null and index("agent_stopped") != null' \
    < "$HOME/.claude/forge-metrics/events.ndjson" >/dev/null
  jq -es 'all(.[]; .agent == "forge-typer")' < "$HOME/.claude/forge-metrics/events.ndjson" >/dev/null
}

@test "agent-status: hooks.json wires start (PreToolUse Task) and stop (PostToolUse Task)" {
  run jq -r '.hooks.PreToolUse[] | select(.matcher | test("Task")) | .hooks[0].command' \
    "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'agent-status.sh" start'* ]]
  run jq -r '.hooks.PostToolUse[] | select(.matcher | test("Task")) | .hooks[0].command' \
    "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'agent-status.sh" stop'* ]]
}
