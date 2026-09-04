#!/usr/bin/env bats
# rules-check.sh — forge-review step 0: deterministic rule patterns over changed files.

load helpers/common

RULES_CHECK="$PLUGIN_ROOT/skills/forge-review/scripts/rules-check.sh"

setup() {
  setup_project
  init_git
  mkdir -p context src
  printf '# rules\nCS-010|Critical|*.ts|No any|:\\s*any\\b\nCS-030|Important|*.css|Raw hex|#[0-9a-fA-F]{3,8}\\b\nCS-090|Important|*|log or warn|console\\.(log|warn)\\(\n' > context/rules.txt
}

@test "rules-check: no rules file -> exit 0, says so" {
  rm context/rules.txt
  run bash "$RULES_CHECK" src/x.ts
  [ "$status" -eq 0 ]
  [[ "$output" == *'no rules.txt'* ]]
}

@test "rules-check: hit reports file:line ID [Severity] message, exit 1" {
  printf 'const a = 1;\nfunction f(x: any) {}\n' > src/x.ts
  run bash "$RULES_CHECK" src/x.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/x.ts:2: CS-010 [Critical] No any'* ]]
}

@test "rules-check: glob scopes the rule to matching files" {
  printf 'x: any\n' > src/notes.md
  run bash "$RULES_CHECK" src/notes.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'clean'* ]]
}

@test "rules-check: regex containing | (alternation) survives the field split" {
  printf 'console.warn("x")\n' > src/y.ts
  run bash "$RULES_CHECK" src/y.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'CS-090'* ]]
}

@test "rules-check: no args -> changed files vs HEAD incl. untracked" {
  printf 'clean\n' > src/base.ts; commit_all
  printf 'color: #fff;\n' > src/new.css
  run bash "$RULES_CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/new.css:1: CS-030'* ]]
  [[ "$output" != *'base.ts'* ]]
}

@test "rules-check: --base scopes to ref...HEAD" {
  printf 'clean\n' > src/base.ts; commit_all
  git tag base
  printf 'x: any\n' > src/z.ts; commit_all "z"
  printf 'x: any\n' > src/untracked.ts
  run bash "$RULES_CHECK" --base base
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/z.ts:1: CS-010'* ]]
  [[ "$output" != *'untracked.ts'* ]]
}

@test "rules-check: .forge/rules.txt wins over context/" {
  mkdir -p .forge
  printf 'CS-001|Critical|*|forge rule|TODO\n' > .forge/rules.txt
  printf 'TODO later\n' > src/t.ts
  run bash "$RULES_CHECK" src/t.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'CS-001 [Critical] forge rule'* ]]
}

@test "rules-check: malformed rule line -> exit 2 with the ID" {
  printf 'CS-999|Critical|only three\n' > context/rules.txt
  printf 'x\n' > src/x.ts
  run bash "$RULES_CHECK" src/x.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *'CS-999'* ]]
}

@test "rules-check: bundled golden case 05 is caught by its own rules.txt" {
  cp -R "$PLUGIN_ROOT/skills/forge-calibrate/golden/05-standards-rule/context" .
  cp -R "$PLUGIN_ROOT/skills/forge-calibrate/golden/05-standards-rule/after/src" .
  run bash "$RULES_CHECK" src/api.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/api.ts:4: CS-003 [Important]'* ]]
}
