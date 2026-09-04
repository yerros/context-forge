# Code Standards

<!-- Rule cards. One card per rule — an ID, a severity, who enforces it, and a
     concrete ✗/✓ pair. A rule without an example is an opinion: reviewers read
     it differently every time. Reviews cite the ID (CS-007), never the prose.
       enforced: tool   → also encoded as a pattern in rules.txt (or the linter);
                          the tool catches it, the reviewer only confirms.
       enforced: review → judgment call; the ✗/✓ pair is the calibration.
     IDs are stable: never renumber, never reuse a deleted ID. -->

## General

### CS-001 · Important · enforced: review
[Rule — e.g. Keep modules small and single-purpose.]
```
✗ [one small snippet that violates the rule]
✓ [the same snippet, fixed]
```

### CS-002 · Important · enforced: review
[Rule — e.g. Fix root causes; do not layer workarounds.]
```
✗ [snippet]
✓ [snippet]
```

## [Language — e.g. TypeScript]

### CS-010 · Critical · enforced: tool
[Rule — e.g. No `any`; use explicit interfaces or narrowly scoped types.]
```
✗ function parse(input: any) { … }
✓ function parse(input: unknown): Config { … }
```

### CS-011 · Critical · enforced: review
[Rule — e.g. Validate unknown external input at system boundaries before trusting it.]
```
✗ const body = await req.json(); db.insert(body)
✓ const body = BodySchema.parse(await req.json()); db.insert(body)
```

## [Framework — e.g. Next.js]

### CS-020 · Important · enforced: review
[Convention — e.g. Default to server components; add `use client` only when browser interactivity requires it.]
```
✗ [snippet]
✓ [snippet]
```

## Styling

### CS-030 · Important · enforced: tool
[Rule — e.g. Use design tokens, never raw hex values.]
```
✗ color: #1a73e8
✓ color: var(--color-primary)
```

## API Routes

### CS-040 · Critical · enforced: review
[Rule — e.g. Enforce auth and ownership before any mutation.]
```
✗ [snippet]
✓ [snippet]
```

## Data and Storage

### CS-050 · Important · enforced: review
[Rule — e.g. Metadata in the database; large generated content in blob storage.]
```
✗ [snippet]
✓ [snippet]
```

## File Organization

- `[folder]/` — [What belongs here]
- `[folder]/` — [What belongs here]
- `[folder]/` — [What belongs here]
