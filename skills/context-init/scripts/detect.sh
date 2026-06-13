#!/usr/bin/env bash
# detect.sh — deterministic report of a project's Six-File Context state.
# Run from the project root. Output is a stable, line-based report the skill
# parses to decide between SETUP (fresh), ADOPT (already present), or REPAIR
# (present but incomplete). Read-only: this script never writes anything.

set -u

CTX="context"
SIX="project-overview architecture ui-context code-standards ai-workflow-rules progress-tracker"

say() { printf '%s\n' "$1"; }

# --- entry point ---
ENTRY="none"
[ -f "AGENTS.md" ] && ENTRY="AGENTS.md"
[ -f "CLAUDE.md" ] && ENTRY="CLAUDE.md"   # CLAUDE.md wins if both exist

entry_links_context="no"
if [ "$ENTRY" != "none" ] && grep -q "context/" "$ENTRY" 2>/dev/null; then
  entry_links_context="yes"
fi

# --- context dir + six files ---
ctx_dir="no"; [ -d "$CTX" ] && ctx_dir="yes"

present=0; missing=0; missing_list=""
declare_present=""
for f in $SIX; do
  if [ -f "$CTX/$f.md" ]; then
    present=$((present+1)); declare_present="$declare_present $f"
  else
    missing=$((missing+1)); missing_list="$missing_list $f"
  fi
done

# --- unfilled template placeholders ([bracketed] text) per present file ---
# A high count means the file is still a blank template, not real content.
placeholder_total=0
placeholder_detail=""
for f in $SIX; do
  if [ -f "$CTX/$f.md" ]; then
    n=$(grep -oE '\[[^]]+\]' "$CTX/$f.md" 2>/dev/null | wc -l | tr -d ' ')
    placeholder_total=$((placeholder_total + n))
    placeholder_detail="$placeholder_detail $f:$n"
  fi
done

# --- optional pieces ---
decisions="no"; [ -f "$CTX/decisions.md" ] && decisions="yes"
specs_dir="no"; [ -d "$CTX/specs" ] && specs_dir="yes"
build_plan="no"; [ -f "$CTX/specs/00-build-plan.md" ] && build_plan="yes"
spec_count=0
[ -d "$CTX/specs" ] && spec_count=$(find "$CTX/specs" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

# --- codebase signal (brownfield vs greenfield) ---
code="no"
if find . -maxdepth 2 \( -name package.json -o -name requirements.txt -o -name pyproject.toml \
   -o -name go.mod -o -name Cargo.toml -o -name pom.xml -o -name build.gradle \
   -o -name pubspec.yaml -o -name Package.swift \) \
   -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null | grep -q .; then
  code="yes"
fi

# --- verdict ---
# SETUP  : no context dir and no six files  -> fresh install
# ADOPT  : all six present and mostly filled -> recognize & reconcile gaps
# REPAIR : context exists but incomplete or still mostly template
verdict="SETUP"
if [ "$present" -gt 0 ]; then
  if [ "$missing" -eq 0 ] && [ "$placeholder_total" -le 12 ]; then
    verdict="ADOPT"
  else
    verdict="REPAIR"
  fi
fi

say "=== SIX-FILE CONTEXT: STATE REPORT ==="
say "verdict: $verdict"
say "context_dir: $ctx_dir"
say "six_files_present: $present/6"
say "present_files:$declare_present"
say "missing_files:${missing_list:- none}"
say "entry_point: $ENTRY"
say "entry_links_context: $entry_links_context"
say "unfilled_placeholders_total: $placeholder_total"
say "placeholders_by_file:$placeholder_detail"
say "decisions_md: $decisions"
say "specs_dir: $specs_dir"
say "build_plan: $build_plan"
say "spec_files: $spec_count"
say "codebase_detected: $code"
say "=== END REPORT ==="
