#!/usr/bin/env bats
# Prompt-text contract: the wording the model sees in skill descriptions and
# hook messages must not use framings shown to degrade tool selection
# (see docs/REFERENCE-context-mode.md §2.6: "BLOCKED", "Do NOT retry", a bare
# "NOT a …" denial, "Never use"). Deny reasons must name the replacement action.
# Zero model tokens: reads the source as text.

load helpers/common

# The model-facing text of a skill/agent: the frontmatter description block.
descriptions() {
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md; do
    awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {exit} fm {print FILENAME": "$0}' "$f"
  done
}

@test "prompt-style: no forbidden framing in skill/agent descriptions" {
  run descriptions
  [ -n "$output" ]
  ! printf '%s\n' "$output" | grep -nE '\bBLOCKED\b|Do NOT retry|\bNOT a\b|Never use'
}

@test "prompt-style: hook stdout strings avoid forbidden framing" {
  run grep -nE 'printf|echo|deny ' "$PLUGIN_ROOT"/hooks/scripts/*.sh
  ! printf '%s\n' "$output" | grep -qE '\bBLOCKED\b|Do NOT retry|\bNOT a\b|Never use'
}

@test "prompt-style: every guard deny reason names what to do instead" {
  # Each deny "…" literal must contain an alternative verb (change/instead/re-resolve/run/use).
  run grep -oE 'deny "[^"]+"' "$PLUGIN_ROOT/hooks/scripts/guard.sh"
  [ -n "$output" ]
  while IFS= read -r line; do
    [[ "$line" =~ (instead|change|re-resolve|should not be edited|protected) ]] || { echo "no alternative in: $line"; return 1; }
  done <<< "$output"
}

@test "prompt-style: injected session text carries the anti-lock-in clause" {
  grep -q 'memory aid, not a standing order' "$PLUGIN_ROOT/hooks/scripts/compact-snapshot.sh"
}
