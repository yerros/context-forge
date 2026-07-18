#!/usr/bin/env bash
# smoke.sh — run every deterministic script against one fixture type and assert
# nothing crashes. This is the CI matrix entry point:
#
#   tests/fixtures/smoke.sh <brownfield-empty|modules|no-git>
set -eu

type=${1:?usage: smoke.sh <fixture-type>}
here=$(cd "$(dirname "$0")" && pwd)
plugin_root=$(cd "$here/../.." && pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bash "$here/make-fixture.sh" "$type" "$tmp/proj"
cd "$tmp/proj"

fail=0
check() { # $1 = label, rest = command
  label=$1; shift
  if out=$("$@" 2>&1); then
    echo "ok    $label"
  else
    echo "FAIL  $label (exit $?)"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=1
  fi
}

# detect.sh must always produce a verdict, on any fixture.
check "detect.sh" bash "$plugin_root/skills/forge-init/scripts/detect.sh"
bash "$plugin_root/skills/forge-init/scripts/detect.sh" | grep -q '^verdict: ' \
  || { echo "FAIL  detect.sh verdict line missing"; fail=1; }

# SessionStart inline hook (extracted from hooks.json — the shipped command).
ss_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$plugin_root/hooks/hooks.json")
check "SessionStart hook" bash -c "$ss_cmd"

# Stop hook: must exit 0 with and without pending changes.
check "track.sh (clean tree)" bash "$plugin_root/hooks/scripts/track.sh"
printf 'change\n' > smoke-change.txt
check "track.sh (dirty tree)" bash "$plugin_root/hooks/scripts/track.sh"

# Guard: allow + deny paths.
check "guard.sh (allow)" bash -c \
  "printf '%s' '{\"tool_input\":{\"file_path\":\"src/ok.ts\"}}' | bash '$plugin_root/hooks/scripts/guard.sh'"
deny_out=$(printf '%s' '{"tool_input":{"file_path":"package-lock.json"}}' \
  | bash "$plugin_root/hooks/scripts/guard.sh")
case "$deny_out" in
  *'"deny"'*) echo "ok    guard.sh (deny)" ;;
  *) echo "FAIL  guard.sh did not deny a lock file"; fail=1 ;;
esac

# forge-index.sh build should work wherever a context dir exists.
if [ -d context ] || [ -d .forge ]; then
  if command -v sqlite3 >/dev/null 2>&1; then
    check "forge-index.sh build" bash "$plugin_root/skills/forge-init/scripts/forge-index.sh" build
  else
    echo "skip  forge-index.sh (sqlite3 not installed)"
  fi
fi

exit "$fail"
