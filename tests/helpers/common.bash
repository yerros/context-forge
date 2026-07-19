# Shared helpers for the context-forge test suite (bats-core).
# Every test runs in an isolated project dir with a redirected $HOME, so the
# suite never touches the real home directory or the real repo state.

# Absolute path to the plugin repo root (tests/ lives directly under it).
PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export PLUGIN_ROOT

GUARD="$PLUGIN_ROOT/hooks/scripts/guard.sh"
TRACK="$PLUGIN_ROOT/hooks/scripts/track.sh"
SKILL_STATUS="$PLUGIN_ROOT/hooks/scripts/skill-status.sh"
WORKTREE="$PLUGIN_ROOT/skills/forge-worktree/scripts/forge-worktree.sh"
DETECT="$PLUGIN_ROOT/skills/forge-init/scripts/detect.sh"
DETECT_OOB="$PLUGIN_ROOT/skills/forge-reconcile/scripts/detect-oob.sh"
export GUARD TRACK SKILL_STATUS WORKTREE DETECT DETECT_OOB

# Fresh, isolated project dir for the current test.
setup_project() {
  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR" || return 1
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Minimal git repo with an identity so commits work everywhere (CI included).
init_git() {
  git init -q -b main . 2>/dev/null || { git init -q .; git checkout -qb main; }
  git config user.email "tests@context-forge.invalid"
  git config user.name "Context Forge Tests"
}

commit_all() {
  git add -A
  git commit -qm "${1:-fixture}"
}

# Write a file of exactly $2 bytes (for budget-threshold tests).
write_bytes() {
  head -c "$2" /dev/zero | tr '\0' 'x' > "$1"
}

# The SessionStart hook is an inline command in hooks.json — extract and run
# exactly what ships, so the tests can never drift from the real hook.
session_start_cmd() {
  jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json"
}

run_session_start() {
  bash -c "$(session_start_cmd)"
}
