#!/usr/bin/env bats
# PreCompact snapshot + SessionStart replay (hooks/scripts/compact-snapshot.sh).

load helpers/common

SNAP="$PLUGIN_ROOT/hooks/scripts/compact-snapshot.sh"

setup() {
  setup_project
  mkdir -p context
  printf '# Tracker\n\n## In Progress\n\n- unit 07: payment webhook\n\n## Next Up\n\n- unit 08\n\n## Open Questions\n\n- none\n' > context/progress-tracker.md
}

@test "snapshot: non-forge project writes nothing and stays silent" {
  rm -rf context
  run bash "$SNAP" write <<< '{"trigger":"auto"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f context/.compact-snapshot.md ]
}

@test "snapshot: write freezes In Progress, Next Up, trigger, and dirty files" {
  init_git; commit_all
  printf 'x' > src.txt
  run bash "$SNAP" write <<< '{"trigger":"auto","session_id":"s1"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  f=context/.compact-snapshot.md
  grep -q 'trigger: auto' "$f"
  grep -q 'unit 07: payment webhook' "$f"
  grep -q 'unit 08' "$f"
  ! grep -q 'Open Questions' "$f"
  grep -q -- '- src.txt' "$f"
  ! grep -q 'compact-snapshot.md' "$f"
}

@test "snapshot: write records the active skill from the status file" {
  mkdir -p "$HOME/.claude/forge-status"
  printf 'active forge-build 1\n' > "$HOME/.claude/forge-status/s1"
  bash "$SNAP" write <<< '{"session_id":"s1"}'
  grep -q 'forge-build (active)' context/.compact-snapshot.md
}

@test "snapshot: inject on compact prints directive + snapshot" {
  bash "$SNAP" write <<< '{"trigger":"manual"}'
  run bash "$SNAP" inject <<< '{"source":"compact"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'[Context Forge]'* ]]
  [[ "$output" == *'memory aid, not a standing order'* ]]
  [[ "$output" == *'unit 07: payment webhook'* ]]
}

@test "snapshot: inject on resume also replays" {
  bash "$SNAP" write <<< '{}'
  run bash "$SNAP" inject <<< '{"source":"resume"}'
  [[ "$output" == *'unit 07'* ]]
}

@test "snapshot: inject on startup deletes the stale snapshot silently" {
  bash "$SNAP" write <<< '{}'
  run bash "$SNAP" inject <<< '{"source":"startup"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f context/.compact-snapshot.md ]
}

@test "snapshot: inject on clear or without a snapshot stays silent" {
  run bash "$SNAP" inject <<< '{"source":"clear"}'
  [ -z "$output" ]
  run bash "$SNAP" inject <<< '{"source":"compact"}'
  [ -z "$output" ]
}

@test "snapshot: .forge/ layout is honored" {
  mv context .forge
  bash "$SNAP" write <<< '{}'
  [ -f .forge/.compact-snapshot.md ]
  run bash "$SNAP" inject <<< '{"source":"compact"}'
  [[ "$output" == *'.forge/progress-tracker.md is authoritative'* ]]
}
