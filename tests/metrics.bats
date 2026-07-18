#!/usr/bin/env bats
# metrics.sh + forge-stats.sh — opt-in local metrics (never telemetry).

load helpers/common

METRICS="$PLUGIN_ROOT/hooks/scripts/metrics.sh"
STATS="$PLUGIN_ROOT/hooks/scripts/forge-stats.sh"

setup() {
  setup_project
  MDIR="$HOME/.claude/forge-metrics"
}

enable_metrics() { mkdir -p "$MDIR"; touch "$MDIR/enabled"; }

@test "metrics: disabled by default — records nothing" {
  run bash "$METRICS" record skill_invoked skill=forge-build
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$MDIR/events.ndjson" ]
}

@test "metrics: enabled — appends one valid JSON line" {
  enable_metrics
  bash "$METRICS" record skill_invoked skill=forge-build
  [ "$(wc -l < "$MDIR/events.ndjson" | tr -d ' ')" -eq 1 ]
  jq -e '.event == "skill_invoked" and .skill == "forge-build" and (.ts | length) > 0' \
    < "$MDIR/events.ndjson" >/dev/null
}

@test "metrics: records only the project basename, not the full path" {
  enable_metrics
  bash "$METRICS" record skill_invoked
  proj=$(jq -r '.project' < "$MDIR/events.ndjson")
  [ "$proj" = "project" ]
  ! grep -qF "$BATS_TEST_TMPDIR" "$MDIR/events.ndjson"
}

@test "metrics: values with quotes are escaped, line stays valid JSON" {
  enable_metrics
  bash "$METRICS" record test_event 'note=say "hi" \ there'
  jq -e . < "$MDIR/events.ndjson" >/dev/null
}

@test "metrics: malformed key=value pairs are skipped, not fatal" {
  enable_metrics
  run bash "$METRICS" record test_event 'bad key=x' '=nokey' 'ok=1'
  [ "$status" -eq 0 ]
  jq -e '.ok == "1"' < "$MDIR/events.ndjson" >/dev/null
}

@test "metrics: skill-status capture records skill_invoked when enabled" {
  enable_metrics
  bash "$SKILL_STATUS" capture <<< '{"session_id":"m1","command_name":"forge-fix"}'
  jq -e 'select(.event=="skill_invoked") | .skill == "forge-fix"' \
    < "$MDIR/events.ndjson" >/dev/null
}

@test "metrics: track.sh records stop_with_changes when enabled" {
  enable_metrics
  init_git
  mkdir -p context
  printf '# t\n' > context/progress-tracker.md
  commit_all
  printf 'x\n' > app.ts
  bash "$TRACK"
  jq -e 'select(.event=="stop_with_changes") | .changed_files == "1"' \
    < "$MDIR/events.ndjson" >/dev/null
}

@test "stats: no data yet -> friendly hint, exit 0" {
  run bash "$STATS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'no metrics recorded'* ]]
}

@test "stats: aggregates by event, skill, project" {
  enable_metrics
  bash "$METRICS" record skill_invoked skill=forge-build
  bash "$METRICS" record skill_invoked skill=forge-build
  bash "$METRICS" record skill_invoked skill=forge-debug
  run bash "$STATS" 7
  [ "$status" -eq 0 ]
  [[ "$output" == *'forge-build'*'2'* ]]
  [[ "$output" == *'debug pressure: 1 forge-debug per 2 forge-build'* ]]
}

@test "stats: old events fall outside the window" {
  enable_metrics
  printf '{"ts":"2001-01-01T00:00:00","event":"skill_invoked","project":"p","skill":"forge-build"}\n' \
    >> "$MDIR/events.ndjson"
  run bash "$STATS" 7
  [[ "$output" == *'0 events'* ]] || [[ "$output" == *'nothing recorded'* ]]
}
