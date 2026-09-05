---
name: forge-gatekeeper
description: >
  This skill should be used as the last gate before a release in a Context Forge
  project — phrases like "forge-gatekeeper", "is this safe to ship", "production
  readiness review", "security gate", "release review", "can this go to prod", or
  "gate this PR". It runs a deterministic security scan first, then the
  forge-gatekeeper agent reviews the release diff against OWASP ASVS L2 / CWE Top 25
  and a Google-SRE-style production readiness checklist, scoped by the trust
  boundaries in architecture.md. Binary verdict: SHIP or HOLD. Read-only.
metadata:
  version: "0.1.0"
---

# forge-gatekeeper

`forge-review` asks "is this good code?". This skill asks the only question that
matters at release time: **if this ships tonight, what breaks, leaks, or cannot be
rolled back?** It is deliberately narrow — security and operability, nothing
else — and deliberately binary: `SHIP` or `HOLD`, never "advisory".

Trust model: the gate raises the floor, it does not certify the ceiling. It catches
what a careful release manager and an AppSec reviewer would catch from the repo
alone. It does not replace a penetration test, does not see infrastructure outside
the repo, and reports what it could **not** verify so a human can decide.

## Argument

- `<PR number | URL>`, `<branch>`, or nothing (working diff vs `main`) — same scope
  resolution as `forge-review`. `--base <ref>` overrides the diff base.
- `--all` — release audit: step 0 runs over every tracked file, and the agent walks
  every trust boundary in `architecture.md`, not only the ones the diff touches.
  Slow; run before a major release or after adopting the skill.
- `--focus=security|prod` — only that half of the checklist.

## Preconditions

Reads `context/architecture.md` (or `.forge/`). Two sections drive the review and
are added by `forge-init` from v0.53: **Trust Boundaries** and **Production
Constraints**. If either is missing, the skill still runs, reports `GK-000`
(architecture silent on boundaries/constraints, Important), and reviews from what
the code reveals — but tell the user to fill them in; without them the gate cannot
strike inapplicable checks and will be noisier than it should be.

## Steps

### 0. Deterministic gate — tools before judgment

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-gatekeeper/scripts/security-check.sh" --base <base>   # or --all
```

Three layers, cheapest first: tracked secret files (`.env`, keys, certs); built-in
regex rules with stable `GK-0nn` IDs + CWE for secret literals, debug leftovers,
and dangerous sinks (`eval`, shell strings, string-built SQL, raw HTML,
`shell=True`, unsafe deserializers, TLS off, CORS wildcard, weak hashes); then
**gitleaks, semgrep (`p/owasp-top-ten`, `p/secrets`), osv-scanner/trivy, `npm
audit` / `pip-audit`** — each only if installed. The script prints which tools are
missing; recommend installing them, but never block on their absence. Project
rules: `<context-dir>/security-rules.txt` (same `ID|Severity|glob|message|regex`
format as `rules.txt`).

Also run the project's own test/lint/typecheck commands (from
`ai-workflow-rules.md`). Capture every output verbatim.

**Every tool hit is a finding by construction** (`T`-finding, severity from the
rule). The agent confirms and cites it; it never re-litigates it. A failing test
suite or a Critical tool hit is a `HOLD` before any agent runs — say so and stop
unless the user asks for the full report anyway.

### 1. Scope

From `architecture.md`, list the **trust boundaries** and **production constraints**
that the diff touches: changed routes/handlers, jobs, consumers, migrations,
outbound integrations, config keys. Grep the callers of every changed function.
Print the scope table before spawning: boundaries touched · entry points · files
not in scope. This is the inventory the agent must mark in full; a verdict with an
unmarked entry point is `INCOMPLETE`, not `SHIP`.

### 2. Spawn the gatekeeper

Spawn the bundled **`forge-gatekeeper`** agent (opus-pinned, read-only), titled
`"Ingrid — gate <scope>"`. Give it: the base ref, the step-0 output verbatim, the
scope table, the paths to both checklists
(`${CLAUDE_PLUGIN_ROOT}/skills/forge-gatekeeper/references/security-checklist.md`,
`.../production-readiness.md`) and any project additions
(`<context-dir>/security-checklist.md`, `<context-dir>/production-readiness.md`).
It returns findings that each cite a `GK-Snn`/`GK-Pnn` ID (+ CWE) with
`[confidence NN]`, a "Not verified" list, and `Ingrid: SHIP` or `Ingrid: HOLD —
<reason>`. Findings under confidence 80 do not touch the verdict.

If the agent is unavailable, run the same checklists in-session with the agent's
hunt list; say that you did.

For a large `--all` audit, split by trust boundary and spawn one gatekeeper per
boundary in parallel; collapse to one verdict (any HOLD → HOLD).

### 3. Record

Append to the review ledger (`<context-dir>/review-ledger.md`, same format as
`forge-review`) under a `## Gate — <scope> — <date>` heading: step-0 summary,
findings with IDs, not-verified list, verdict. On a PR scope, post the verdict
block as one PR comment titled **Gatekeeper: SHIP / HOLD** so the trail is on the
PR. A `HOLD` finding that is fixed goes through `forge-fix` (regression test
first), then re-run this skill — the ledger makes the second pass cumulative.

Any Critical finding that the reviewer could have caught mechanically (a regex
would have found it) → propose one `security-rules.txt` line via `forge-lesson`, so
the next release does not spend an opus session on it.

## Output

In this order, nothing before the gate:

1. **Gate** — commands run, pass/fail, tool hits by ID, tools not installed.
2. **Scope** — boundaries touched, entry points reviewed, explicitly not reviewed.
3. **Findings** — Critical then Important: `file:line · GK-xxx (CWE) · [confidence] · what · fix`.
4. **Not verified** — what needs a running environment or out-of-repo config.
5. **Verdict** — `SHIP` or `HOLD — <the single blocking reason>` plus, on HOLD, the
   minimal set of changes that would flip it.

Never report `SHIP` with a failing step 0, an unmarked entry point, or an
unresolved Critical. Never downgrade a Critical because a follow-up is promised.

## Calibration

`forge-calibrate` ships three golden cases for this gate (`06-hardcoded-secret`,
`07-missing-authz`, `08-irreversible-migration`; keys prefixed `security:`/`prod:`).
Run `/forge-calibrate --case 07-missing-authz --runs 3` after changing the agent
prompt or a checklist row. Grow the set from every real miss.

## Boundaries

- Read-only. Reports; never edits, never fixes, never "quick-patches" a secret.
- Not a code-quality review — route style, tests, and design findings to
  `forge-review`; the gatekeeper ignores them unless they are a security or
  operability defect.
- Not a substitute for a pentest, dependency SBOM policy, or infra review. Say
  what was not verified rather than implying coverage.
- Findings are evidence-backed (`file:line`, ID, how known) or they go under
  "Not verified".
