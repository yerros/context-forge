#!/usr/bin/env bats
# SessionStart hook (hooks/scripts/team-sync.sh) — team knowledge sync.
# A bare "origin" repo stands in for the remote; a second clone plays the teammate.

load helpers/common

TEAM_SYNC="$PLUGIN_ROOT/hooks/scripts/team-sync.sh"

setup() { setup_project; }

# Project with a forge context, pushed to a bare origin; origin/HEAD resolvable.
mk_team_repo() {
  init_git
  mkdir -p context
  printf 'digest\n' > context/context-digest.md
  printf '# Lessons\n\n- [old] first lesson\n' > context/lessons.md
  commit_all
  git init -q --bare -b main "$BATS_TEST_TMPDIR/origin.git" 2>/dev/null \
    || { git init -q --bare "$BATS_TEST_TMPDIR/origin.git"; git --git-dir="$BATS_TEST_TMPDIR/origin.git" symbolic-ref HEAD refs/heads/main; }
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git push -q -u origin main
  git remote set-head origin main
}

# Teammate commits $1 to lessons.md on main and pushes.
teammate_adds_lesson() {
  local mate="$BATS_TEST_TMPDIR/mate"
  git clone -q -b main "$BATS_TEST_TMPDIR/origin.git" "$mate"
  ( cd "$mate" \
    && git config user.email "mate@context-forge.invalid" \
    && git config user.name "Mate" \
    && printf '%s\n' "$1" >> context/lessons.md \
    && git commit -qam "lesson from mate" && git push -q origin main )
}

@test "team-sync: non-forge project stays silent" {
  init_git
  run bash "$TEAM_SYNC" --no-fetch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team-sync: forge project without a remote stays silent" {
  init_git; mkdir -p context; printf 'd\n' > context/context-digest.md; commit_all
  run bash "$TEAM_SYNC" --no-fetch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team-sync: first run sets the watermark and prints nothing" {
  mk_team_repo
  run bash "$TEAM_SYNC" --no-fetch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(ls "$HOME/.context-forge/team-sync" | wc -l)" -eq 1 ]
}

@test "team-sync: teammate lesson on origin is reported once, then quiet" {
  mk_team_repo
  bash "$TEAM_SYNC" --no-fetch
  teammate_adds_lesson '- [mate-rule] never mock the clock'
  git fetch -q origin
  run bash "$TEAM_SYNC" --no-fetch
  [ "$status" -eq 0 ]
  [[ "$output" == *'[Context Forge] Team sync'* ]]
  [[ "$output" == *'never mock the clock'* ]]
  [[ "$output" != *'first lesson'* ]]          # unchanged lines are not repeated
  run bash "$TEAM_SYNC" --no-fetch
  [ -z "$output" ]                              # watermark advanced
}

@test "team-sync: commits that touch no knowledge file stay silent" {
  mk_team_repo
  bash "$TEAM_SYNC" --no-fetch
  printf 'code\n' > app.ts; commit_all; git push -q origin main; git fetch -q origin
  run bash "$TEAM_SYNC" --no-fetch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team-sync: watermark lives under \$HOME, never in the repo" {
  mk_team_repo
  bash "$TEAM_SYNC" --no-fetch
  [ -z "$(git status --porcelain)" ]
}

@test "team-sync: real fetch against a local bare origin works end to end" {
  mk_team_repo
  bash "$TEAM_SYNC"
  teammate_adds_lesson '- [mate-rule] fetched lesson'
  run bash "$TEAM_SYNC"
  [ "$status" -eq 0 ]
  [[ "$output" == *'fetched lesson'* ]]
}
