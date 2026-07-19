#!/usr/bin/env bats
# forge-reconcile detector (skills/forge-reconcile/scripts/detect-oob.sh).

load helpers/common

setup() { setup_project; }

# Adopted project: tracker committed (the adoption epoch).
adopt() {
  init_git
  mkdir -p context
  printf '# Progress Tracker\n' > context/progress-tracker.md
  commit_all "chore: forge-init scaffolding"
}

oob_commit() { # $1 = file, $2 = message
  printf 'x\n' >> "$1"
  git add -A
  git commit -qm "$2"
}

@test "reconcile: no context files -> report NO_CONTEXT, hook silent" {
  init_git
  run bash "$DETECT_OOB"
  [ "$status" -eq 0 ]
  grep -q 'verdict: NO_CONTEXT' <<<"$output"
  run bash "$DETECT_OOB" --hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reconcile: tracker never committed -> NO_EPOCH" {
  init_git
  mkdir -p context
  printf '# Tracker\n' > context/progress-tracker.md
  run bash "$DETECT_OOB"
  grep -q 'verdict: NO_EPOCH' <<<"$output"
}

@test "reconcile: only in-band history -> CLEAN, hook silent" {
  adopt
  printf 'a\n' > app.ts
  printf 'x' >> context/progress-tracker.md
  commit_all "feat: unit work with tracker bookkeeping"
  run bash "$DETECT_OOB"
  grep -q 'verdict: CLEAN' <<<"$output"
  run bash "$DETECT_OOB" --hook
  [ -z "$output" ]
}

@test "reconcile: commit citing its spec is in-band even without context edits" {
  adopt
  printf 'a\n' > app.ts
  git add -A
  git commit -qm "feat(auth): login" -m "Implements unit 04 per context/specs/04-auth.md"
  run bash "$DETECT_OOB"
  grep -q 'verdict: CLEAN' <<<"$output"
}

@test "reconcile: code-only commit with no trail -> OOB, listed in report and hook" {
  adopt
  oob_commit app.ts "fix: manual hotfix"
  run bash "$DETECT_OOB"
  grep -q 'verdict: OOB' <<<"$output"
  grep -q 'oob_count: 1' <<<"$output"
  grep -q 'manual hotfix' <<<"$output"
  run bash "$DETECT_OOB" --hook
  grep -q 'forge-reconcile' <<<"$output"
  grep -q 'manual hotfix' <<<"$output"
}

@test "reconcile: pre-adoption history is never flagged" {
  init_git
  printf 'legacy\n' > old.ts
  commit_all "legacy work before forge"
  mkdir -p context
  printf '# Progress Tracker\n' > context/progress-tracker.md
  commit_all "chore: forge-init scaffolding"
  run bash "$DETECT_OOB"
  grep -q 'verdict: CLEAN' <<<"$output"
}

@test "reconcile: Reconciles: marker excludes adopted commits" {
  adopt
  oob_commit app.ts "fix: manual hotfix"
  sha=$(git log --format=%h -1)
  git commit -q --allow-empty \
    -m "chore(forge): reconcile out-of-band work" -m "Reconciles: $sha"
  run bash "$DETECT_OOB"
  grep -q 'verdict: CLEAN' <<<"$output"
}

@test "reconcile: .reconcile-ignore dismisses a commit" {
  adopt
  oob_commit app.ts "chore: formatting noise"
  git log --format=%h -1 > context/.reconcile-ignore
  run bash "$DETECT_OOB"
  grep -q 'verdict: CLEAN' <<<"$output"
}

@test "reconcile: uncommitted non-context changes -> dirty_tree yes" {
  adopt
  printf 'wip\n' > wip.ts
  run bash "$DETECT_OOB"
  grep -q 'dirty_tree: yes' <<<"$output"
  grep -q 'dirty: wip.ts' <<<"$output"
}

@test "reconcile: works with .forge context dir" {
  init_git
  mkdir -p .forge
  printf '# Progress Tracker\n' > .forge/progress-tracker.md
  commit_all "chore: forge-init scaffolding"
  oob_commit app.ts "fix: manual hotfix"
  run bash "$DETECT_OOB"
  grep -q 'context_dir: .forge' <<<"$output"
  grep -q 'verdict: OOB' <<<"$output"
}

@test "reconcile: hook never fails and never writes files" {
  adopt
  oob_commit app.ts "fix: manual hotfix"
  before=$(git status --porcelain | sort)
  run bash "$DETECT_OOB" --hook
  [ "$status" -eq 0 ]
  after=$(git status --porcelain | sort)
  [ "$before" = "$after" ]
}
