#!/usr/bin/env bash
# agent-inject.sh — PreToolUse ^(Task|Agent)$: give every subagent Tier 1.
#
# The SessionStart digest reaches the main session only; a subagent starts with
# a blank context and whatever the caller pasted into its prompt. This hook
# appends a short pointer to the subagent's prompt so it reads the digest and
# honors the invariants before deciding anything. A pointer, not the digest:
# ~60 tokens per launch instead of ~600.
#
# Rewrites tool_input via hookSpecificOutput.updatedInput, which needs a real
# JSON round-trip — python3 (already required by the Antigravity build). No
# python3, no digest, or a prompt that already carries the marker -> passthrough.
# Never denies. Always exits 0. stdout is the last write.

set -u
input=$(cat 2>/dev/null || true)

CTX=context
{ [ -f .forge/progress-tracker.md ] || [ -f .forge/context-digest.md ]; } && CTX=.forge
[ -f "$CTX/context-digest.md" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CTX="$CTX" python3 - "$input" <<'PY' 2>/dev/null || true
import json, os, sys
try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
ti = payload.get("tool_input")
if not isinstance(ti, dict):
    sys.exit(0)
field = next((f for f in ("prompt", "request", "objective", "question", "query", "task") if isinstance(ti.get(f), str)), None)
if field is None or "[Context Forge]" in ti[field]:
    sys.exit(0)
ctx = os.environ["CTX"]
note = (
    "\n\n[Context Forge] This project uses the Context Forge methodology; its context directory is "
    f"{ctx}/. Before deciding anything, read {ctx}/context-digest.md (Tier 1), then only the context "
    f"files your task needs. Honor the invariants in {ctx}/architecture.md and the rules in "
    f"{ctx}/ai-workflow-rules.md. Never guess: if a decision depends on a file you have not read, read it first."
)
updated = dict(ti)
updated[field] = ti[field] + note
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": updated}}))
PY
exit 0
