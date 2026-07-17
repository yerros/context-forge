#!/usr/bin/env bash
# forge-worktree.sh — parallel-build plumbing: one unit = one worktree = one branch.
# Deterministic, no model tokens. Claims live in the shared git common dir so every
# worktree sees them (that's what prevents two terminals grabbing the same unit).
#
#   forge-worktree.sh new <NN> <slug>   # create worktree ../<repo>-u<NN> on feat/<NN>-<slug>, claim unit
#   forge-worktree.sh list              # active claims: unit, path, branch, age
#   forge-worktree.sh done <NN>         # release the claim and remove the worktree (must be clean/merged)
#
# Claim file: $(git rev-parse --git-common-dir)/forge-claims/<NN> — created with
# noclobber (atomic on POSIX filesystems), so a double claim loses cleanly.

set -eu

say() { printf '%s\n' "$*"; }
die() { printf 'forge-worktree: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

common=$(git rev-parse --git-common-dir)
# Resolve to absolute (git may print a relative path).
case "$common" in /*) ;; *) common="$(pwd)/$common" ;; esac
claims="$common/forge-claims"
mkdir -p "$claims"

# New worktrees always hang off the MAIN repo, even when this script runs from
# inside a linked worktree — the main root is the parent of the shared .git dir.
main_root=$(dirname "$common")
repo_name=$(basename "$main_root")

# Portable file-mtime (GNU first, BSD fallback).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

mode=${1:-}

case "$mode" in
new)
  nn=${2:-}; slug=${3:-}
  [ -z "$nn" ] && die "usage: forge-worktree.sh new <NN> <slug>"
  [ -z "$slug" ] && die "usage: forge-worktree.sh new <NN> <slug> (slug = short feature name, e.g. invoice-crud)"
  case "$nn" in *[!0-9]*) die "unit must be a number (got '$nn')" ;; esac
  nn=$(printf '%02d' "$nn")

  branch="feat/$nn-$slug"
  wt_path="$main_root/../$repo_name-u$nn"
  claim="$claims/$nn"

  # Atomic claim: noclobber write fails if the file exists.
  if ! ( set -C; printf 'unit=%s\nbranch=%s\nworktree=%s\nclaimed_at=%s\n' \
        "$nn" "$branch" "$wt_path" "$(date '+%Y-%m-%d %H:%M')" > "$claim" ) 2>/dev/null; then
    say "forge-worktree: unit $nn is ALREADY CLAIMED:"
    sed 's/^/  /' "$claim"
    die "pick another unit, or 'forge-worktree.sh done $nn' if that worktree is finished"
  fi

  if ! git worktree add -b "$branch" "$wt_path" 2>&1; then
    rm -f "$claim"   # roll the claim back if the worktree failed
    die "worktree creation failed (branch may already exist) — claim released"
  fi

  say ""
  say "Unit $nn claimed. Next, in a NEW terminal:"
  say "  cd \"$wt_path\" && claude"
  say "then run: /forge-build unit $nn"
  ;;
list)
  found=0
  for c in "$claims"/*; do
    [ -f "$c" ] || continue
    found=1
    unit=$(basename "$c")
    age_min=$(( ( $(date +%s) - $(mtime "$c") ) / 60 ))
    say "unit $unit  (claimed ${age_min}m ago)"
    sed 's/^/  /' "$c"
  done
  [ "$found" = 0 ] && say "no active claims"
  git worktree list
  ;;
done)
  nn=${2:-}
  [ -z "$nn" ] && die "usage: forge-worktree.sh done <NN>"
  case "$nn" in *[!0-9]*) die "unit must be a number" ;; esac
  nn=$(printf '%02d' "$nn")
  claim="$claims/$nn"
  [ -f "$claim" ] || die "no claim for unit $nn"
  wt_path=$(sed -n 's/^worktree=//p' "$claim")

  if [ -d "$wt_path" ]; then
    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
      die "worktree $wt_path has uncommitted changes — commit/ship them first (nothing was removed)"
    fi
    git worktree remove "$wt_path" || die "could not remove worktree (nothing else was changed)"
  fi
  rm -f "$claim"
  say "unit $nn released; worktree removed. Reconcile on main: /forge-resume will refresh digest/index."
  ;;
*)
  die "usage: forge-worktree.sh new <NN> <slug> | list | done <NN>"
  ;;
esac
