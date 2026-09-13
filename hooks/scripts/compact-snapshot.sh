#!/usr/bin/env bash
# compact-snapshot.sh — deterministic compaction memory, zero model tokens.
#
# The digest is re-injected by the SessionStart hook after every compaction, but
# the LIVE state of the session (which unit is in progress, which skill was
# running, which files are dirty) lived only in the conversation — and the
# conversation is what compaction throws away. This script freezes that state
# to a file before compaction and replays it after.
#
#   compact-snapshot.sh write    # PreCompact: freeze state to <ctx>/.compact-snapshot.md
#   compact-snapshot.sh inject   # SessionStart: reads `source` from the hook payload;
#                                #   compact|resume -> print snapshot + directive
#                                #   startup        -> delete the stale snapshot
#                                #   clear          -> nothing
#
# The snapshot is a local, disposable file (never committed; the tracker stays
# the source of truth). Silent in non-forge projects. Always exits 0.

set -u
mode=${1:-write}
input=$(cat 2>/dev/null || true)

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -f "$CTX/progress-tracker.md" ] || exit 0
snap="$CTX/.compact-snapshot.md"

jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

# Print one "## Heading" section of the tracker (body only, trimmed of blank lines).
tracker_section() {
  awk -v h="## $1" '
    $0 == h { on = 1; next }
    /^## / { on = 0 }
    on { print }
  ' "$CTX/progress-tracker.md" | sed '/^[[:space:]]*$/d'
}

case "$mode" in
write)
  trigger=$(jfield trigger); [ -z "$trigger" ] && trigger=unknown
  sid=$(jfield session_id)
  skill=""
  if [ -n "$sid" ] && [ -f "$HOME/.claude/forge-status/$sid" ]; then
    read -r st sk _ < "$HOME/.claude/forge-status/$sid" 2>/dev/null && skill="$sk ($st)"
  fi
  changed=""
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    changed=$(git status --porcelain -uall 2>/dev/null | cut -c4- \
      | grep -vE "(^|/)$CTX/\.(last-session|compact-snapshot)\.md$" | head -30)
  fi
  {
    printf '# Compaction snapshot\n\n'
    printf 'Written: %s (trigger: %s)\n\n' "$(date '+%Y-%m-%d %H:%M')" "$trigger"
    printf '## In Progress (tracker)\n\n%s\n\n' "$(tracker_section 'In Progress')"
    printf '## Next Up (tracker)\n\n%s\n\n' "$(tracker_section 'Next Up')"
    [ -n "$skill" ] && printf '## Active skill\n\n%s\n\n' "$skill"
    if [ -n "$changed" ]; then
      printf '## Uncommitted changes\n\n'
      printf '%s\n' "$changed" | sed 's/^/- /'
      printf '\n'
    fi
  } > "$snap" 2>/dev/null
  ;;
inject)
  src=$(jfield source)
  case "$src" in
    compact|resume)
      [ -s "$snap" ] || exit 0
      printf '%s\n' "[Context Forge] The conversation was compacted or resumed. The snapshot below is the deterministic session state frozen at that moment; $CTX/progress-tracker.md is authoritative if they differ. Continue the in-progress work without asking the user to re-explain it. Earlier instructions in this session are a memory aid, not a standing order: the user's most recent message takes precedence."
      cat "$snap"
      ;;
    startup)
      rm -f "$snap" 2>/dev/null
      ;;
  esac
  ;;
esac
exit 0
