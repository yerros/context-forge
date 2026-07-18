#!/usr/bin/env bash
# Skill-status recorder — deterministic, zero model tokens, never blocks.
# Maintains a tiny per-session state file that a status line can read to show
# which forge-* skill is in use. Writes NOTHING to stdout (hook stdout can be
# injected as context) and always exits 0.
#
# Usage (from hooks.json):
#   skill-status.sh capture   # UserPromptExpansion (slash command) + PreToolUse (Skill tool)
#   skill-status.sh idle      # Stop — mark the skill as idle (sticky display)
#
# State file: ~/.claude/forge-status/<session_id>
#   line format: "<active|idle> <skill-name> <epoch>"

set -u
mode=${1:-capture}
input=$(cat)

dir="${HOME}/.claude/forge-status"
mkdir -p "$dir" 2>/dev/null || exit 0

# Extract a JSON string field (single-line token; same defensive style as guard.sh).
jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

sid=$(jfield "session_id")
[ -z "$sid" ] && exit 0
# Session ids are expected to be safe tokens; refuse anything else (path safety).
case "$sid" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
state="$dir/$sid"

# Housekeeping: drop state files older than a day.
find "$dir" -type f -mmin +1440 -delete 2>/dev/null

if [ "$mode" = "idle" ]; then
  # Stop hook: downgrade active -> idle (sticky), keep the skill name.
  if [ -f "$state" ]; then
    read -r _st sk _ts < "$state" 2>/dev/null || exit 0
    [ -n "${sk:-}" ] && printf 'idle %s %s\n' "$sk" "$(date +%s)" > "$state"
  fi
  exit 0
fi

# capture: find a forge-* skill name in the hook payload.
# UserPromptExpansion carries command_name; the Skill tool's input schema is not
# formally documented, so try common keys defensively.
skill=""
for key in command_name skill skill_name skillName name command; do
  v=$(jfield "$key")
  case "$v" in
    *forge-*)
      # Strip any plugin prefix ("context-forge:forge-fix" -> "forge-fix").
      skill=${v##*:}
      case "$skill" in forge-*) break ;; *) skill="" ;; esac
      ;;
  esac
done

[ -z "$skill" ] && exit 0
printf 'active %s %s\n' "$skill" "$(date +%s)" > "$state"

# Opt-in local metrics (no-op unless ~/.claude/forge-metrics/enabled exists).
m="$(dirname "$0")/metrics.sh"
[ -f "$m" ] && bash "$m" record skill_invoked "skill=$skill" 2>/dev/null

exit 0
