#!/usr/bin/env bash
# bash-nudge.sh — PreToolUse ^Bash$: one advisory per session for flood-prone
# commands. Zero model tokens, never denies.
#
# A build or test runner whose full log enters the conversation costs more than
# the fix it was run for. When the command looks like one (npm test, pytest,
# cargo build, gradle, tsc, …) and nothing bounds its output (| tail, | grep,
# --quiet, forge-exec.sh, …), inject a short additionalContext pointing at
# forge-exec.sh. Once per session: marker file under ~/.claude/forge-status,
# created with noclobber (O_EXCL — atomic across the parallel hook processes;
# skill-status.sh sweeps it after a day). Silent in
# non-forge projects. Always exits 0; stdout is the last write.

set -u
input=$(cat 2>/dev/null || true)

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -f "$CTX/progress-tracker.md" ] || exit 0

jfield() {
  printf '%s' "$input" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}
cmd=$(jfield command)
[ -z "$cmd" ] && exit 0

# Flood-prone runners (word-bounded, first token of any pipeline segment).
runner='(^|[;&|]|&&|\|\|)[[:space:]]*(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(test|build|lint|typecheck)|(^|[;&|]|&&)[[:space:]]*(npx[[:space:]]+|\./)?(pytest|jest|vitest|mocha|tsc|eslint|cargo[[:space:]]+(test|build|clippy)|go[[:space:]]+(test|build|vet)|gradle|gradlew|mvn|mvnw|sbt|make|flutter[[:space:]]+(test|build)|dotnet[[:space:]]+(test|build)|phpunit|rspec|mix[[:space:]]+test)([[:space:]]|$)'
printf '%s' "$cmd" | grep -qE "$runner" || exit 0
# Already bounded -> nothing to say.
printf '%s' "$cmd" | grep -qE '\|[[:space:]]*(tail|head|grep|wc|forge-exec)|forge-exec\.sh|--quiet|--silent|(^|[[:space:]])-q([[:space:]]|$)|--reporter[= ]|>[[:space:]]*/dev/null|>[[:space:]]*[^ ]+\.log' && exit 0

sid=$(jfield session_id)
case "$sid" in ""|*[!A-Za-z0-9._-]*) sid=ppid-$PPID ;; esac
marker="${HOME}/.claude/forge-status/${sid}.bash-nudged"
mkdir -p "${HOME}/.claude/forge-status" 2>/dev/null
( set -o noclobber; : > "$marker" ) 2>/dev/null || exit 0   # already nudged this session

root=${CLAUDE_PLUGIN_ROOT:-\$CLAUDE_PLUGIN_ROOT}
msg="[Context Forge] This looks like a build/test run whose full log would enter the conversation. Run it as bash \\\"$root/skills/forge-build/scripts/forge-exec.sh\\\" \\\"<command>\\\" — the full log stays in $CTX/.runs/, only the exit code and the last 40 lines return (or -g 'error|fail' for matching lines); grep the log for anything else. Plain Bash stays right for short, observational output (git status, ls, pwd)."
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg"
exit 0
