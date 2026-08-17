#!/usr/bin/env bash
# agy-hook.sh — Antigravity CLI/IDE adapter for context-forge's hooks.
#
# Antigravity's hook contract differs from Claude Code's in three ways:
#   1. stdin payload is camelCase ({toolCall:{name,args},conversationId,...})
#      with Antigravity arg names (TargetFile, CommandLine, ...);
#   2. every hook MUST print a JSON object on stdout (PreToolUse needs a
#      "decision", PreInvocation injects context via "injectSteps", Stop needs
#      a "decision") — exit codes and raw-stdout injection mean nothing;
#   3. events are coarser: there is no SessionStart / UserPromptSubmit /
#      SubagentStop / SessionEnd — only PreToolUse, PostToolUse,
#      PreInvocation, PostInvocation, Stop.
#
# This adapter is the single entry point for all four events we register
# (see the generated hooks.json). Per event it:
#   - parses the Antigravity payload (python3 preferred, jq fallback),
#   - normalizes it into the flat Claude-Code-shaped JSON that the scripts in
#     hooks/scripts/ grep for (session_id, tool_name, file_path, ...),
#   - runs the SAME unmodified scripts (guard, now-status, agent-status,
#     skill-status, hook-logger, track, office-inbox),
#   - translates their outputs into the Antigravity response JSON.
#
# One adapter call per event also means exactly ONE decision JSON per event —
# no ambiguity about how multiple hook outputs combine.
#
# Docs: https://antigravity.google/docs/hooks
#
# Usage (from hooks.json): agy-hook.sh <PreToolUse|PostToolUse|PreInvocation|Stop>

set -u

EVENT=${1:-}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPTS="$ROOT/hooks/scripts"

RAW=$(cat 2>/dev/null || true)

PY=""
command -v python3 >/dev/null 2>&1 && PY=python3

# ---------------------------------------------------------------- parsing ----
# Emits "key<TAB>value" lines; values sanitized (no tabs/newlines, capped).
parse_payload() {
  if [ -n "$PY" ]; then
    printf '%s' "$RAW" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
def clean(v, cap=500):
    if v is None: return ""
    v = str(v)
    return v.replace("\t", " ").replace("\n", " ").replace("\r", " ")[:cap]
out = {}
out["sid"]  = d.get("conversationId", "")
wp = d.get("workspacePaths") or []
out["ws"]   = wp[0] if wp and isinstance(wp, list) else ""
inv = d.get("invocationNum", "")
out["inv"]  = "" if inv == "" else str(inv)
out["idle"] = "true" if d.get("fullyIdle") else ""
tc = d.get("toolCall") or {}
out["tool"] = tc.get("name", "") if isinstance(tc, dict) else ""
a = tc.get("args") or {} if isinstance(tc, dict) else {}
if not isinstance(a, dict): a = {}
def first(*keys):
    for k in keys:
        v = a.get(k)
        if v: return v
    return ""
out["file"]     = first("TargetFile", "AbsolutePath", "NotebookPath")
out["cmd"]      = first("CommandLine")
out["pattern"]  = first("Pattern")
out["query"]    = first("Query", "query")
out["url"]      = first("Url")
out["prompt"]   = first("Prompt")
out["desc"]     = first("Description", "Instruction")
out["dirpath"]  = first("DirectoryPath", "SearchDirectory")
out["skillfile"] = "true" if a.get("IsSkillFile") else ""
sub = a.get("Subagents") or []
agtype = ""
if isinstance(sub, list) and sub and isinstance(sub[0], dict):
    agtype = sub[0].get("TypeName", "") or sub[0].get("Role", "")
out["agtype"] = agtype or clean(a.get("TypeName", "")) or ""
for k, v in out.items():
    print(k + "\t" + clean(v))
'
  elif command -v jq >/dev/null 2>&1; then
    printf '%s' "$RAW" | jq -r '
      def clean: tostring | gsub("[\t\n\r]"; " ") | .[0:500];
      [
        ["sid",  (.conversationId // "")],
        ["ws",   ((.workspacePaths // [])[0] // "")],
        ["inv",  (if .invocationNum == null then "" else (.invocationNum|tostring) end)],
        ["idle", (if .fullyIdle == true then "true" else "" end)],
        ["tool", (.toolCall.name // "")],
        ["file", (.toolCall.args.TargetFile // .toolCall.args.AbsolutePath // .toolCall.args.NotebookPath // "")],
        ["cmd",  (.toolCall.args.CommandLine // "")],
        ["pattern", (.toolCall.args.Pattern // "")],
        ["query",   (.toolCall.args.Query // .toolCall.args.query // "")],
        ["url",     (.toolCall.args.Url // "")],
        ["prompt",  (.toolCall.args.Prompt // "")],
        ["desc",    (.toolCall.args.Description // .toolCall.args.Instruction // "")],
        ["dirpath", (.toolCall.args.DirectoryPath // .toolCall.args.SearchDirectory // "")],
        ["skillfile", (if .toolCall.args.IsSkillFile == true then "true" else "" end)],
        ["agtype", ((.toolCall.args.Subagents // [])[0].TypeName // .toolCall.args.TypeName // "")]
      ] | .[] | .[0] + "\t" + (.[1] | clean)
    ' 2>/dev/null
  fi
  # No python3 and no jq: emit nothing — every handler below degrades to a
  # safe default output for its event.
}

sid="" ws="" inv="" idle="" tool="" file="" cmd="" pattern="" query="" url=""
prompt="" desc="" dirpath="" skillfile="" agtype=""
while IFS=$(printf '\t') read -r k v; do
  # shellcheck disable=SC2034 # skillfile parsed for parity with agy_hook.py payload; not consumed downstream yet
  case "$k" in
    sid) sid=$v ;; ws) ws=$v ;; inv) inv=$v ;; idle) idle=$v ;;
    tool) tool=$v ;; file) file=$v ;; cmd) cmd=$v ;; pattern) pattern=$v ;;
    query) query=$v ;; url) url=$v ;; prompt) prompt=$v ;; desc) desc=$v ;;
    dirpath) dirpath=$v ;; skillfile) skillfile=$v ;; agtype) agtype=$v ;;
  esac
done <<EOF
$(parse_payload)
EOF

# Run project-relative scripts from the workspace root (Antigravity does not
# guarantee the hook cwd; guard globs, git and the office inbox rely on $PWD).
[ -n "$ws" ] && [ -d "$ws" ] && cd "$ws" 2>/dev/null || true

# ------------------------------------------------------- tool-name mapping ----
# Antigravity tool -> the Claude Code name the downstream scripts expect.
ctool=""
case "$tool" in
  write_to_file)              ctool=Write ;;
  replace_file_content)       ctool=Edit ;;
  multi_replace_file_content) ctool=MultiEdit ;;
  view_file)                  ctool=Read ;;
  list_dir)                   ctool=LS ;;
  find_by_name)               ctool=Glob ;;
  grep_search)                ctool=Grep ;;
  run_command)                ctool=Bash ;;
  search_web)                 ctool=WebSearch ;;
  read_url_content)           ctool=WebFetch ;;
  invoke_subagent)            ctool=Task ;;
  "")                         ctool="" ;;
  *)                          ctool=$tool ;;
