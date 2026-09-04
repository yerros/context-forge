#!/usr/bin/env bats
# score.sh — forge-calibrate: recall + agreement of reviewer runs against a golden set.

load helpers/common

SCORE="$PLUGIN_ROOT/skills/forge-calibrate/scripts/score.sh"

setup() {
  setup_project
  mkdir -p g
  printf 'errors:src/save.ts:swallowed-catch\ntests:test/u.test.ts:asserts-nothing\nspec:src/util.ts:orthogonal-edit\n# comment\n' > g/expected.txt
}

@test "score: perfect runs -> 100% recall, 100% agreement" {
  cp g/expected.txt g/run-1.txt; cp g/expected.txt g/run-2.txt
  run bash "$SCORE" g
  [ "$status" -eq 0 ]
  [[ "$output" == *'mean recall: 100%'* ]]
  [[ "$output" == *'Jaccard): 100%'* ]]
  [[ "$output" != *'never found'* ]]
}

@test "score: blind spot and unstable key are named" {
  printf 'errors:src/save.ts:swallowed-catch\nextra:src/x.ts:noise\n' > g/run-1.txt
  printf 'errors:src/save.ts:swallowed-catch\ntests:test/u.test.ts:asserts-nothing\n' > g/run-2.txt
  run bash "$SCORE" g
  [ "$status" -eq 0 ]
  [[ "$output" == *'run-1: recall 1/3 (33%) · extra 1'* ]]
  [[ "$output" == *'run-2: recall 2/3 (66%) · extra 0'* ]]
  [[ "$output" == *'never found'* ]]
  [[ "$output" == *'  spec:src/util.ts:orthogonal-edit'* ]]
  [[ "$output" == *'unstable'* ]]
  [[ "$output" == *'  tests:test/u.test.ts:asserts-nothing'* ]]
}

@test "score: agreement below 100 when runs disagree" {
  printf 'errors:src/save.ts:swallowed-catch\n' > g/run-1.txt
  printf 'tests:test/u.test.ts:asserts-nothing\n' > g/run-2.txt
  run bash "$SCORE" g
  [[ "$output" == *'Jaccard): 0%'* ]]
}

@test "score: single run -> no agreement line" {
  cp g/expected.txt g/run-1.txt
  run bash "$SCORE" g
  [[ "$output" != *'Jaccard'* ]]
}

@test "score: missing expected.txt -> usage, exit 2" {
  run bash "$SCORE" nowhere
  [ "$status" -eq 2 ]
}
