#!/usr/bin/env bats
# Stop hook (hooks/scripts/track.sh) — activity recorder + budget guard.

load helpers/common

setup() { setup_project; }

mk_tracker() { # $1 = context dir
  mkdir -p "$1"
  printf '# Progress Tracker\n\n## In Progress\n\n- unit 01\n' > "$1/progress-tracker.md"
}

@test "track: no tracker -> exits 0, writes nothing" {
  init_git
  run bash "$TRACK"
  [ "$status" -eq 0 ]
  [ ! -f context/.last-session.md ]
  [ ! -f .forge/.last-session.md ]
}

@test "track: tracker without git repo -> exits 0, writes nothing" {
  mk_tracker context
  run bash "$TRACK"
  [ "$status" -eq 0 ]
  [ ! -f context/.last-session.md ]
}

@test "track: never writes to stdout" {
  init_git; mk_tracker context; commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "track: uncommitted code change -> .last-session.md lists it" {
  init_git; mk_tracker context; commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  [ -f context/.last-session.md ]
  grep -q 'app.ts' context/.last-session.md
  grep -q 'progress-tracker' context/.last-session.md   # the reminder line
}

@test "track: tracker-only change -> no activity file" {
  init_git; mk_tracker context; commit_all
  printf 'edit\n' >> context/progress-tracker.md
  run bash "$TRACK"
  [ ! -f context/.last-session.md ]
}

@test "track: .forge dir is resolved and used for output" {
  init_git; mk_tracker .forge; commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  [ -f .forge/.last-session.md ]
  [ ! -f context/.last-session.md ]
}

@test "track: empty (0-byte) tracker still works" {
  init_git
  mkdir -p context
  : > context/progress-tracker.md
  commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  [ "$status" -eq 0 ]
  [ -f context/.last-session.md ]
}

@test "track: over-budget tracker is reported" {
  init_git
  mkdir -p context
  write_bytes context/progress-tracker.md 7000     # budget 6144
  commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  grep -q 'progress-tracker.md is 7000 bytes' context/.last-session.md
}

@test "track: under-budget files produce no budget section" {
  init_git; mk_tracker context; commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  ! grep -q 'over their token budget' context/.last-session.md
}

@test "track: over-budget module context is reported" {
  init_git; mk_tracker context
  mkdir -p context/modules
  write_bytes context/modules/api.md 9000          # budget 8192
  commit_all
  printf 'change\n' > app.ts
  run bash "$TRACK"
  grep -q 'modules/api.md' context/.last-session.md
}

@test "track: activity file is overwritten, never appended" {
  init_git; mk_tracker context; commit_all
  printf 'change\n' > app.ts
  bash "$TRACK"
  size1=$(wc -c < context/.last-session.md)
  bash "$TRACK"
  size2=$(wc -c < context/.last-session.md)
  [ "$size1" -eq "$size2" ]
}
