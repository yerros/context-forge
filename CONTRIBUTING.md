# Contributing to Context Forge

Thanks for your interest in improving Context Forge! This document explains how the plugin
is structured and how to propose changes.

## Ways to contribute

- **Report bugs** or unexpected behavior by opening an issue with steps to reproduce.
- **Suggest features** — open an issue describing the problem before sending a large PR.
- **Improve skills, hooks, templates, or docs** via a pull request.

## Project layout

```
.claude-plugin/plugin.json       # plugin manifest
.claude-plugin/marketplace.json  # marketplace catalog
skills/<name>/SKILL.md           # one directory per skill
skills/forge-init/templates/   # the six context templates + entry point
skills/forge-init/references/  # stack profiles
skills/forge-init/scripts/     # deterministic detector (detect.sh)
hooks/hooks.json                 # SessionStart, Stop, PreToolUse
```

## Authoring guidelines

- **Skills are instructions for Claude**, not documentation for the user. Write the body
  in imperative voice ("Read the file…", not "You should read…").
- Keep each `SKILL.md` focused and under ~3,000 words; move long material into
  `references/`.
- The frontmatter `description` must be third-person and include concrete trigger phrases.
- Use `${CLAUDE_PLUGIN_ROOT}` for any intra-plugin path; never hardcode absolute paths.
- Prefer deterministic scripts over prompts when correctness matters (see `detect.sh`).
- Keep all content in English.

## Develop and test locally

1. Add this directory as a local marketplace and install the plugin:

   ```shell
   /plugin marketplace add ./context-forge
   /plugin install context-forge@yerros
   ```

2. Validate structure and JSON:

   ```bash
   claude plugin validate .
   ```

3. Exercise the skills in a throwaway project (both a fresh repo and one that already has
   a `context/` folder) and confirm the detector verdicts behave as expected.

## Versioning and releases

This project follows [Semantic Versioning](https://semver.org/).

- Bump `version` in **both** `.claude-plugin/plugin.json` and the plugin entry in
  `.claude-plugin/marketplace.json` on every release. Claude Code only delivers updates to
  users when the version string changes.
- Record changes in [CHANGELOG.md](./CHANGELOG.md) under a new version heading.

## Pull request checklist

- [ ] `claude plugin validate .` passes.
- [ ] Any new skill has a clear, third-person `description` with trigger phrases.
- [ ] Docs (README/CHANGELOG) updated if behavior changed.
- [ ] Version bumped in both manifests if releasing.
- [ ] No hardcoded paths; English only.

## Code of conduct

Be respectful and constructive. Assume good faith and keep discussions focused on the
work.
