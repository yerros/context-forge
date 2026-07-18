#!/usr/bin/env bats
# forge-lock.sh — portable locks + in-place unit claims.

load helpers/common

FORGE_LOCK() { bash "$PLUGIN_ROOT/skills/forge-worktree/scripts/forge-lock.sh" "$@"; }

setup() {
  setup_project
  init_git
  printf 'x\n' > README.md
  commit_all
}

@test "lock: acquire and release" {
  run FORGE_LOCK lock tracker
  [ "$status" -eq 0 ]
  [ -d .git/forge-locks/tracker.lock ]
  run FORGE_LOCK unlock tracker
  [ ! -d .git/forge-locks/tracker.lock ]
}

@test "lock: second acquire fails while held, names the holder" {
  FORGE_LOCK lock tracker
  run FORGE_LOCK lock tracker
  [ "$status" -ne 0 ]
  [[ "$output" == *'HELD'* ]]
  [[ "$output" == *'pid='* ]]
}

@test "lock: --wait retries until the lock frees" {
  FORGE_LOCK lock tracker
  ( sleep 2; FORGE_LOCK unlock tracker ) &
  run FORGE_LOCK lock tracker --wait 10
  [ "$status" -eq 0 ]
  wait
}

@test "lock: --steal takes over" {
  FORGE_LOCK lock tracker
  run FORGE_LOCK lock tracker --steal
  [ "$status" -eq 0 ]
}

@test "lock: unlock when not locked is a no-op, exit 0" {
  run FORGE_LOCK unlock never-held
  [ "$status" -eq 0 ]
}

@test "lock: invalid name is rejected (path safety)" {
  run FORGE_LOCK lock '../evil'
  [ "$status" -ne 0 ]
  [ ! -e .git/forge-locks/../evil.lock ] || true
  [ ! -e .git/evil.lock ]
}

@test "lock: without git repo it refuses cleanly" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p nogit && cd nogit
  run FORGE_LOCK lock tracker
  [ "$status" -ne 0 ]
  [[ "$output" == *'not inside a git repository'* ]]
}

@test "claim: in-place claim is atomic; double claim loses" {
  run FORGE_LOCK claim 4 "in-place build"
  [ "$status" -eq 0 ]
  grep -q 'mode=build' .git/forge-claims/04
  run FORGE_LOCK claim 4
  [ "$status" -ne 0 ]
  [[ "$output" == *'ALREADY CLAIMED'* ]]
}

@test "claim: shares the claims dir with forge-worktree (cross-flow conflict)" {
  bash "$WORKTREE" new 5 wt-first >/dev/null
  run FORGE_LOCK claim 5
  [ "$status" -ne 0 ]
  [[ "$output" == *'ALREADY CLAIMED'* ]]
}

@test "claim: release refuses a worktree-owned claim" {
  bash "$WORKTREE" new 6 wt-owned >/dev/null
  run FORGE_LOCK release 6
  [ "$status" -ne 0 ]
  [[ "$output" == *'forge-worktree'* ]]
  [ -f .git/forge-claims/06 ]
}

@test "claim: release frees an in-place claim" {
  FORGE_LOCK claim 7
  run FORGE_LOCK release 7
  [ "$status" -eq 0 ]
  [ ! -f .git/forge-claims/07 ]
}

@test "status: shows locks and claims together" {
  FORGE_LOCK lock tracker
  FORGE_LOCK claim 9
  run FORGE_LOCK status
  [[ "$output" == *'lock  tracker'* ]]
  [[ "$output" == *'claim unit 09'* ]]
}

@test "status: empty state says so" {
  run FORGE_LOCK status
  [[ "$output" == *'no locks, no claims'* ]]
}

@test "lock: concurrent contenders — exactly one wins" {
  n=8
  pids=""
  for i in $(seq 1 $n); do
    ( FORGE_LOCK lock race >/dev/null 2>&1 && echo "$i" >> winners.txt ) &
    pids="$pids $!"
  done
  for p in $pids; do wait "$p" || true; done
  [ -f winners.txt ]
  [ "$(wc -l < winners.txt | tr -d ' ')" -eq 1 ]
}
