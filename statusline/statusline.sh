#!/usr/bin/env bash
# Reference status line for Claude Code with a forge skill indicator.
# Reads the statusline JSON on stdin, shows: skill indicator · model · git branch
# · cost · context usage. Copy or adapt freely — the only contract is the state
# file written by hooks/scripts/skill-status.sh:
#   ~/.claude/forge-status/<session_id>  ->  "<active|idle> <skill> <epoch>"
#
# Setup (one time), e.g. in ~/.claude/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "bash ~/.claude/forge-statusline.sh",
#                   "refreshInterval": 1000 }
# after copying this file to ~/.claude/forge-statusline.sh — or run /statusline
# and ask for these elements.

set -u
input=$(cat)

jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}
jnum() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]+" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*//"
}

sid=$(jfield "session_id")
model=$(jfield "display_name")
cwd=$(jfield "current_dir"); [ -z "$cwd" ] && cwd=$(jfield "cwd")
cost=$(jnum "total_cost_usd")
ctx=$(jnum "used_percentage")

# --- forge skill indicator (sticky: active -> shown; idle -> dimmed 30 min) ---
IDLE_TTL=1800
skill_part=""
if [ -n "$sid" ] && [ -f "${HOME}/.claude/forge-status/$sid" ]; then
  read -r st sk ts < "${HOME}/.claude/forge-status/$sid" 2>/dev/null || true
  now=$(date +%s)
  case "${st:-}" in
    active) skill_part="⚒ ${sk}" ;;
    idle)   [ $((now - ${ts:-0})) -lt $IDLE_TTL ] && skill_part="(${sk})" ;;
  esac
fi

# --- git branch ---
branch=""
if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

out=""
append() { [ -n "$1" ] && out="${out}${out:+ · }$1"; }
append "$skill_part"
append "${model}"
append "${branch:+⎇ $branch}"
[ -n "$cost" ] && append "\$$(printf '%.2f' "$cost" 2>/dev/null || printf '%s' "$cost")"
[ -n "$ctx" ] && append "ctx ${ctx%%.*}%"

printf '%s\n' "$out"
