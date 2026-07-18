#!/usr/bin/env bats
# migrate-schema.sh — schema stamping and stepwise migration.

load helpers/common

MIGRATE() { bash "$PLUGIN_ROOT/skills/forge-init/scripts/migrate-schema.sh" "$@"; }

mk_core() { # $1 = context dir
  mkdir -p "$1"
  for f in project-overview architecture code-standards ai-workflow-rules progress-tracker; do
    printf '# %s\n' "$f" > "$1/$f.md"
  done
}

setup() { setup_project; }

@test "schema: refuses a project with no context files" {
  run MIGRATE
  [ "$status" -ne 0 ]
  [[ "$output" == *'forge-init'* ]]
}

@test "schema: pre-schema project is stamped to current" {
  mk_core context
  run MIGRATE
  [ "$status" -eq 0 ]
  [ -f context/.schema-version ]
  [ "$(cat context/.schema-version)" = "1" ]
}

@test "schema: idempotent — second run is a no-op" {
  mk_core context
  MIGRATE
  run MIGRATE
  [ "$status" -eq 0 ]
  [[ "$output" == *'already current'* ]]
}

@test "schema: --dry-run writes nothing" {
  mk_core context
  run MIGRATE --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'would: stamp'* ]]
  [ ! -f context/.schema-version ]
}

@test "schema: refuses to stamp a half-set-up project" {
  mkdir -p context
  printf '# only one file\n' > context/project-overview.md
  run MIGRATE
  [ "$status" -ne 0 ]
  [[ "$output" == *'core files missing'* ]]
}

@test "schema: .forge dir is resolved" {
  mk_core .forge
  run MIGRATE
  [ "$status" -eq 0 ]
  [ -f .forge/.schema-version ]
}

@test "schema: newer-than-known schema is refused (downgrade guard)" {
  mk_core context
  printf '99\n' > context/.schema-version
  run MIGRATE
  [ "$status" -ne 0 ]
  [[ "$output" == *'update the plugin'* ]]
}

@test "schema: corrupt marker is refused with a clear message" {
  mk_core context
  printf 'banana\n' > context/.schema-version
  run MIGRATE
  [ "$status" -ne 0 ]
  [[ "$output" == *'no number'* ]]
}

@test "schema: detect.sh reports pre-schema then the stamped version" {
  mk_core context
  run bash "$DETECT"
  [[ "$output" == *'schema: pre-schema'* ]]
  MIGRATE
  run bash "$DETECT"
  [[ "$output" == *'schema: 1'* ]]
}
