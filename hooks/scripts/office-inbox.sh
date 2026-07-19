#!/usr/bin/env bash
# office-inbox.sh — deliver forge-office dashboard messages into the session.
# The dashboard (chat box / kanban "assign") appends NDJSON lines to
#   ~/.claude/forge-office/inbox/<project-basename>.ndjson
# — NEVER into the project. This UserPromptSubmit hook drains that file and
# prints the pending messages to stdout, which Claude Code injects as context
# for the next turn. Empty inbox costs one file-existence check.
#
# Contract: always exits 0; prints nothing when there is nothing to deliver.

set -u
cat >/dev/null 2>&1 || true   # drain hook stdin; payload not needed

inbox="${HOME}/.claude/forge-office/inbox/$(basename "$PWD").ndjson"
[ -s "$inbox" ] || exit 0

# Claim the file atomically so parallel sessions don't double-deliver.
tmp="${inbox}.claim.$$"
mv "$inbox" "$tmp" 2>/dev/null || exit 0

printf '%s\n' "[forge-office] Pending messages from the dashboard (delivered once, oldest first). Treat 'assign' entries as a request to build that unit next via the normal forge workflow; treat 'chat' entries as user messages addressed to the named agent or to the main session:"

# Render each NDJSON line as a readable bullet without requiring jq.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  kind=$(printf '%s' "$line" | grep -oE '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"$/\1/')
  to=$(printf '%s'   "$line" | grep -oE '"to"[[:space:]]*:[[:space:]]*"[^"]*"'   | head -1 | sed -E 's/.*:"(.*)"$/\1/')
  unit=$(printf '%s' "$line" | grep -oE '"unit"[[:space:]]*:[[:space:]]*"?[0-9]+"?' | head -1 | grep -oE '[0-9]+')
  msg=$(printf '%s'  "$line" | grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"$/\1/')
  ts=$(printf '%s'   "$line" | grep -oE '"ts"[[:space:]]*:[[:space:]]*"[^"]*"'    | head -1 | sed -E 's/.*:"(.*)"$/\1/')
  case "$kind" in
    assign) printf -- '- [assign %s] build unit %s next%s\n' "${ts:-?}" "${unit:-?}" "${msg:+ — $msg}" ;;
    chat)   printf -- '- [chat %s → %s] %s\n' "${ts:-?}" "${to:-main session}" "${msg:-}" ;;
    *)      printf -- '- %s\n' "$line" ;;
  esac
done < "$tmp"

rm -f "$tmp" 2>/dev/null
exit 0