esac

# Skill detection: Antigravity has no Skill tool — skills activate when the
# agent reads a SKILL.md (view_file carries IsSkillFile). Recover the name.
skill=""
if [ "$tool" = "view_file" ] && [ -n "$file" ]; then
  case "$file" in
    */skills/forge-*)
      skill=$(printf '%s' "$file" | sed -E 's#.*/skills/(forge-[a-z0-9-]+)(/.*)?$#\1#')
      case "$skill" in forge-*) ;; *) skill="" ;; esac
      ;;
  esac
fi

# ------------------------------------------- synthesized Claude-style JSON ----
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

payload="{\"session_id\":\"$(esc "$sid")\",\"hook_event_name\":\"$(esc "$EVENT")\""
[ -n "$ctool" ] && payload="$payload,\"tool_name\":\"$(esc "$ctool")\""
payload="$payload,\"tool_input\":{\"_agy\":true"
[ -n "$file" ]    && payload="$payload,\"file_path\":\"$(esc "$file")\""
[ -n "$cmd" ]     && payload="$payload,\"command\":\"$(esc "$cmd")\""
[ -n "$pattern" ] && payload="$payload,\"pattern\":\"$(esc "$pattern")\""
[ -n "$query" ]   && payload="$payload,\"query\":\"$(esc "$query")\""
[ -n "$url" ]     && payload="$payload,\"url\":\"$(esc "$url")\""
[ -n "$desc" ]    && payload="$payload,\"description\":\"$(esc "$desc")\""
[ -n "$dirpath" ] && payload="$payload,\"path\":\"$(esc "$dirpath")\""
[ -n "$prompt" ]  && payload="$payload,\"prompt\":\"$(esc "$prompt")\""
[ -n "$agtype" ]  && payload="$payload,\"subagent_type\":\"$(esc "$agtype")\""
[ -n "$skill" ]   && payload="$payload,\"skill\":\"$(esc "$skill")\""
# Antigravity subagents are asynchronous by design: mark spawns as background
# so agent-status uses its B-entry lifecycle (TTL-pruned; there is no
# SubagentStop equivalent to deliver an exact completion signal).
[ "$ctool" = "Task" ] && payload="$payload,\"run_in_background\":true"
payload="$payload}}"

