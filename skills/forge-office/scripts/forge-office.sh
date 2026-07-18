#!/usr/bin/env bash
# forge-office.sh — launcher for the bundled dashboard (dashboard/ in the plugin).
# The dashboard itself is read-only and binds to 127.0.0.1 only.
#
#   forge-office.sh start [--hook]   # start for the current project (idempotent)
#   forge-office.sh stop             # stop the server for this port
#   forge-office.sh status           # running or not, which project, URL
#   forge-office.sh autostart on|off # start automatically at SessionStart
#
# Port: $FORGE_OFFICE_PORT or 4820. State: ~/.claude/forge-office/<port>.pid/.log
# --hook mode (used by the SessionStart hook): completely silent unless the
# server actually starts fresh, then prints ONE line with the URL; never fails.

set -u

say() { printf '%s\n' "$*"; }
die() { printf 'forge-office: %s\n' "$*" >&2; exit 1; }

mode=${1:-start}
hookmode=0
[ "${2:-}" = "--hook" ] && hookmode=1
quiet() { [ "$hookmode" = 1 ]; }

port=${FORGE_OFFICE_PORT:-4820}
dir="${HOME}/.claude/forge-office"
mkdir -p "$dir" 2>/dev/null || { quiet && exit 0; die "cannot create $dir"; }
pidfile="$dir/$port.pid"
logfile="$dir/$port.log"
url="http://127.0.0.1:$port"

script_dir=$(cd "$(dirname "$0")" && pwd)
plugin_root=$(cd "$script_dir/../../.." && pwd)
server="$plugin_root/dashboard/src/server.mjs"

running() {
  [ -f "$pidfile" ] || return 1
  pid=$(cat "$pidfile" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

case "$mode" in
start)
  # In hook mode only start inside Context Forge projects — a dashboard for a
  # random directory is noise.
  if [ "$hookmode" = 1 ]; then
    [ -f ".forge/progress-tracker.md" ] || [ -f "context/progress-tracker.md" ] || exit 0
  fi
  if running; then
    quiet || { say "already running: $url (project: $(cat "$dir/$port.project" 2>/dev/null || echo '?'))"; }
    exit 0
  fi
  command -v node >/dev/null 2>&1 || { quiet && exit 0; die "node not found — the dashboard needs Node ≥18 (or run it with bun manually)"; }
  [ -f "$server" ] || { quiet && exit 0; die "bundled dashboard not found at $server"; }

  FORGE_OFFICE_PORT="$port" nohup node "$server" "$PWD" >> "$logfile" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pidfile"
  printf '%s\n' "$PWD" > "$dir/$port.project"

  # Wait briefly and verify it actually serves.
  ok=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if command -v curl >/dev/null 2>&1; then
      curl -sf -o /dev/null "$url/api/state" && { ok=1; break; }
    else
      kill -0 "$pid" 2>/dev/null && { ok=1; break; }   # no curl: alive is our best signal
    fi
    sleep 0.3
  done
  if [ "$ok" = 1 ]; then
    say "[Context Forge] dashboard: $url  (project: $(basename "$PWD"))"
    if ! quiet && command -v open >/dev/null 2>&1; then open "$url" 2>/dev/null || true; fi
  else
    rm -f "$pidfile"
    quiet && exit 0
    die "failed to start — see $logfile"
  fi
  ;;
stop)
  running || { say "not running (port $port)"; exit 0; }
  kill "$(cat "$pidfile")" 2>/dev/null
  rm -f "$pidfile" "$dir/$port.project"
  say "stopped (port $port)"
  ;;
status)
  if running; then
    say "running: $url"
    say "project: $(cat "$dir/$port.project" 2>/dev/null || echo '?')"
    say "pid: $(cat "$pidfile")  log: $logfile"
  else
    say "not running (port $port)"
  fi
  [ -f "$dir/autostart" ] && say "autostart: on" || say "autostart: off"
  ;;
autostart)
  case "${2:-}" in
    on)  touch "$dir/autostart"; say "autostart on — the dashboard will start with every Claude Code session in a Context Forge project" ;;
    off) rm -f "$dir/autostart"; say "autostart off" ;;
    *)   die "usage: forge-office.sh autostart on|off" ;;
  esac
  ;;
*)
  die "usage: forge-office.sh start [--hook] | stop | status | autostart on|off"
  ;;
esac
exit 0
