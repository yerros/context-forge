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
