#!/usr/bin/env bats
# Retrieval index (skills/forge-init/scripts/forge-index.sh): build, refresh, ranking.

load helpers/common

INDEX="$PLUGIN_ROOT/skills/forge-init/scripts/forge-index.sh"

setup() {
  setup_project
  command -v sqlite3 >/dev/null || skip "sqlite3 not installed"
  sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(a, tokenize='porter unicode61');" 2>/dev/null \
    || skip "sqlite3 without FTS5"
  mkdir -p context/specs
  cat > context/decisions.md <<'EOF'
# Decisions

## Webhook retries

We retry payment webhooks three times with backoff.

## Logging

Structured JSON logs everywhere.
EOF
  cat > context/specs/07-webhook.md <<'EOF'
# Unit 07

## Implementation

```bash
# not a heading: install deps
npm ci
```

Handle the retrying of webhooks.
EOF
}

@test "index: build counts sections and ignores # lines inside code fences" {
  run bash "$INDEX" build
  [ "$status" -eq 0 ]
  [[ "$output" == *'indexed 6 sections'* ]]   # 3 + 3, not 7
  n=$(sqlite3 context/.index.db "SELECT count(*) FROM docs WHERE title LIKE 'not a heading%';")
  [ "$n" -eq 0 ]
}

@test "index: porter stemming matches morphological variants" {
  bash "$INDEX" build >/dev/null
  run bash "$INDEX" query "retried webhook"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Webhook retries'* ]]
}

@test "index: title hit outranks a body-only hit" {
  bash "$INDEX" build >/dev/null
  run bash "$INDEX" query "logging" 1
  [[ "$output" == *'[Logging]'* ]]
}

@test "index: stopwords are dropped, all-stopword query falls back" {
  bash "$INDEX" build >/dev/null
  run bash "$INDEX" query "how do we do the logging"
  [[ "$output" == *'[Logging]'* ]]
  run bash "$INDEX" query "the and of"
  [ "$status" -eq 0 ]
}

@test "index: refresh rebuilds only when a markdown file is newer" {
  bash "$INDEX" build >/dev/null
  touch -t 202001010000 context/.index.db
  printf '# Fresh\n\nbrand new zebra section\n' > context/lessons.md
  run bash "$INDEX" refresh
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$INDEX" query zebra
  [[ "$output" == *'zebra'* ]]
  # nothing newer now -> refresh leaves the db untouched
  before=$(stat -f %m context/.index.db 2>/dev/null || stat -c %Y context/.index.db)
  sleep 1
  bash "$INDEX" refresh
  after=$(stat -f %m context/.index.db 2>/dev/null || stat -c %Y context/.index.db)
  [ "$before" = "$after" ]
}

@test "index: refresh without an index is a silent no-op" {
  run bash "$INDEX" refresh
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f context/.index.db ]
}
