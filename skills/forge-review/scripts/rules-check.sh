#!/usr/bin/env bash
# rules-check.sh — forge-review step 0: deterministic rule patterns over changed files.
#
#   rules-check.sh                 # changed files vs HEAD (staged + unstaged + untracked)
#   rules-check.sh --base <ref>    # changed files in <ref>...HEAD
#   rules-check.sh <file>...       # exactly these files
#
# Rules live in <context-dir>/rules.txt, one per line:
#   ID|Severity|glob|message|regex        (regex is the LAST field, so it may contain |)
# Output, one line per hit:  file:line: ID [Severity] message
# Exit 0 = clean (or no rules file), 1 = at least one hit, 2 = usage/setup error.
#
# ponytail: grep -E only. Upgrade to semgrep when a rule needs AST context.

set -eu

base=""
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { echo "rules-check: --base needs a ref" >&2; exit 2; }
            base=$2; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) files+=("$1"); shift ;;
  esac
done

if [ -f ".forge/rules.txt" ]; then RULES=".forge/rules.txt"
elif [ -f "context/rules.txt" ]; then RULES="context/rules.txt"
else echo "rules-check: no rules.txt in context/ or .forge/ — nothing to check"; exit 0; fi

if [ ${#files[@]} -eq 0 ]; then
  if [ -n "$base" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only "$base...HEAD")
  else
    while IFS= read -r f; do files+=("$f"); done < <(
      { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
  fi
fi
[ ${#files[@]} -gt 0 ] || { echo "rules-check: no changed files"; exit 0; }

hits=0
while IFS='|' read -r id sev glob msg regex; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "$regex" ] || { echo "rules-check: malformed rule line for $id (need 5 fields)" >&2; exit 2; }
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    # shellcheck disable=SC2254  # glob from the rule file is meant to expand
    case "$f" in $glob|*/$glob) ;; *) continue ;; esac
    while IFS= read -r line; do
      printf '%s:%s: %s [%s] %s\n' "$f" "${line%%:*}" "$id" "$sev" "$msg"
      hits=$((hits + 1))
    done < <(grep -nE -- "$regex" "$f" 2>/dev/null | cut -d: -f1 || true)
  done
done < "$RULES"

[ "$hits" -eq 0 ] && { echo "rules-check: clean (${#files[@]} files, rules from $RULES)"; exit 0; }
exit 1
