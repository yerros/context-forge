#!/usr/bin/env bash
# wait-status.sh — records when a session is BLOCKED on the user, so the
# forge-office dashboard can show a "waiting for input" / "permission needed"
# bubble. Same contract as now-status.sh: deterministic, zero model tokens,
# writes NOTHING to stdout, always exits 0, never blocks.
#
# Usage (from hooks.json):
#   wait-status.sh notify       # Notification — permission_prompt|idle_prompt
#   wait-status.sh permission   # PermissionRequest — a tool awaits approval
#   wait-status.sh stop         # Stop — the turn ended, Claude waits for the user
#   wait-status.sh clear        # PreToolUse / UserPromptSubmit — work resumed
#
# State file: ~/.claude/forge-status/<session_id>.wait
#   line format: "<waiting|permission> <epoch>"

set -u
mode=${1:-clear}
input=$(cat)

dir="${HOME}/.claude/forge-status"
mkdir -p "$dir" 2>/dev/null || exit 0

jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

sid=$(jfield "session_id")
[ -z "$sid" ] && exit 0
case "$sid" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
state="$dir/$sid.wait"

kind=""
case "$mode" in
  clear)      rm -f "$state" 2>/dev/null; exit 0 ;;
  permission) kind=permission ;;
  stop)       kind=waiting ;;
  notify)
    case "$(jfield "notification_type")" in
      permission_prompt) kind=permission ;;
      idle_prompt)       kind=waiting ;;
      *)                 exit 0 ;;   # auth_success etc. — not a wait state
    esac ;;
  *) exit 0 ;;
esac

printf '%s %s\n' "$kind" "$(date +%s)" > "$state" 2>/dev/null
exit 0
