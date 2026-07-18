#!/usr/bin/env bats
# SessionStart hook — the inline command in hooks.json, extracted via jq and run
# verbatim so these tests exercise exactly what ships.

load helpers/common

setup() { setup_project; }

@test "session-start: digest in context/ is injected with tiered instructions" {
  mkdir -p context
  printf '# Digest\n\nMy project one-liner.\n' > context/context-digest.md
  run run_session_start
  [ "$status" -eq 0 ]
  [[ "$output" == *'[Context Forge]'* ]]
  [[ "$output" == *'context directory is context/'* ]]
  [[ "$output" == *'My project one-liner.'* ]]
}

@test "session-start: .forge/ digest wins and is named in the output" {
  mkdir -p .forge context
  printf 'forge digest\n' > .forge/context-digest.md
  printf 'stale context digest\n' > context/context-digest.md
  printf 'tracker\n' > .forge/progress-tracker.md
  run run_session_start
  [[ "$output" == *'context directory is .forge/'* ]]
  [[ "$output" == *'forge digest'* ]]
  [[ "$output" != *'stale context digest'* ]]
}

@test "session-start: pre-digest project falls back to tracker injection (old format)" {
  mkdir -p context
  printf '## In Progress\n\n- unit 07\n' > context/progress-tracker.md
  run run_session_start
  [ "$status" -eq 0 ]
  [[ "$output" == *'unit 07'* ]]
  [[ "$output" == *'read the entry point'* ]]
}

@test "session-start: non-forge project stays silent" {
  run run_session_start
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-start: empty (0-byte) digest does not break the hook" {
  mkdir -p context
  : > context/context-digest.md
  run run_session_start
  [ "$status" -eq 0 ]
  [[ "$output" == *'[Context Forge]'* ]]
}

@test "session-start: digest with shell metacharacters is passed through literally" {
  mkdir -p context
  printf 'uses `backticks` and $(subshell) and $VARS\n' > context/context-digest.md
  run run_session_start
  [ "$status" -eq 0 ]
  [[ "$output" == *'$(subshell)'* ]]
  [[ "$output" == *'$VARS'* ]]
}
