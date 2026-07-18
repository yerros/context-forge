#!/usr/bin/env bash
# forge-stats.sh — aggregate the opt-in local metrics (see metrics.sh).
# Read-only; run it yourself whenever you want the numbers.
#
#   forge-stats.sh [days]      # default: last 30 days

set -eu

days=${1:-30}
case "$days" in *[!0-9]*) echo "usage: forge-stats.sh [days]" >&2; exit 1 ;; esac

f="${HOME}/.claude/forge-metrics/events.ndjson"
if [ ! -f "$f" ]; then
  echo "no metrics recorded yet (they record automatically as you work)"
  echo "to opt out: touch ~/.claude/forge-metrics/disabled"
  exit 0
fi

# Cutoff date, GNU first then BSD.
cutoff=$(date -d "-${days} days" '+%Y-%m-%d' 2>/dev/null \
  || date -v -"${days}d" '+%Y-%m-%d')

# Our own writer (metrics.sh) controls the format, so a field-based awk parse is
# reliable — no jq dependency.
awk -v cutoff="$cutoff" '
  function field(name,   re, s) {
    re = "\"" name "\":\"[^\"]*\""
    if (match($0, re)) {
      s = substr($0, RSTART, RLENGTH)
      sub("\"" name "\":\"", "", s); sub("\"$", "", s)
      return s
    }
    return ""
  }
  {
    ts = field("ts")
    if (ts == "" || substr(ts, 1, 10) < cutoff) next
    total++
    ev = field("event");   if (ev != "") events[ev]++
    sk = field("skill");   if (sk != "") skills[sk]++
    pj = field("project"); if (pj != "") projects[pj]++
  }
  END {
    printf "forge metrics — last %s (%d events since %s)\n\n", days_label, total, cutoff
    if (total == 0) { print "nothing recorded in this window"; exit }
    print "by event:"
    for (e in events)   printf "  %-24s %d\n", e, events[e]
    n = 0; for (s in skills) n++
    if (n) { print "\nby skill:"; for (s in skills) printf "  %-24s %d\n", s, skills[s] }
    print "\nby project:"
    for (p in projects) printf "  %-24s %d\n", p, projects[p]
    if (skills["forge-build"] > 0) {
      printf "\ndebug pressure: %d forge-debug per %d forge-build", \
        skills["forge-debug"], skills["forge-build"]
      printf "  (rising ratio = specs or lessons need attention)\n"
    }
  }
' days_label="${days} days" "$f"
