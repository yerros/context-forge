---
name: forge-decision
description: >
  This skill should be used to log an architecture decision in a Six-File Context
  Methodology project — phrases like "forge-decision", "log this decision", "record an
  ADR", "we decided to...", "document why we chose X", or "add a decision record". It
  appends a structured ADR entry to context/decisions.md.
metadata:
  version: "0.1.0"
---

# forge-decision

Record architecture decisions as lightweight ADRs (Architecture Decision Records) so the
"why" behind the system is never lost. Decisions live in `context/decisions.md`.

## When to log

Log a decision whenever the project makes a choice that shapes the system and would be
expensive or confusing to reverse silently: picking/replacing a technology, changing a
boundary or storage model, adding or changing an invariant, choosing a pattern that
other code must follow.

## How

1. If `context/decisions.md` doesn't exist, create it from the bundled template at
   `${CLAUDE_PLUGIN_ROOT}/skills/forge-decision/templates/decisions.md`.
2. Determine the next ADR number (increment the highest existing one).
3. Append a new entry using this structure:

```
## ADR-NNN: <short title>

- **Date:** YYYY-MM-DD
- **Status:** Accepted        <!-- Proposed | Accepted | Superseded by ADR-XXX -->

### Context
What forces are at play — the problem, constraints, and options considered.

### Decision
What was decided, stated plainly.

### Consequences
What this makes easier, what it makes harder, and any follow-up needed.
```

4. If the decision changes an invariant, the stack, or a boundary, also update
   `context/architecture.md` to match — the ADR explains *why*, architecture.md states
   the current *rule*.
5. If a new decision reverses an old one, set the old ADR's status to
   `Superseded by ADR-NNN` rather than deleting it.

## Output

Confirm the ADR number and title written, and note any architecture.md update made.
