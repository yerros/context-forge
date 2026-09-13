#!/usr/bin/env bash
# forge-index.sh — deterministic, zero-model-token retrieval over context artifacts.
# The markdown files remain the single source of truth; the index is a rebuildable
# cache (SQLite FTS5, add <context-dir>/.index.db to .gitignore).
#
#   forge-index.sh build              # (re)build the index — fast full rebuild
#   forge-index.sh refresh            # rebuild only if a .md is newer than the index (hook use)
#   forge-index.sh query "terms" [k]  # top-k sections: path:line, title, snippet
#
# Indexes every markdown section (split on # headings, fenced code blocks kept
# intact) under the context dir, including specs/, specs/archived/, decisions,
# lessons, patterns, and the progress archive — so history stays findable
# without ever being auto-read. Ranking: porter-stemmed BM25 with the section
# title weighted 5x (a heading hit is a navigational hit), stopwords dropped.

set -eu

# Context dir resolution (same rule as detect.sh).
CTX=context
[ -d .forge ] && { [ -f .forge/progress-tracker.md ] || [ -f .forge/project-overview.md ] || [ ! -d context ]; } && CTX=.forge
DB="$CTX/.index.db"

command -v sqlite3 >/dev/null 2>&1 || { echo "forge-index: sqlite3 not found" >&2; exit 1; }
[ -d "$CTX" ] || { echo "forge-index: no $CTX/ directory here" >&2; exit 1; }

mode=${1:-}

case "$mode" in
refresh)
  # Silent, for SessionStart: rebuild only when the index is missing or stale.
  [ -f "$DB" ] || exit 0
  [ -n "$(find "$CTX" -name '*.md' -type f -newer "$DB" -print -quit)" ] || exit 0
  exec "$0" build >/dev/null 2>&1
  ;;
build)
  tmp=$(mktemp)
  {
    echo "DROP TABLE IF EXISTS docs;"
    echo "CREATE VIRTUAL TABLE docs USING fts5(path, line UNINDEXED, title, body, tokenize='porter unicode61');"
    echo "BEGIN;"
    find "$CTX" -name '*.md' -type f | sort | while IFS= read -r f; do
      awk -v path="$f" '
        function esc(s) { gsub(/\x27/, "\x27\x27", s); return s }
        function flush() {
          if (body != "" || title != "") {
            printf "INSERT INTO docs VALUES(\x27%s\x27,%d,\x27%s\x27,\x27%s\x27);\n",
                   esc(path), startline, esc(title), esc(body)
          }
        }
        /^```/ { fence = !fence }
        /^#/ && !fence { flush(); title=$0; sub(/^#+[ ]*/,"",title); startline=NR; body=""; next }
        NR==1 { startline=1; title=path; body=$0; next }
        { body = body " " $0 }
        END { flush() }
      ' "$f"
    done
    echo "COMMIT;"
  } > "$tmp"
  sqlite3 "$DB" < "$tmp"
  rm -f "$tmp"
  n=$(sqlite3 "$DB" "SELECT count(*) FROM docs;")
  echo "forge-index: indexed $n sections into $DB"
  ;;
query)
  q=${2:-}
  [ -z "$q" ] && { echo "forge-index: usage: forge-index.sh query \"terms\" [k]" >&2; exit 1; }
  k=${3:-5}
  [ -f "$DB" ] || { echo "forge-index: no index — run 'forge-index.sh build' first" >&2; exit 1; }
  # Sanitize into FTS-safe OR-of-words (strips MATCH syntax pitfalls), drop
  # stopwords (fall back to the raw words when nothing else is left).
  words=$(printf '%s' "$q" | tr -cs '[:alnum:]' ' ' | tr '[:upper:]' '[:lower:]' | xargs)
  # shellcheck disable=SC2086  # intentional word split
  kept=$(printf '%s\n' $words | grep -vxE 'the|a|an|and|or|of|to|in|for|on|with|is|are|be|by|as|at|it|this|that|from|we|our|how|what|do|does|did' | xargs)
  [ -n "$kept" ] && words=$kept
  terms=$(printf '%s' "$words" | sed 's/ / OR /g')
  [ -z "$terms" ] && { echo "forge-index: empty query after sanitizing" >&2; exit 1; }
  # bm25 weights follow column order: path, line (unindexed), title, body.
  sqlite3 -separator '  ' "$DB" \
    "SELECT path || ':' || line, '[' || title || ']', snippet(docs, 3, '>>', '<<', '…', 12)
     FROM docs WHERE docs MATCH '$terms' ORDER BY bm25(docs, 1.0, 0.0, 5.0, 1.0) LIMIT $k;"
  ;;
*)
  echo "forge-index: usage: forge-index.sh build | refresh | query \"terms\" [k]" >&2
  exit 1
  ;;
esac
