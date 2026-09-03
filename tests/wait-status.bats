#!/usr/bin/env bats
# wait-status.sh — blocked-on-user recorder for the forge-office dashboard.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  S="$PLUGIN_ROOT/hooks/scripts/wait-status.sh"
  F="$HOME/.claude/forge-status/sid-1.wait"
}

run_hook() { printf '%s' "$2" | bash "$S" "$1"; }

@test "wait-status: permission writes 'permission <epoch>', no stdout" {
  run run_hook permission '{"session_id":"sid-1","tool_name":"Bash"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  read -r kind epoch < "$F"
  [ "$kind" = permission ]; [ "$epoch" -gt 0 ]
}

@test "wait-status: stop writes 'waiting'" {
  run_hook stop '{"session_id":"sid-1"}'
  read -r kind _ < "$F"; [ "$kind" = waiting ]
}

@test "wait-status: notify maps notification_type, ignores others" {
  run_hook notify '{"session_id":"sid-1","notification_type":"idle_prompt"}'
  read -r kind _ < "$F"; [ "$kind" = waiting ]
  run_hook notify '{"session_id":"sid-1","notification_type":"permission_prompt"}'
  read -r kind _ < "$F"; [ "$kind" = permission ]
  rm -f "$F"
  run_hook notify '{"session_id":"sid-1","notification_type":"auth_success"}'
  [ ! -f "$F" ]
}

@test "wait-status: clear removes the file; stop after permission downgrades to waiting" {
  run_hook permission '{"session_id":"sid-1"}'
  run_hook stop '{"session_id":"sid-1"}'
  read -r kind _ < "$F"; [ "$kind" = waiting ]
  run_hook clear '{"session_id":"sid-1"}'
  [ ! -f "$F" ]
}

@test "wait-status: unsafe or missing session_id writes nothing" {
  run_hook stop '{"session_id":"../evil"}'
  run_hook stop '{"tool_name":"Bash"}'
  [ -z "$(ls -A "$HOME/.claude/forge-status" 2>/dev/null)" ]
}

@test "wait-status: hooks.json wires notify, permission, stop and both clears" {
  J="$PLUGIN_ROOT/hooks/hooks.json"
  jq -r '.hooks.Notification[].hooks[].command'      "$J" | grep -q 'wait-status.sh" notify'
  jq -r '.hooks.PermissionRequest[].hooks[].command' "$J" | grep -q 'wait-status.sh" permission'
  jq -r '.hooks.Stop[].hooks[].command'              "$J" | grep -q 'wait-status.sh" stop'
  jq -r '.hooks.PreToolUse[0].hooks[].command'       "$J" | grep -q 'wait-status.sh" clear'
  jq -r '.hooks.UserPromptSubmit[].hooks[].command'  "$J" | grep -q 'wait-status.sh" clear'
}
