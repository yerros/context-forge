#!/usr/bin/env bash
# make-fixture.sh — build a throwaway fixture project for the CI matrix.
#
#   make-fixture.sh <brownfield-empty|modules|no-git> <target-dir>
#
#   brownfield-empty  a codebase with no Context Forge files at all
#   modules           a large project: six files + digest + context/modules/*
#   no-git            context files present, but no git repository
set -eu

type=${1:?usage: make-fixture.sh <type> <dir>}
dir=${2:?usage: make-fixture.sh <type> <dir>}

mkdir -p "$dir"
cd "$dir"

init_git() {
  git init -q .
  git config user.email "tests@context-forge.invalid"
  git config user.name "Context Forge Fixture"
}

mk_ctx() { # $1 = context dir name
  ctx=$1
  mkdir -p "$ctx/specs"
  for f in project-overview architecture ui-context code-standards ai-workflow-rules; do
    printf '# %s\n\nReal content, no placeholders.\n' "$f" > "$ctx/$f.md"
  done
  printf '# Progress Tracker\n\n## In Progress\n\n(none)\n\n## Next Up\n\n- unit 01\n' \
    > "$ctx/progress-tracker.md"
  printf '# Context Digest\n\nFixture project one-liner.\n\n## Tier map\n\n- building: progress-tracker.md\n' \
    > "$ctx/context-digest.md"
}

case "$type" in
brownfield-empty)
  init_git
  printf '{ "name": "fixture", "private": true }\n' > package.json
  mkdir -p src
  printf 'export const x = 1;\n' > src/index.ts
  git add -A && git commit -qm init
  ;;
modules)
  init_git
  mk_ctx context
  mkdir -p context/modules
  for m in api web billing; do
    printf '# %s module context\n\nBoundary notes for %s.\n' "$m" "$m" > "context/modules/$m.md"
  done
  git add -A && git commit -qm init
  ;;
no-git)
  mk_ctx context
  ;;
*)
  echo "make-fixture.sh: unknown fixture type '$type'" >&2
  exit 1
  ;;
esac

echo "fixture '$type' ready at $dir"