feed() { # feed <script> [args...] — run a hooks/scripts helper, discard output
  printf '%s' "$payload" | bash "$SCRIPTS/$1" "${@:2}" >/dev/null 2>&1
  return 0
}

json_str() { # JSON-encode $1 (multiline-safe) — prints a quoted JSON string
  if [ -n "$PY" ]; then
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  else
    printf '%s' "$1" | awk '
      BEGIN { ORS = ""; print "\"" }
      {
        gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "")
        if (NR > 1) print "\\n"
        print
      }
      END { print "\"" }'
  fi
}

# ------------------------------------------------------------------ events ----
case "$EVENT" in

PreToolUse)
  feed now-status.sh tool
  feed hook-logger.sh pre
  case "$ctool" in
    Write|Edit|MultiEdit|NotebookEdit)
      g=$(printf '%s' "$payload" | bash "$SCRIPTS/guard.sh" 2>/dev/null || true)
      case "$g" in
        *'"permissionDecision":"deny"'*)
          reason=$(printf '%s' "$g" | sed -E 's/.*"permissionDecisionReason":"([^"]*)".*/\1/')
          printf '{"decision":"deny","reason":"%s"}\n' "$(esc "$reason")"
          exit 0
          ;;
      esac
      ;;
    Task)
      feed agent-status.sh start
      ;;
  esac
  [ -n "$skill" ] && feed skill-status.sh capture
  # "ask" = Antigravity's default gating (prompts only where the user has not
  # already granted access). Never "allow": this hook must not weaken security.
  printf '{"decision":"ask"}\n'
  ;;

PostToolUse)
  feed hook-logger.sh post
  [ "$ctool" = "Task" ] && feed agent-status.sh stop
  printf '{}\n'
  ;;

PreInvocation)
  inject=""
  add_step() {
    [ -z "$1" ] && return 0
    inject="${inject}${inject:+,}{\"ephemeralMessage\":$(json_str "$1")}"
  }
  if [ "$inv" = "0" ]; then
    feed hook-logger.sh session-start
    # -- Tier-1 context injection (Claude Code: SessionStart stdout) --
    CTX=context
    { [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
    if [ -f "$CTX/context-digest.md" ]; then
      add_step "[Context Forge] This project uses the Context Forge methodology with tiered context loading; its context directory is $CTX/ (substitute it wherever skills mention context/). The compact digest below is Tier 1 — always in effect. Read further context files ONLY as the task requires (see the tier map at the bottom of the digest); when starting implementation work, also read $CTX/progress-tracker.md for live state. Never guess: if a decision depends on a file you have not read, read it first. Digest:
$(cat "$CTX/context-digest.md")"
    elif [ -f "$CTX/progress-tracker.md" ]; then
      add_step "[Context Forge] This project uses the Context Forge methodology; its context directory is $CTX/. Before implementing or making any architectural decision, read the entry point (AGENTS.md or CLAUDE.md) and the files in $CTX/ in order. Honor the invariants in $CTX/architecture.md and the rules in $CTX/ai-workflow-rules.md. Current project state from $CTX/progress-tracker.md:
$(cat "$CTX/progress-tracker.md")"
    fi
    bash "$ROOT/skills/forge-init/scripts/migrate-schema.sh" --auto >/dev/null 2>&1 || true
    add_step "$(bash "$ROOT/skills/forge-reconcile/scripts/detect-oob.sh" --hook 2>/dev/null || true)"
    if [ -f "$HOME/.claude/forge-office/autostart" ]; then
      bash "$ROOT/skills/forge-office/scripts/forge-office.sh" start --hook >/dev/null 2>&1 || true
    fi
  fi
  # -- forge-office inbox (Claude Code: UserPromptSubmit stdout), every turn --
  add_step "$(printf '%s' "$RAW" | bash "$SCRIPTS/office-inbox.sh" 2>/dev/null || true)"
  if [ -n "$inject" ]; then
    printf '{"injectSteps":[%s]}\n' "$inject"
  else
    printf '{}\n'
  fi
  ;;

Stop)
  feed hook-logger.sh stop-pre
  feed track.sh
  feed skill-status.sh idle
  feed now-status.sh clear
  feed agent-status.sh turnend
  feed hook-logger.sh stop
  if [ "$idle" = "true" ]; then
    # Closest equivalent of Claude Code's SessionEnd: the loop terminated and
    # no background work remains.
    feed hook-logger.sh session-end
    feed agent-status.sh end
  fi
  # Anything other than "continue" allows the stop.
  printf '{"decision":"ok"}\n'
  ;;

*)
  printf '{}\n'
  ;;
esac
exit 0
