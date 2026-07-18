#!/usr/bin/env bats
# Skill-status recorder (hooks/scripts/skill-status.sh) — status line state file.

load helpers/common

setup() {
  setup_project
  STATE_DIR="$HOME/.claude/forge-status"
}

@test "skill-status: slash command via command_name is captured" {
  run bash "$SKILL_STATUS" capture <<< '{"session_id":"abc-123","command_name":"forge-fix"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  read -r st sk _ < "$STATE_DIR/abc-123"
  [ "$st" = "active" ]
  [ "$sk" = "forge-fix" ]
}

@test "skill-status: plugin-prefixed skill name is stripped" {
  run bash "$SKILL_STATUS" capture <<< '{"session_id":"s1","skill":"context-forge:forge-build"}'
  read -r _ sk _ < "$STATE_DIR/s1"
  [ "$sk" = "forge-build" ]
}

@test "skill-status: non-forge skill writes nothing" {
  run bash "$SKILL_STATUS" capture <<< '{"session_id":"s2","skill":"commit-helper"}'
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_DIR/s2" ]
}

@test "skill-status: missing session_id exits 0 silently" {
  run bash "$SKILL_STATUS" capture <<< '{"command_name":"forge-fix"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "skill-status: path-traversal session id is refused" {
  run bash "$SKILL_STATUS" capture <<< '{"session_id":"../../evil","command_name":"forge-fix"}'
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/evil" ]
  [ ! -e "$HOME/evil" ]
}

@test "skill-status: idle downgrades active but keeps the skill name" {
  bash "$SKILL_STATUS" capture <<< '{"session_id":"s3","command_name":"forge-build"}'
  run bash "$SKILL_STATUS" idle <<< '{"session_id":"s3"}'
  [ "$status" -eq 0 ]
  read -r st sk _ < "$STATE_DIR/s3"
  [ "$st" = "idle" ]
  [ "$sk" = "forge-build" ]
}

@test "skill-status: idle without prior state exits 0" {
  run bash "$SKILL_STATUS" idle <<< '{"session_id":"never-seen"}'
  [ "$status" -eq 0 ]
}

@test "skill-status: corrupt payload exits 0 silently" {
  run bash "$SKILL_STATUS" capture <<< 'garbage'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "skill-status: state files older than a day are pruned" {
  mkdir -p "$STATE_DIR"
  printf 'idle forge-fix 0\n' > "$STATE_DIR/old-session"
  touch -d '2 days ago' "$STATE_DIR/old-session" 2>/dev/null \
    || touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null)" "$STATE_DIR/old-session"
  bash "$SKILL_STATUS" capture <<< '{"session_id":"fresh","command_name":"forge-fix"}'
  [ ! -f "$STATE_DIR/old-session" ]
  [ -f "$STATE_DIR/fresh" ]
}
