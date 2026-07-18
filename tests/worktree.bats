#!/usr/bin/env bats
# forge-worktree.sh — parallel-build claims and worktree lifecycle.

load helpers/common

setup() {
  setup_project
  # The script creates sibling dirs (../repo-uNN), so give the repo its own parent.
  REPO="$BATS_TEST_TMPDIR/wt/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  init_git
  printf 'hello\n' > README.md
  commit_all "init"
}

@test "worktree: new claims the unit, creates branch + worktree" {
  run bash "$WORKTREE" new 3 invoice-crud
  [ "$status" -eq 0 ]
  [ -f .git/forge-claims/03 ]
  grep -q 'branch=feat/03-invoice-crud' .git/forge-claims/03
  [ -d "$BATS_TEST_TMPDIR/wt/repo-u03" ]
  git -C "$BATS_TEST_TMPDIR/wt/repo-u03" rev-parse --abbrev-ref HEAD | grep -q 'feat/03-invoice-crud'
}

@test "worktree: double claim loses cleanly" {
  bash "$WORKTREE" new 3 first
  run bash "$WORKTREE" new 3 second
  [ "$status" -ne 0 ]
  [[ "$output" == *'ALREADY CLAIMED'* ]]
  # The original claim is untouched.
  grep -q 'branch=feat/03-first' .git/forge-claims/03
}

@test "worktree: claim rolls back when worktree creation fails" {
  git branch feat/04-taken
  run bash "$WORKTREE" new 4 taken
  [ "$status" -ne 0 ]
  [ ! -f .git/forge-claims/04 ]
}

@test "worktree: non-numeric unit is rejected" {
  run bash "$WORKTREE" new abc slug
  [ "$status" -ne 0 ]
  [ ! -d .git/forge-claims ] || [ -z "$(ls -A .git/forge-claims)" ]
}

@test "worktree: list shows active claims" {
  bash "$WORKTREE" new 5 listing
  run bash "$WORKTREE" list
  [[ "$output" == *'unit 05'* ]]
}

@test "worktree: done refuses a dirty worktree" {
  bash "$WORKTREE" new 6 dirty
  printf 'wip\n' > "$BATS_TEST_TMPDIR/wt/repo-u06/wip.txt"
  run bash "$WORKTREE" done 6
  [ "$status" -ne 0 ]
  [[ "$output" == *'uncommitted changes'* ]]
  [ -f .git/forge-claims/06 ]
  [ -d "$BATS_TEST_TMPDIR/wt/repo-u06" ]
}

@test "worktree: done releases a clean worktree and its claim" {
  bash "$WORKTREE" new 7 clean
  run bash "$WORKTREE" done 7
  [ "$status" -eq 0 ]
  [ ! -f .git/forge-claims/07 ]
  [ ! -d "$BATS_TEST_TMPDIR/wt/repo-u07" ]
}

@test "worktree: claims are visible from inside a linked worktree" {
  bash "$WORKTREE" new 8 shared
  cd "$BATS_TEST_TMPDIR/wt/repo-u08"
  run bash "$WORKTREE" list
  [[ "$output" == *'unit 08'* ]]
}
