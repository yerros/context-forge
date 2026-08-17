# Context Forge on Antigravity — term mapping

This workspace has the context-forge plugin installed. Its skills were written
for Claude Code; when a skill mentions a Claude Code concept, apply the
Antigravity equivalent:

- "Task tool" / "spawn a subagent via Task" → use the `invoke_subagent` tool.
  The plugin's custom agents (forge-reviewer, forge-architect, forge-scout,
  forge-tester, forge-failure-hunter, forge-aligner, forge-archivist,
  forge-typer, forge-commenter) are available as custom subagents.
- "CLAUDE.md" → the project entry point. On Antigravity prefer `AGENTS.md`;
  if only CLAUDE.md exists, read that.
- "Skill tool" / "invoke the skill" → skills are available directly; in the
  Antigravity CLI each forge skill is also a slash command (e.g. `/forge-build`).
- `${CLAUDE_PLUGIN_ROOT}` → `$HOME/.gemini/antigravity-cli/plugins/context-forge`
  (already substituted in the bundled skill files).
- Tools: Read→view_file, Write→write_to_file, Edit→replace_file_content,
  Grep→grep_search, Glob→find_by_name, Bash→run_command.

Everything else in the skills — the methodology, file layout (`context/` or
`.forge/`), specs, the build/verify loop, invariants — applies unchanged.
