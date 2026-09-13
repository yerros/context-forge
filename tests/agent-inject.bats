#!/usr/bin/env bats
# PreToolUse Agent/Task prompt injection (hooks/scripts/agent-inject.sh).

load helpers/common

INJECT="$PLUGIN_ROOT/hooks/scripts/agent-inject.sh"

setup() {
  setup_project
  command -v python3 >/dev/null || skip "python3 not installed"
  mkdir -p context
  printf 'digest\n' > context/context-digest.md
}

payload() { printf '{"tool_name":"Agent","tool_input":{"subagent_type":"forge-architect","prompt":%s}}' "$1"; }

@test "agent-inject: no digest -> passthrough" {
  rm context/context-digest.md
  run bash "$INJECT" <<< "$(payload '"plan unit 3"')"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "agent-inject: appends the Tier-1 pointer and keeps every other field" {
  run bash "$INJECT" <<< "$(payload '"plan unit 3"')"
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])["hookSpecificOutput"]
assert d["hookEventName"] == "PreToolUse"
ui = d["updatedInput"]
assert ui["subagent_type"] == "forge-architect"
assert ui["prompt"].startswith("plan unit 3\n\n[Context Forge]")
assert "context/context-digest.md" in ui["prompt"]
PY
}

@test "agent-inject: prompt with JSON-hostile characters survives the round-trip" {
  run bash "$INJECT" <<< "$(payload '"say \"hi\" \\ newline\n tab\t ünïcode"')"
  python3 - "$output" <<'PY'
import json, sys
p = json.loads(sys.argv[1])["hookSpecificOutput"]["updatedInput"]["prompt"]
assert p.startswith('say "hi" \\ newline\n tab\t ünïcode')
PY
}

@test "agent-inject: prompt already carrying the marker is left alone" {
  run bash "$INJECT" <<< "$(payload '"[Context Forge] already briefed"')"
  [ -z "$output" ]
}

@test "agent-inject: .forge/ layout names .forge/ in the pointer" {
  mv context .forge
  printf 'tracker\n' > .forge/progress-tracker.md
  run bash "$INJECT" <<< "$(payload '"x"')"
  [[ "$output" == *'.forge/context-digest.md'* ]]
}

@test "agent-inject: garbage or promptless payloads are ignored" {
  run bash "$INJECT" <<< 'not json'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$INJECT" <<< '{"tool_name":"Agent","tool_input":{"subagent_type":"x"}}'
  [ -z "$output" ]
}
