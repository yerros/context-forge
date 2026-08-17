#!/usr/bin/env bats
# Antigravity adapter (hooks/antigravity/agy-hook.sh) + build
# (scripts/build-antigravity.sh) — payload translation, decisions, injection.
#
# The adapter is tested straight from the repo (it only needs hooks/scripts/
# relative to itself, which holds in-repo and in the built bundle alike).

load helpers/common

AGY="$PLUGIN_ROOT/hooks/antigravity/agy-hook.sh"
BUILD="$PLUGIN_ROOT/scripts/build-antigravity.sh"

setup() { setup_project; }

# --- payload builders (Antigravity camelCase shape) --------------------------

agy_tool() { # $1=tool $2=extra args JSON (e.g. '"TargetFile":"/x"')
  printf '{"conversationId":"agy-test-1","workspacePaths":["%s"],"toolCall":{"name":"%s","args":{%s}},"stepIdx":1}' \
    "$PROJECT_DIR" "$1" "$2"
}

# --- PreToolUse --------------------------------------------------------------

@test "agy: lock-file write is denied with a reason" {
  run bash "$AGY" PreToolUse <<< "$(agy_tool write_to_file "\"TargetFile\":\"$PROJECT_DIR/package-lock.json\"")"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"deny"'* ]]
  [[ "$output" == *'lock files are generated'* ]]
}

@test "agy: protected-paths globs deny via the same guard" {
  mkdir -p context
  printf 'src/generated/*\n' > context/protected-paths
  run bash "$AGY" PreToolUse <<< "$(agy_tool replace_file_content "\"TargetFile\":\"$PROJECT_DIR/src/generated/api.ts\"")"
  [[ "$output" == *'"decision":"deny"'* ]]
}

@test "agy: ordinary edits pass through as ask (default gating)" {
  run bash "$AGY" PreToolUse <<< "$(agy_tool replace_file_content "\"TargetFile\":\"$PROJECT_DIR/src/app.js\"")"
  [ "$status" -eq 0 ]
  [ "$output" = '{"decision":"ask"}' ]
}

@test "agy: read-only tools never deny" {
  run bash "$AGY" PreToolUse <<< "$(agy_tool view_file "\"AbsolutePath\":\"$PROJECT_DIR/node_modules/x.js\"")"
  [ "$output" = '{"decision":"ask"}' ]
}

@test "agy: now-status records the mapped tool name" {
  bash "$AGY" PreToolUse <<< "$(agy_tool run_command "\"CommandLine\":\"npm test\",\"Cwd\":\"$PROJECT_DIR\"")" > /dev/null
  run cat "$HOME/.claude/forge-status/agy-test-1.now"
  [[ "$output" == *"	Bash	"* ]]
}

@test "agy: invoke_subagent registers a background agent entry" {
  bash "$AGY" PreToolUse <<< "$(agy_tool invoke_subagent '"Subagents":[{"Prompt":"go","TypeName":"context-forge:forge-reviewer"}]')" > /dev/null
  run cat "$HOME/.claude/forge-status/agy-test-1.agents"
  [[ "$output" == forge-reviewer\ *B* ]]
}

@test "agy: reading a SKILL.md marks the skill active" {
  bash "$AGY" PreToolUse <<< "$(agy_tool view_file '"AbsolutePath":"/plug/skills/forge-build/SKILL.md","IsSkillFile":true')" > /dev/null
  run cat "$HOME/.claude/forge-status/agy-test-1"
  [[ "$output" == active\ forge-build\ * ]]
}

# --- PostToolUse -------------------------------------------------------------

@test "agy: PostToolUse returns an empty object" {
  run bash "$AGY" PostToolUse <<< "$(agy_tool run_command '"CommandLine":"ls"')"
  [ "$output" = '{}' ]
}

# --- PreInvocation -----------------------------------------------------------

pre_invocation() { # $1=invocationNum
  printf '{"conversationId":"agy-test-1","workspacePaths":["%s"],"invocationNum":%s,"initialNumSteps":0}' \
    "$PROJECT_DIR" "$1"
}

