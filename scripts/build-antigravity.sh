#!/usr/bin/env bash
# build-antigravity.sh — generate the Antigravity CLI/IDE plugin bundle from
# this repo (single source of truth). Output: dist/antigravity/context-forge/
#
# Install the result with:
#   agy plugin install dist/antigravity/context-forge
#
# What gets transformed (docs: https://antigravity.google/docs/cli/plugins):
#   plugin.json   strict Antigravity schema — name + description only
#   agents/*.md   frontmatter: tools -> Antigravity tool names (validated
#                 against a whitelist; a typo hangs the subagent), model ->
#                 pro/flash, plus subagent/mainAgent/commandExecutionPolicy
#   hooks.json    generated in Antigravity's format; all four events route
#                 through hooks/antigravity/agy-hook.sh (the adapter)
#   skills/       copied verbatim except ${CLAUDE_PLUGIN_ROOT} -> installed
#                 plugin path
#   rules/        Antigravity-only term-mapping rule
#
# Requires: python3 (for exact JSON/frontmatter transforms).

set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT="$SRC/dist/antigravity/context-forge"
AGY_ROOT='$HOME/.gemini/antigravity-cli/plugins/context-forge'

command -v python3 >/dev/null 2>&1 || {
  echo "build-antigravity: python3 is required" >&2
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT/hooks/antigravity" "$OUT/rules" "$OUT/statusline"

# ------------------------------------------------------------- plugin.json ----
python3 - "$SRC" "$OUT" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
with open(f"{src}/.claude-plugin/plugin.json") as f:
    p = json.load(f)
manifest = {
    "$schema": "https://antigravity.google/schemas/v1/plugin.json",
    "name": p["name"],
    "description": p["description"],
}
with open(f"{out}/plugin.json", "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

# --------------------------------------------------------------- hooks.json ----
python3 - "$OUT" "$AGY_ROOT" <<'PY'
import json, sys
out, root = sys.argv[1], sys.argv[2]
adapter = f'bash "{root}/hooks/antigravity/agy-hook.sh"'
hooks = {
    "context-forge": {
        "PreToolUse": [
            {"matcher": "", "hooks": [
                {"type": "command", "command": f"{adapter} PreToolUse", "timeout": 15}
            ]}
        ],
        "PostToolUse": [
            {"matcher": "", "hooks": [
                {"type": "command", "command": f"{adapter} PostToolUse", "timeout": 10}
            ]}
        ],
        "PreInvocation": [
            {"type": "command", "command": f"{adapter} PreInvocation", "timeout": 20}
        ],
        "Stop": [
            {"type": "command", "command": f"{adapter} Stop", "timeout": 20}
        ],
    }
}
with open(f"{out}/hooks.json", "w") as f:
    json.dump(hooks, f, indent=2)
    f.write("\n")
PY

# ------------------------------------------------------------------- agents ----
mkdir -p "$OUT/agents"
python3 - "$SRC" "$OUT" <<'PY'
import glob, os, sys
src, out = sys.argv[1], sys.argv[2]

TOOL_MAP = {
    "Read": "view_file",
    "Write": "write_to_file",
    "Edit": "replace_file_content",
    "MultiEdit": "multi_replace_file_content",
    "Grep": "grep_search",
    "Glob": "find_by_name",
    "Bash": "run_command",
    "LS": "list_dir",
    "WebFetch": "read_url_content",
    "WebSearch": "search_web",
    "Task": "invoke_subagent",
}
# The full set Antigravity documents for custom subagents — used to validate
# our output (an unmapped/misspelled name hangs the subagent process).
AGY_TOOLS = {
    "view_file", "write_to_file", "replace_file_content",
    "multi_replace_file_content", "list_dir", "find_by_name", "grep_search",
    "search_web", "read_url_content", "run_command", "manage_task",
    "schedule", "list_permissions", "ask_permission", "invoke_subagent",
    "define_subagent", "send_message", "manage_subagents", "ask_question",
    "generate_image",
}
MODEL_MAP = {"opus": "pro", "sonnet": "pro", "haiku": "flash", "inherit": "inherit"}

failures = []
for path in sorted(glob.glob(f"{src}/agents/*.md")):
    name = os.path.basename(path)
    lines = open(path).read().split("\n")
    if lines[0] != "---":
        failures.append(f"{name}: no frontmatter")
        continue
    try:
        end = lines.index("---", 1)
    except ValueError:
        failures.append(f"{name}: unterminated frontmatter")
        continue

    front, body = lines[1:end], lines[end + 1:]
    new_front, saw_tools, saw_model = [], False, False
    for ln in front:
        if ln.startswith("tools:"):
            saw_tools = True
            tools = [t.strip() for t in ln.split(":", 1)[1].split(",") if t.strip()]
            mapped = []
            for t in tools:
                if t not in TOOL_MAP:
                    failures.append(f"{name}: unknown Claude tool '{t}'")
                    break
                mapped.append(TOOL_MAP[t])
            else:
                bad = [m for m in mapped if m not in AGY_TOOLS]
                if bad:
                    failures.append(f"{name}: invalid Antigravity tool(s) {bad}")
                new_front.append("tools:")
                new_front.extend(f"  - {m}" for m in mapped)
            continue
        if ln.startswith("model:"):
            saw_model = True
            m = ln.split(":", 1)[1].strip()
            if m not in MODEL_MAP:
                failures.append(f"{name}: unknown model '{m}'")
                continue
            new_front.append(f"model: {MODEL_MAP[m]}")
            continue
        new_front.append(ln)
    if not saw_tools:
        failures.append(f"{name}: frontmatter has no tools line")
    if not saw_model:
        new_front.append("model: inherit")
    new_front += [
        "subagent: true",
        "mainAgent: false",
        "commandExecutionPolicy: sandbox",
    ]

    with open(f"{out}/agents/{name}", "w") as f:
        f.write("\n".join(["---"] + new_front + ["---"] + body))

if failures:
    print("build-antigravity: agent transform FAILED:", file=sys.stderr)
    for x in failures:
        print(f"  - {x}", file=sys.stderr)
    sys.exit(1)
PY

# ------------------------------------------------------------------- skills ----
cp -R "$SRC/skills" "$OUT/skills"
find "$OUT" -name '.DS_Store' -delete
# Substitute the Claude Code plugin-root variable with the Antigravity install
# path in every text file of the bundle (exact literal replacement).
python3 - "$OUT" "$AGY_ROOT" <<'PY'
import os, sys
out, root = sys.argv[1], sys.argv[2]
needle = "${CLAUDE_PLUGIN_ROOT}"
for dirpath, _dirs, files in os.walk(f"{out}/skills"):
    for fn in files:
        if not fn.endswith((".md", ".sh", ".json", ".txt", ".yaml", ".yml")):
            continue
        p = os.path.join(dirpath, fn)
        with open(p, encoding="utf-8", errors="surrogateescape") as f:
            s = f.read()
        if needle in s:
            with open(p, "w", encoding="utf-8", errors="surrogateescape") as f:
                f.write(s.replace(needle, root))
PY

# -------------------------------------------------- hooks scripts + adapter ----
cp -R "$SRC/hooks/scripts" "$OUT/hooks/scripts"
cp "$SRC/hooks/antigravity/agy-hook.sh" "$OUT/hooks/antigravity/agy-hook.sh"
chmod +x "$OUT/hooks/antigravity/agy-hook.sh" "$OUT"/hooks/scripts/*.sh

# ---------------------------------------------------------- rules, extras ----
cp "$SRC/hooks/antigravity/antigravity-rules.md" "$OUT/rules/context-forge.md"
cp "$SRC/statusline/statusline.sh" "$OUT/statusline/statusline.sh"
cp "$SRC/LICENSE" "$OUT/LICENSE"

cat > "$OUT/README.md" <<EOF
# context-forge — Antigravity bundle

Generated by scripts/build-antigravity.sh — do not edit; edit the repo and
rebuild. Source: https://github.com/yerros/context-forge

Install:

    agy plugin install /path/to/this/directory

Then restart \`agy\` in your project. Verify with \`/hooks\` (one hook set,
"context-forge", on PreToolUse/PostToolUse/PreInvocation/Stop) and type
\`/forge-\` to see the skills as slash commands.

Optional status line (skill indicator · model · branch · context %):
copy statusline/statusline.sh to ~/.gemini/antigravity-cli/statusline.sh,
chmod +x it, and add to ~/.gemini/antigravity-cli/settings.json:

    { "statusLine": { "type": "command",
                      "command": "~/.gemini/antigravity-cli/statusline.sh" } }

Known platform differences (best-effort on Antigravity):
- Subagent completion has no exact signal (no SubagentStop event); the
  dashboard's agent list uses TTL-based cleanup instead.
- The forge-office inbox is delivered per model invocation (no
  UserPromptSubmit event).
EOF

# --------------------------------------------------------------- validation ----
python3 - "$OUT" <<'PY'
import glob, json, sys
out = sys.argv[1]
errs = []

for f in ("plugin.json", "hooks.json"):
    try:
        json.load(open(f"{out}/{f}"))
    except Exception as e:
        errs.append(f"{f}: invalid JSON — {e}")

p = json.load(open(f"{out}/plugin.json"))
extra = set(p) - {"$schema", "name", "description"}
if extra:
    errs.append(f"plugin.json: fields not allowed by schema: {extra}")
if not p.get("name"):
    errs.append("plugin.json: name missing")

for path in glob.glob(f"{out}/agents/*.md"):
    s = open(path).read()
    for key in ("subagent: true", "mainAgent: false", "tools:"):
        if key not in s:
            errs.append(f"{path.split('/')[-1]}: missing '{key}'")
    if "model: sonnet" in s or "model: haiku" in s or "model: opus" in s:
        errs.append(f"{path.split('/')[-1]}: Claude model name left behind")

n = len(glob.glob(f"{out}/skills/*/SKILL.md"))
if n < 20:
    errs.append(f"skills: only {n} SKILL.md files copied")

leftovers = []
import os
for dirpath, _d, files in os.walk(f"{out}/skills"):
    for fn in files:
        if fn.endswith((".md", ".sh")):
            if "${CLAUDE_PLUGIN_ROOT}" in open(os.path.join(dirpath, fn),
                    encoding="utf-8", errors="surrogateescape").read():
                leftovers.append(os.path.join(dirpath, fn))
if leftovers:
    errs.append(f"CLAUDE_PLUGIN_ROOT not substituted in: {leftovers[:3]}")

if errs:
    print("build-antigravity: VALIDATION FAILED:", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
PY

# Syntax-check every shell script in the bundle.
find "$OUT" -name '*.sh' -print0 | while IFS= read -r -d '' f; do
  bash -n "$f" || { echo "build-antigravity: bash -n failed: $f" >&2; exit 1; }
done

echo "build-antigravity: OK -> $OUT"
echo "install: agy plugin install $OUT"
