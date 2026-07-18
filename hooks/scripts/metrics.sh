#!/usr/bin/env bash
# metrics.sh — OPT-IN local metrics recorder. This is NOT telemetry: nothing
# ever leaves the machine. Events append as NDJSON to
# ~/.claude/forge-metrics/events.ndjson so you can see, over time, how often
# skills run, how often builds hit forge-debug, and iterate on real data.
#
# Enable:   mkdir -p ~/.claude/forge-metrics && touch ~/.claude/forge-metrics/enabled
# Disable:  rm ~/.claude/forge-metrics/enabled
# Inspect:  hooks/scripts/forge-stats.sh [days]
#
# usage: metrics.sh record <event> [key=value ...]
#
# Costs nothing when disabled (one file-existence check). Writes nothing to
# stdout (hook stdout can be injected as context) and always exits 0.

set -u

dir="${HOME}/.claude/forge-metrics"
[ -f "$dir/enabled" ] || exit 0
[ "${1:-}" = "record" ] || exit 0
event=${2:-}
[ -n "$event" ] || exit 0
shift 2 2>/dev/null || exit 0

esc() { printf '%s' "$1" | tr -d '\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Only the project's basename is recorded — enough to group, no full paths.
line=$(printf '{"ts":"%s","event":"%s","project":"%s"' \
  "$(date '+%Y-%m-%dT%H:%M:%S')" "$(esc "$event")" "$(esc "$(basename "$PWD")")")

for kv in "$@"; do
  case "$kv" in *=*) ;; *) continue ;; esac
  k=${kv%%=*}; v=${kv#*=}
  case "$k" in ''|*[!A-Za-z0-9_]*) continue ;; esac
  line="$line,\"$k\":\"$(esc "$v")\""
done

printf '%s}\n' "$line" >> "$dir/events.ndjson" 2>/dev/null
exit 0
