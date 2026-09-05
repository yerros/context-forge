#!/usr/bin/env bats
# security-check.sh — forge-gatekeeper step 0: deterministic security gate.

load helpers/common

SEC_CHECK="$PLUGIN_ROOT/skills/forge-gatekeeper/scripts/security-check.sh"

setup() {
  setup_project
  init_git
  mkdir -p src context
  export ECC_SKIP_PRECOMMIT=1   # a global pre-commit secret hook would otherwise block fixture commits
}

@test "security-check: clean file -> exit 0, says clean" {
  printf 'export const x = 1;\n' > src/ok.ts
  run bash "$SEC_CHECK" src/ok.ts
  [ "$status" -eq 0 ]
  [[ "$output" == *'security-check: clean'* ]]
}

@test "security-check: hardcoded credential assignment -> GK-010 Critical, exit 1" {
  printf 'const password = "hunter2hunter2";\n' > src/cfg.ts
  run bash "$SEC_CHECK" src/cfg.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/cfg.ts:1: GK-010 [Critical]'* ]]
}

@test "security-check: live token literal -> GK-013 even inside a test file" {
  mkdir -p src/__tests__
  printf 'const k = "sk_live_FAKE0000GATE0000TEST";\n' > src/__tests__/m.test.ts
  run bash "$SEC_CHECK" src/__tests__/m.test.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'GK-013'* ]]
}

@test "security-check: generic secret + console.log skipped in test files (gitleaks territory)" {
  mkdir -p src/__tests__
  printf 'const password = "hunter2hunter2";\nconsole.log("x");\n' > src/__tests__/m.test.ts
  run bash "$SEC_CHECK" src/__tests__/m.test.ts
  [ "$status" -eq 0 ]
}

@test "security-check: tracked .env -> GK-001; .env.example is fine" {
  printf 'DB=x\n' > .env; printf 'DB=\n' > .env.example; printf 'ok\n' > src/a.ts
  commit_all
  run bash "$SEC_CHECK" --all
  [ "$status" -eq 1 ]
  [[ "$output" == *'.env:1: GK-001 [Critical]'* ]]
  [[ "$output" != *'.env.example:'* ]]
}

@test "security-check: dangerous sinks by language glob (SQL concat, innerHTML, shell=True, yaml.load)" {
  printf 'db.q("SELECT * FROM t WHERE id = " + id);\nel.innerHTML = x;\n' > src/a.ts
  printf 'subprocess.run(c, shell=True)\nyaml.load(f)\nsafe = yaml.load(f, Loader=yaml.SafeLoader)\n' > src/b.py
  run bash "$SEC_CHECK" src/a.ts src/b.py
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/a.ts:1: GK-035'* ]]
  [[ "$output" == *'src/a.ts:2: GK-034'* ]]
  [[ "$output" == *'src/b.py:1: GK-032'* ]]
  [[ "$output" == *'src/b.py:2: GK-033'* ]]
  [[ "$output" != *'src/b.py:3:'* ]]
}

@test "security-check: python rules do not fire on .ts and vice versa" {
  printf 'print("hi")\n' > src/a.ts
  printf 'console.log("hi")\n' > src/b.py
  run bash "$SEC_CHECK" src/a.ts src/b.py
  [ "$status" -eq 0 ]
}

@test "security-check: project security-rules.txt is appended to the built-ins" {
  printf 'GK-901|Critical|*.ts|No raw fetch — use apiClient|\\bfetch\\(\n' > context/security-rules.txt
  printf 'await fetch(url);\n' > src/a.ts
  run bash "$SEC_CHECK" src/a.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/a.ts:1: GK-901 [Critical] No raw fetch'* ]]
}

@test "security-check: no args -> changed files vs HEAD incl. untracked" {
  printf 'clean\n' > src/base.ts; commit_all
  printf 'const token = "abcdefghijklmnop";\n' > src/new.ts
  run bash "$SEC_CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/new.ts:1: GK-010'* ]]
  [[ "$output" != *'base.ts'* ]]
}

@test "security-check: --base scopes to <ref>...HEAD" {
  printf 'const token = "abcdefghijklmnop";\n' > src/old.ts; commit_all
  git tag base
  printf 'ok\n' > src/new.ts; commit_all "second"
  run bash "$SEC_CHECK" --base base
  [ "$status" -eq 0 ]
  [[ "$output" != *'old.ts'* ]]
}

@test "security-check: golden case 06 is caught by step 0 with the expected ID" {
  cp -R "$PLUGIN_ROOT/skills/forge-calibrate/golden/06-hardcoded-secret/after/src" .
  run bash "$SEC_CHECK" src/mailer.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *'src/mailer.ts:5: GK-013'* ]]
}

@test "security-check: reports which external tools are missing, never fatal" {
  printf 'ok\n' > src/a.ts
  PATH="/usr/bin:/bin" run bash "$SEC_CHECK" src/a.ts
  [ "$status" -eq 0 ]
  [[ "$output" == *'not installed, skipped:'* ]]
}
