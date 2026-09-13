#!/usr/bin/env bats
# UserPromptSubmit correction capture (hooks/scripts/lesson-candidates.sh).

load helpers/common

LC="$PLUGIN_ROOT/hooks/scripts/lesson-candidates.sh"
F=context/.lesson-candidates.md

setup() { setup_project; mkdir -p context; printf 't\n' > context/progress-tracker.md; }
p() { printf '{"session_id":"s","prompt":"%s"}' "$1"; }

@test "candidates: an English correction is captured once" {
  run bash "$LC" <<< "$(p "no, don't retry on 4xx; only retry on 5xx")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q "only retry on 5xx" "$F"
  bash "$LC" <<< "$(p "no, don't retry on 4xx; only retry on 5xx")"
  [ "$(grep -c '^- ' "$F")" -eq 1 ]
}

@test "candidates: an Indonesian correction is captured" {
  bash "$LC" <<< "$(p 'jangan pakai any, pakai tipe eksplisit di semua handler')"
  grep -q 'tipe eksplisit' "$F"
}

@test "candidates: questions, short prompts, plain requests, envelopes, slash commands are ignored" {
  for t in "no, should we retry on 4xx?" "no, stop" "add a retry to the fetch helper, with backoff" "<system-reminder>not a decision, really</system-reminder>" "/forge-build unit 3, please"; do
    bash "$LC" <<< "$(p "$t")"
  done
  [ ! -f "$F" ]
}

@test "candidates: escaped newlines and quotes in the prompt are unescaped" {
  bash "$LC" <<< "$(p 'wrong, use \"ctx\" not \"context\";\nkeep it short')"
  grep -q 'use "ctx" not "context"; keep it short' "$F"
}

@test "candidates: non-forge project stays inert" {
  rm -rf context
  run bash "$LC" <<< "$(p 'no, do it the other way; the first was wrong')"
  [ -z "$output" ]; [ ! -d context ]
}
