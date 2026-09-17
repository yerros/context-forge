#!/usr/bin/env bats
# forge-security-audit: the vendored Cloudflare validators (scripts/*.cjs) — upstream
# node:test suites must pass as shipped, the CLI contract must hold, and every
# companion SKILL.md links to must exist in references/.

load helpers/common

SA="$PLUGIN_ROOT/skills/forge-security-audit"

setup() {
  setup_project
  command -v node >/dev/null 2>&1 || skip "node not installed"
}

@test "security-audit: upstream validate-findings suite passes" {
  run node "$SA/scripts/validate-findings.test.cjs"
  [ "$status" -eq 0 ]
}

@test "security-audit: upstream validate-coverage-ledger suite passes" {
  run node "$SA/scripts/validate-coverage-ledger.test.cjs"
  [ "$status" -eq 0 ]
}

@test "security-audit: validators reject malformed input with a non-zero exit" {
  printf 'not json' > bad.json
  run node "$SA/scripts/validate-findings.cjs" bad.json
  [ "$status" -ne 0 ]
  run node "$SA/scripts/validate-coverage-ledger.cjs" bad.json
  [ "$status" -ne 0 ]
  run node "$SA/scripts/validate-findings.cjs"
  [ "$status" -ne 0 ]
  [[ "$output" == *Usage* ]]
}

@test "security-audit: every companion linked from SKILL.md exists" {
  run grep -oE '\]\(references/[A-Z-]+\.md\)' "$SA/SKILL.md"
  [ -n "$output" ]
  for link in $(printf '%s\n' "$output" | sed -E 's/^\]\((.*)\)$/\1/' | sort -u); do
    [ -f "$SA/$link" ] || { echo "missing $link"; return 1; }
  done
  for f in validate-findings.cjs validate-coverage-ledger.cjs report-schema.json; do
    [ -f "$SA/scripts/$f" ]
  done
}

@test "plan-rank: groups by subsystem+boundary, tool hits and low-trust rank first" {
  cat > ledger.json <<'JSON'
[
 {"coverage_id":"a1","subsystem":"packages/api","boundary":"src/authz.ts#requireOwner","surface":"POST /users/:id","starting_paths":["src/users"],"status":"planned"},
 {"coverage_id":"a2","subsystem":"packages/api","boundary":"src/authz.ts#requireOwner","surface":"DELETE /users/:id","starting_paths":["src/users"],"status":"planned"},
 {"coverage_id":"b1","subsystem":"packages/api","boundary":"unauthenticated","surface":"POST /login","starting_paths":["src/auth"],"status":"planned"},
 {"coverage_id":"c1","subsystem":"packages/worker","boundary":"queue","surface":"job","starting_paths":["src/jobs"],"status":"out_of_scope"}
]
JSON
  printf 'src/users/update.ts:12: GK-020 [Important] string-built SQL\nsrc/users/update.ts:40: GK-020 [Important] string-built SQL\nsecurity-check: 2 hits\n' > hits.log
  run node "$SA/scripts/plan-rank.cjs" ledger.json --hits hits.log
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == '#  | Subsystem / boundary | Units | Est. agents | Why first' ]]
  [[ "${lines[1]}" == *'requireOwner | 2 | 2-3 | 2 tool hits'* ]]   # 2 hits x3 = 6 beats low-trust 5
  [[ "${lines[2]}" == *'unauthenticated | 1 | 1-2 | low-trust surface'* ]]
  [[ "$output" != *'packages/worker'* ]]                             # out_of_scope dropped
  [[ "$output" == *'total: 2 targets, 3 units'* ]]
  run node "$SA/scripts/plan-rank.cjs" ledger.json --hits hits.log --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(r.length, r[0].score, r[1].low_trust)')" = "2 6 true" ]
}

@test "plan-rank: bad input exits non-zero, no args prints usage" {
  printf 'nope' > bad.json
  run node "$SA/scripts/plan-rank.cjs" bad.json
  [ "$status" -eq 1 ]
  run node "$SA/scripts/plan-rank.cjs"
  [ "$status" -eq 2 ]
  [[ "$output" == *Usage* ]]
}
