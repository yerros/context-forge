#!/usr/bin/env bats
# PreToolUse guard (hooks/scripts/guard.sh) — deterministic deny/allow.

load helpers/common

setup() { setup_project; }

tool_json() { # $1 = file path to embed
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1"
}

@test "guard: payload without file_path is allowed silently" {
  run bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard: empty stdin is allowed silently (corrupt payload)" {
  run bash "$GUARD" <<< ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard: non-JSON garbage on stdin does not crash" {
  run bash "$GUARD" <<< 'not json at all %%%'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard: node_modules paths are denied" {
  run bash "$GUARD" <<< "$(tool_json "$PWD/node_modules/lib/index.js")"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "guard: .git internals are denied" {
  run bash "$GUARD" <<< "$(tool_json ".git/config")"
  [[ "$output" == *'"deny"'* ]]
}

@test "guard: lock files are denied (package-lock.json, *.lock)" {
  run bash "$GUARD" <<< "$(tool_json "package-lock.json")"
  [[ "$output" == *'"deny"'* ]]
  run bash "$GUARD" <<< "$(tool_json "sub/dir/Cargo.lock")"
  [[ "$output" == *'"deny"'* ]]
}

@test "guard: deny output is valid JSON" {
  run bash "$GUARD" <<< "$(tool_json "yarn.lock")"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "guard: ordinary source file is allowed" {
  run bash "$GUARD" <<< "$(tool_json "src/index.ts")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard: protected-paths relative glob matches an absolute tool path" {
  mkdir -p context
  printf 'src/generated/*\n' > context/protected-paths
  run bash "$GUARD" <<< "$(tool_json "$PWD/src/generated/api.ts")"
  [[ "$output" == *'"deny"'* ]]
}

@test "guard: protected-paths basename glob matches anywhere" {
  mkdir -p context
  printf '*.generated.ts\n' > context/protected-paths
  run bash "$GUARD" <<< "$(tool_json "deep/nested/dir/schema.generated.ts")"
  [[ "$output" == *'"deny"'* ]]
}

@test "guard: comment and blank lines in protected-paths are ignored" {
  mkdir -p context
  printf '# a comment\n\nsrc/generated/*\n' > context/protected-paths
  run bash "$GUARD" <<< "$(tool_json "README.md")"
  [ -z "$output" ]
}

@test "guard: .forge/protected-paths wins over context/protected-paths" {
  mkdir -p context .forge
  printf 'never-matches-anything-xyz\n' > context/protected-paths
  printf 'docs/*\n' > .forge/protected-paths
  run bash "$GUARD" <<< "$(tool_json "docs/index.md")"
  [[ "$output" == *'"deny"'* ]]
}

@test "guard: empty protected-paths file allows everything" {
  mkdir -p context
  : > context/protected-paths
  run bash "$GUARD" <<< "$(tool_json "src/app.ts")"
  [ -z "$output" ]
}

@test "guard: protected-paths with CRLF / junk bytes does not crash" {
  mkdir -p context
  printf 'src/generated/*\r\n\003\007junk\n' > context/protected-paths
  run bash "$GUARD" <<< "$(tool_json "src/app.ts")"
  [ "$status" -eq 0 ]
}

@test "guard: notebook_path is honored too" {
  run bash "$GUARD" <<< '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"node_modules/x/nb.ipynb"}}'
  [[ "$output" == *'"deny"'* ]]
}
