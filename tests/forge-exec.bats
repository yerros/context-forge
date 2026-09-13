#!/usr/bin/env bats
# forge-exec.sh — long-output runner that keeps the log out of the conversation.

load helpers/common

EXEC="$PLUGIN_ROOT/skills/forge-build/scripts/forge-exec.sh"

setup() { setup_project; mkdir -p context; printf 't\n' > context/progress-tracker.md; }

@test "forge-exec: prints exit code, log path, and only the tail" {
  run bash "$EXEC" -n 3 'seq 1 100'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == 'exit 0 — full log: context/.runs/'*'(100 lines,'* ]]
  [[ "$output" == *$'98\n99\n100' ]]
  [[ "$output" != *$'\n50\n'* ]]
  log=$(ls context/.runs/*.log); [ "$(wc -l < "$log" | tr -d ' ')" -eq 100 ]
}

@test "forge-exec: propagates the command's exit status and captures stderr" {
  run bash "$EXEC" 'echo out; echo err >&2; exit 3'
  [ "$status" -eq 3 ]
  [[ "${lines[0]}" == 'exit 3 — '* ]]
  [[ "$output" == *'err'* ]]
}

@test "forge-exec: -g returns matching lines instead of the tail" {
  run bash "$EXEC" -g 'error|fail' 'printf "ok\nERROR: boom\nok\nTest failed\nok\n"'
  [[ "$output" == *'2:ERROR: boom'* ]]
  [[ "$output" == *'4:Test failed'* ]]
  [[ "$output" != *$'\nok\n'* ]]
}

@test "forge-exec: no command -> usage, exit 2" {
  run bash "$EXEC"
  [ "$status" -eq 2 ]
}

@test "forge-exec: logs older than 7 days are pruned" {
  mkdir -p context/.runs; touch -t 202001010000 context/.runs/old.log
  bash "$EXEC" 'true' >/dev/null
  [ ! -f context/.runs/old.log ]
}
