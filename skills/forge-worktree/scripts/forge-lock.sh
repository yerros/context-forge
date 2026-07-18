#!/usr/bin/env bash
# forge-lock.sh — portable mutual exclusion for shared context files, and unit
# claims for builds that do NOT use a separate worktree. Extends the same
# claim mechanism as forge-worktree.sh (shared git common dir, atomic create).
#
# Why not flock? It is not shipped on stock macOS. mkdir is atomic on every
# POSIX filesystem, so the lock is a directory.
#
#   forge-lock.sh lock <name> [--wait <sec>] [--steal]   # acquire <name>
#   forge-lock.sh unlock <name>                          # release <name>
#   forge-lock.sh claim <NN> [note]                      # claim a unit (no worktree)
#   forge-lock.sh release <NN>                           # release a unit claim
#   forge-lock.sh status                                 # show locks + claims
#
# Typical use around a tracker update when several engineers build in parallel:
#   forge-lock.sh lock tracker --wait 30
#   ...edit context/progress-tracker.md...
#   forge-lock.sh unlock tracker
#
# Locks:  $(git common dir)/forge-locks/<name>.lock/  (dir = atomic mkdir)
# Claims: $(git common dir)/forge-claims/<NN>         (same file forge-worktree uses)
# A lock older than STALE_MIN minutes is reported as stale; --steal takes it over.

set -eu

STALE_MIN=15

say() { printf '%s\n' "$*"; }
die() { printf 'forge-lock: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not inside a git repository (locks live in the shared .git dir)"

common=$(git rev-parse --git-common-dir)
case "$common" in /*) ;; *) common="$(pwd)/$common" ;; esac
locks="$common/forge-locks"
claims="$common/forge-claims"
mkdir -p "$locks" "$claims"

# Portable file-mtime (GNU first, BSD fallback) — same helper as forge-worktree.sh.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
age_min() { echo $(( ( $(date +%s) - $(mtime "$1") ) / 60 )); }

owner_line() { printf 'host=%s pid=%s user=%s at=%s\n' \
  "$(hostname 2>/dev/null || echo '?')" "$$" "${USER:-?}" "$(date '+%Y-%m-%d %H:%M:%S')"; }

sanitize() { # lock names become path components
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) die "invalid name '$1' (letters, digits, . _ - only)" ;;
  esac
}

mode=${1:-}

case "$mode" in
lock)
  name=${2:-}; [ -n "$name" ] || die "usage: forge-lock.sh lock <name> [--wait <sec>] [--steal]"
  sanitize "$name"
  wait_s=0; steal=0
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait) wait_s=${2:-0}; shift 2 ;;
      --steal) steal=1; shift ;;
      *) die "unknown option '$1'" ;;
    esac
  done
  d="$locks/$name.lock"
  deadline=$(( $(date +%s) + wait_s ))
  while :; do
    if mkdir "$d" 2>/dev/null; then
      owner_line > "$d/owner"
      say "locked: $name"
      exit 0
    fi
    a=$(age_min "$d")
    if [ "$steal" = 1 ]; then
      rm -rf "$d"   # explicit takeover — the caller asserted the holder is gone
      continue
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      say "forge-lock: '$name' is HELD (${a}m old):"
      [ -f "$d/owner" ] && sed 's/^/  /' "$d/owner"
      if [ "$a" -ge "$STALE_MIN" ]; then
        say "  looks STALE (>${STALE_MIN}m) — re-run with --steal if the holder is gone"
      fi
      exit 1
    fi
    sleep 1
  done
  ;;
unlock)
  name=${2:-}; [ -n "$name" ] || die "usage: forge-lock.sh unlock <name>"
  sanitize "$name"
  d="$locks/$name.lock"
  [ -d "$d" ] || { say "not locked: $name"; exit 0; }
  rm -rf "$d"
  say "unlocked: $name"
  ;;
claim)
  nn=${2:-}; note=${3:-}
  [ -n "$nn" ] || die "usage: forge-lock.sh claim <NN> [note]"
  case "$nn" in *[!0-9]*) die "unit must be a number (got '$nn')" ;; esac
  nn=$(printf '%02d' "$nn")
  claim="$claims/$nn"
  # Atomic claim: noclobber write fails if the file exists (same as forge-worktree).
  if ! ( set -C; { printf 'unit=%s\nmode=build\nclaimed_at=%s\n' \
        "$nn" "$(date '+%Y-%m-%d %H:%M')"; owner_line; \
        [ -z "$note" ] || printf 'note=%s\n' "$note"; } > "$claim" ) 2>/dev/null; then
    say "forge-lock: unit $nn is ALREADY CLAIMED:"
    sed 's/^/  /' "$claim"
    die "pick another unit, or release it if abandoned"
  fi
  say "unit $nn claimed (in-place build, no worktree)"
  ;;
release)
  nn=${2:-}
  [ -n "$nn" ] || die "usage: forge-lock.sh release <NN>"
  case "$nn" in *[!0-9]*) die "unit must be a number" ;; esac
  nn=$(printf '%02d' "$nn")
  claim="$claims/$nn"
  [ -f "$claim" ] || die "no claim for unit $nn"
  if grep -q '^worktree=' "$claim" 2>/dev/null; then
    die "unit $nn was claimed by forge-worktree — release it with 'forge-worktree.sh done $nn'"
  fi
  rm -f "$claim"
  say "unit $nn released"
  ;;
status)
  found=0
  for d in "$locks"/*.lock; do
    [ -d "$d" ] || continue
    found=1
    n=$(basename "$d" .lock)
    a=$(age_min "$d")
    flag=""; [ "$a" -ge "$STALE_MIN" ] && flag="  [STALE >${STALE_MIN}m]"
    say "lock  $n  (${a}m old)$flag"
    [ -f "$d/owner" ] && sed 's/^/      /' "$d/owner"
  done
  for c in "$claims"/*; do
    [ -f "$c" ] || continue
    found=1
    say "claim unit $(basename "$c")  ($(age_min "$c")m old)"
    sed 's/^/      /' "$c"
  done
  [ "$found" = 0 ] && say "no locks, no claims"
  ;;
*)
  die "usage: forge-lock.sh lock <name> [--wait <sec>] [--steal] | unlock <name> | claim <NN> [note] | release <NN> | status"
  ;;
esac