@test "agy: first invocation injects the digest as an ephemeral step" {
  mkdir -p context
  printf '# Digest\n\nRule "A" \\ B.\n' > context/context-digest.md
  run bash "$AGY" PreInvocation <<< "$(pre_invocation 0)"
  [ "$status" -eq 0 ]
  [[ "$output" == *'injectSteps'* ]]
  [[ "$output" == *'Context Forge'* ]]
  # output must be parseable JSON even with quotes/backslashes in the digest
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "agy: .forge dir variant is honored in the injected preamble" {
  mkdir -p .forge
  printf 'digest\n' > .forge/context-digest.md
  run bash "$AGY" PreInvocation <<< "$(pre_invocation 0)"
  [[ "$output" == *'.forge/'* ]]
}

@test "agy: later invocations do not re-inject the digest" {
  mkdir -p context
  printf 'digest\n' > context/context-digest.md
  run bash "$AGY" PreInvocation <<< "$(pre_invocation 4)"
  [ "$output" = '{}' ]
}

@test "agy: non-forge project injects nothing" {
  run bash "$AGY" PreInvocation <<< "$(pre_invocation 0)"
  [ "$output" = '{}' ]
}

@test "agy: office inbox is delivered on any invocation" {
  mkdir -p "$HOME/.claude/forge-office/inbox"
  printf '{"kind":"chat","to":"main","message":"hello from dashboard","ts":"12:00"}\n' \
    > "$HOME/.claude/forge-office/inbox/$(basename "$PROJECT_DIR").ndjson"
  run bash "$AGY" PreInvocation <<< "$(pre_invocation 5)"
  [[ "$output" == *'hello from dashboard'* ]]
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

# --- Stop --------------------------------------------------------------------

stop_payload() { # $1=fullyIdle
  printf '{"conversationId":"agy-test-1","workspacePaths":["%s"],"executionNum":1,"terminationReason":"model_stop","fullyIdle":%s}' \
    "$PROJECT_DIR" "$1"
}

@test "agy: Stop allows the stop and clears the now-state" {
  bash "$AGY" PreToolUse <<< "$(agy_tool run_command '"CommandLine":"ls"')" > /dev/null
  run bash "$AGY" Stop <<< "$(stop_payload false)"
  [ "$output" = '{"decision":"ok"}' ]
  [ ! -f "$HOME/.claude/forge-status/agy-test-1.now" ]
}

@test "agy: fullyIdle Stop removes the session's agent state (SessionEnd equivalent)" {
  bash "$AGY" PreToolUse <<< "$(agy_tool invoke_subagent '"Subagents":[{"TypeName":"forge-scout"}]')" > /dev/null
  [ -f "$HOME/.claude/forge-status/agy-test-1.agents" ]
  bash "$AGY" Stop <<< "$(stop_payload true)" > /dev/null
  [ ! -f "$HOME/.claude/forge-status/agy-test-1.agents" ]
}

@test "agy: corrupt stdin still emits a safe decision" {
  run bash "$AGY" PreToolUse <<< 'not json %%%'
  [ "$status" -eq 0 ]
  [ "$output" = '{"decision":"ask"}' ]
  run bash "$AGY" Stop <<< ''
  [ "$output" = '{"decision":"ok"}' ]
}

# --- build -------------------------------------------------------------------

@test "build-antigravity: produces a valid bundle" {
  run bash "$BUILD"
  [ "$status" -eq 0 ]
  out="$PLUGIN_ROOT/dist/antigravity/context-forge"
  python3 -c "import json; json.load(open('$out/plugin.json')); json.load(open('$out/hooks.json'))"
  # strict manifest: only $schema/name/description
  run python3 -c "import json; print(sorted(json.load(open('$out/plugin.json'))))"
  [ "$output" = "['\$schema', 'description', 'name']" ]
  # agents carry Antigravity tool names and no Claude model tiers
  ! grep -rE 'model: (sonnet|opus|haiku)' "$out/agents"
  grep -q 'view_file' "$out/agents/forge-reviewer.md"
  grep -q 'subagent: true' "$out/agents/forge-reviewer.md"
  # no unsubstituted plugin-root vars anywhere in skills
  ! grep -rF '${CLAUDE_PLUGIN_ROOT}' "$out/skills"
}
