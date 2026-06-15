#!/usr/bin/env bash
# PreToolUse guard — deterministic, zero model tokens.
# Reads the tool-call JSON on stdin, extracts the target file path, and denies
# edits to generated/lock/vendor files or any glob listed in context/protected-paths.
# Allows everything else (exit 0, no output). Never calls a model.

set -u
input=$(cat)

# Extract the file_path string value (single-line JSON token; safe even if the
# JSON is multi-line or contains a large "content" field).
fp=$(printf '%s' "$input" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/^"file_path"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')

# Not a path-bearing tool (e.g. no file_path) -> allow.
[ -z "$fp" ] && exit 0

deny() {
  # Fixed, pre-escaped reason string -> always valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Built-in never-hand-edit patterns (essentially zero false-positive risk).
case "$fp" in
  node_modules/*|*/node_modules/*|.git/*|*/.git/*)
    deny "context-forge: this path is inside a vendor/.git directory and should not be edited by hand." ;;
  *.lock|*-lock.json|*-lock.yaml|package-lock.json|pnpm-lock.yaml|yarn.lock|Cargo.lock|poetry.lock|composer.lock)
    deny "context-forge: lock files are generated and should not be hand-edited; change the manifest and re-resolve instead." ;;
esac

# User-configured protected globs: one glob per line in context/protected-paths
# (lines starting with # are comments). Matches against the path or its basename.
if [ -f context/protected-paths ]; then
  base=${fp##*/}
  while IFS= read -r pat || [ -n "$pat" ]; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2254
    case "$fp" in $pat) deny "context-forge: this file matches a protected path in context/protected-paths." ;; esac
    # shellcheck disable=SC2254
    case "$base" in $pat) deny "context-forge: this file matches a protected path in context/protected-paths." ;; esac
  done < context/protected-paths
fi

exit 0
