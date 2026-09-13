#!/usr/bin/env bats
# PreToolUse Bash nudge (hooks/scripts/bash-nudge.sh) — once per session, advisory only.

load helpers/common

NUDGE="$PLUGIN_ROOT/hooks/scripts/bash-nudge.sh"

setup() { setup_project; mkdir -p context; printf 't\n' > context/progress-tracker.md; }

p() { printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2:-s1}" "$1"; }

@test "bash-nudge: test runner without bounding gets one additionalContext" {
  run bash "$NUDGE" <<< "$(p 'npm test')"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"additionalContext"'* ]]
  [[ "$output" == *'forge-exec.sh'* ]]
  [[ "$output" != *'"permissionDecision"'* ]]
}

@test "bash-nudge: second runner in the same session is silent; new session fires again" {
  bash "$NUDGE" <<< "$(p 'npm test')" >/dev/null
  run bash "$NUDGE" <<< "$(p 'pytest')"
  [ -z "$output" ]
  run bash "$NUDGE" <<< "$(p 'pytest' s2)"
  [[ "$output" == *'additionalContext'* ]]
}

@test "bash-nudge: bounded commands are silent" {
  for c in 'npm test 2>&1 | tail -20' 'pytest -q' 'cargo test --quiet' 'go test ./... | grep FAIL' 'bash x/forge-exec.sh \"npm test\"' 'npx vitest run --reporter=dot'; do
    run bash "$NUDGE" <<< "$(p "$c")"
    [ -z "$output" ] || { echo "nudged: $c"; return 1; }
  done
}

@test "bash-nudge: observational commands are silent" {
  for c in 'git status' 'ls -la' 'cat package.json' 'npm install' 'make_it_so --help' 'echo test'; do
    run bash "$NUDGE" <<< "$(p "$c")"
    [ -z "$output" ] || { echo "nudged: $c"; return 1; }
  done
}

@test "bash-nudge: chained and other runners are recognized" {
  for c in 'cd app && npm run build' 'cargo build' './gradlew assembleDebug' 'go test ./...' 'make'; do
    run bash "$NUDGE" <<< "$(p "$c" "s-$RANDOM")"
    [[ "$output" == *'additionalContext'* ]] || { echo "missed: $c"; return 1; }
  done
}

@test "bash-nudge: non-forge project and garbage input stay silent" {
  rm -rf context
  run bash "$NUDGE" <<< "$(p 'npm test')"
  [ -z "$output" ]
  mkdir -p context; printf 't\n' > context/progress-tracker.md
  run bash "$NUDGE" <<< 'garbage'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
