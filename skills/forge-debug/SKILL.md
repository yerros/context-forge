---
name: forge-debug
description: >
  This skill should be used when implementation is stuck or the agent keeps getting
  something wrong in a Six-File Context Methodology project — phrases like
  "forge-debug", "this keeps failing", "the agent can't fix this", "we're going in
  circles", "stuck on a bug", or "it broke again". It runs a disciplined stop-and-diagnose
  strategy instead of thrashing with more guesses.
metadata:
  version: "0.18.2"
---

# forge-debug

When the same problem resists two or more fix attempts, stop guessing. More attempts
without a model of the failure just compounds damage. Switch to this disciplined loop.

(A fresh bug report that isn't stuck yet enters through `forge-fix`, which triages
and hands off here when the cause is non-obvious. After this loop resolves it,
closing — tracker, lesson, `fix/` branch — follows `forge-fix` step 6.)

## Argument

Text after the command describes the stuck problem (e.g. `/forge-debug the websocket
reconnect keeps failing`) — treat it as the starting symptom for step 1. No argument
→ take the failure from the current conversation, or ask for it precisely.

## Stop condition

If you've tried to fix something twice and it still fails, do NOT try a third blind fix.
Run this process.

## The loop

### 1. State the failure precisely

Write down: what was expected, what actually happens, the exact error or wrong output,
and when it started (which unit/change introduced it). Vague symptoms produce vague fixes.

### 2. Reproduce reliably

Establish the smallest, repeatable reproduction. If it can't be reproduced on demand,
the first job is making it reproducible — not fixing it.

### 3. Re-read the context

Read `context/lessons.md` first (if present) — the failure may already be a known
lesson with a known rule. Then read `context/architecture.md` (invariants), the
relevant spec in `context/specs/`, and `context/code-standards.md`. Many "bugs" are
the implementation having drifted from the documented system. Check whether an
invariant was violated — that's often the root cause.

### 4. Isolate

Narrow the failure to one layer/boundary. For the legwork, the `forge-scout` agent
(haiku-pinned, mission "failure isolation") can trace the code path, find recent
related changes, and run the reproduction — returning the narrowest suspect
component with evidence, cheaply. Bisect: disable or stub parts until the failure
disappears, then reintroduce until it returns. Confirm the actual culprit before
proposing a fix. Distinguish root cause from symptom — do not layer a workaround
over a symptom (that's a code-standards violation). **The diagnosis and hypothesis
forming stay in this session** — they need the full conversation context; only
evidence gathering is delegated.

### 5. Form hypotheses, then present options

List the 1–3 most likely root causes with the evidence for each. For each, give the fix,
its blast radius, and the risk. **Present these options to the user rather than
auto-applying** when the cause is non-obvious or the fix touches multiple files.

### 6. Fix the root cause, in scope

Apply the smallest fix that addresses the root cause. Stay within the unit's scope. Then
re-run the reproduction and the unit's verification checklist to confirm.

### 7. Record it

If the bug came from a wrong assumption or a missing rule, add or clarify the relevant
rule in `code-standards.md` or `architecture.md`, and note it in `progress-tracker.md`
so it doesn't recur. If it changed an architectural decision, log it via `forge-decision`.

If the root cause is likely to recur (or cost real effort to find) but isn't a
convention that belongs in a context file yet, distill it to **one lesson line** and
append it to `context/lessons.md` per the memory contract in
`${CLAUDE_PLUGIN_ROOT}/skills/forge-lesson/references/memory.md` — show the user the
line being added. Skip trivial one-off bugs.

## When the agent keeps getting it wrong

If repeated attempts fail, the spec or context is probably ambiguous. Stop coding and
fix the source of truth: make the spec or the relevant context file unambiguous first,
then retry the build. Garbage spec in, garbage code out.
