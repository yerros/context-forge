#!/usr/bin/env bats
# forge-office.sh — bundled dashboard launcher (start/stop/status/autostart).

load helpers/common

LAUNCHER="$PLUGIN_ROOT/skills/forge-office/scripts/forge-office.sh"

setup() {
  setup_project
  export FORGE_OFFICE_PORT=4877
  mkdir -p context
  printf '## In Progress\n\n- unit 01\n' > context/progress-tracker.md
}

teardown() {
  bash "$LAUNCHER" stop >/dev/null 2>&1 || true
}

@test "office: start serves the dashboard and is idempotent" {
  command -v node >/dev/null || skip "node not installed"
  run bash "$LAUNCHER" start
  [ "$status" -eq 0 ]
  [[ "$output" == *'http://127.0.0.1:4877'* ]]
  curl -sf http://127.0.0.1:4877/api/state | grep -q '"project"'
  run bash "$LAUNCHER" start
  [[ "$output" == *'already running'* ]]
}

@test "office: status reports project and autostart, stop kills the server" {
  command -v node >/dev/null || skip "node not installed"
  bash "$LAUNCHER" start >/dev/null
  run bash "$LAUNCHER" status
  [[ "$output" == *'running: http://127.0.0.1:4877'* ]]
  [[ "$output" == *'autostart: off'* ]]
  run bash "$LAUNCHER" stop
  [[ "$output" == *'stopped'* ]]
  run bash "$LAUNCHER" status
  [[ "$output" == *'not running'* ]]
}

@test "office: autostart on/off toggles the marker" {
  bash "$LAUNCHER" autostart on >/dev/null
  [ -f "$HOME/.claude/forge-office/autostart" ]
  bash "$LAUNCHER" autostart off >/dev/null
  [ ! -f "$HOME/.claude/forge-office/autostart" ]
}

@test "office: --hook mode is silent outside a Context Forge project" {
  cd "$BATS_TEST_TMPDIR"; mkdir -p plain && cd plain
  run bash "$LAUNCHER" start --hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "office: --hook mode starts (one line) inside a forge project" {
  command -v node >/dev/null || skip "node not installed"
  run bash "$LAUNCHER" start --hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *'dashboard: http://127.0.0.1:4877'* ]]
}

@test "office: hooks.json wires autostart into SessionStart" {
  run jq -r '.hooks.SessionStart[0].hooks[] | .command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *'forge-office.sh" start --hook'* ]]
  [[ "$output" == *'forge-office/autostart'* ]]
}
