---
name: forge-security-audit
description: >
  This skill should be used to run an evidence-gated security audit of a codebase in a
  Context Forge project — phrases like "forge-security-audit", "security audit this
  codebase", "find security vulnerabilities", "pen-test the code", "vulnerability
  research", "do a security review", or a focused security question. It vendors
  Cloudflare's security-audit skill: six phases (reconnaissance, coverage-led hunting
  with isolated agents, adversarial candidate validation, schema-validated
  findings.json, independent record verification, target-neutral report). Guidance
  mode for questions and focused reviews; the full workflow only for explicit audit,
  pen-test, or report requests. Read-only on target source.
metadata:
  version: "0.1.0"
  upstream: "https://github.com/cloudflare/security-audit-skill @ c1c8a8c (MIT, see LICENSE-cloudflare)"
---

<!--
Vendored from cloudflare/security-audit-skill, commit c1c8a8c (2026-09-14), MIT.
Everything between here and "## Context Forge integration" is the upstream SKILL.md
body verbatim, except: companion links point at references/, validator paths at
scripts/. references/*.md and scripts/* mirror upstream 1:1 (only `<skill-dir>/`
rewritten to ${CLAUDE_PLUGIN_ROOT}). To refresh: copy upstream files over, re-apply
those two rewrites, keep the integration section.
-->


# Security Audit

Find vulnerabilities that violate a real trust boundary, then give owners the source evidence, safe reproduction, priority, and smallest effective fix. This is a defensive, source-first workflow. A candidate without a concrete affected principal, resource, or security outcome is not a confirmed finding.

## Operating modes

This skill is guidance by default. Loading it does not authorize the complete audit workflow or file creation.

- **Guidance mode**: For security questions, focused reviews, methodology, triage, or investigation of specific findings, use only the relevant parts of this skill. Do not automatically run all six phases, create an output directory, or write audit artifacts. You may launch focused agents when useful; they return results to the current task.
- **Full audit mode**: Use the complete workflow when the user explicitly asks to audit or pen-test a codebase, asks for a full, comprehensive, or end-to-end security review, or requests report artifacts. Run all six phases and write the files defined below.

If the request could mean either mode, ask one focused question before creating files or starting the complete workflow.

## Platform terminology

This skill is agent-neutral:

- **Parent** is the agent that coordinates the run and owns shared state.
- **Task tool** is the platform's delegation or sub-agent mechanism.
- **`research` agent** is a delegated agent for focused source exploration and factual verification.
- **`general` agent** is a delegated agent for broad investigation and bounded local execution.
- **`subagent_type:`** in a heading names which of these two delegated agent roles runs that work.

Use equivalent platform capabilities while preserving role, write-isolation, prompt, and independence boundaries.

## Universal execution safety

These rules apply in both operating modes. Source inspection is read-only. Run target-controlled builds, tests, processes, browsers, emulators, fuzzers, and fixture processing only inside an OS-enforced sandbox that provides all of these controls:

- no external network; use only an isolated loopback namespace when the check needs local client/server traffic;
- an empty environment populated from an explicit allowlist with safe values, with scratch-local `HOME`, temporary directories, and caches;
- a read-only target and toolchain, with the target-controlled process able to write only inside its assigned `scratch/` directory; and
- explicit low CPU, memory, process, file-size, disk, and wall-clock limits.

The agent, outside the target-controlled process, may make a disposable source copy in an assigned `scratch/` directory when a build must write beside source. In guidance mode, do not retain target-controlled files. In full audit mode, only trusted parent-side code may promote the minimum non-secret result to retained `artifacts/` using the procedure under Write isolation. Never expose a retained output directory (other than the agent's own assigned `scratch/`), another agent's directory, the host home directory, credentials, sockets, or shared services to target code. Do not install dependencies or let builds fetch them. Use only tools and dependencies already available locally. If every control cannot be enforced, do not execute target code: report the missing sandbox capability as a needs-validation blocker and give a safe validation plan.

Use dummy principals, fixtures, and secrets. Do not probe deployed endpoints, external services, shared infrastructure, production identities, other users' data, or live control planes. Do not test availability against a live or shared process, publish artifacts, alter releases, spend paid API quota, or continue beyond the minimum local effect needed to establish a defect. If the decisive fact is outside source or the sandboxed fixture, report it as needing validation.

## Full audit setup

In full audit mode, resolve these values before reconnaissance:

- **Skill directory**: `${CLAUDE_PLUGIN_ROOT}/skills/forge-security-audit` — companions in `references/`, validators and `report-schema.json` in `scripts/`.
- **Target**: the absolute repository root under review.
- **Repo name**: a stable repository identifier from the directory or local Git remote.
- **Output directory**: a new writable directory outside the target, defaulting to `~/security-audit-skill/<repo-name>/run-<N>`, where `<N>` is the next unused integer. Use a directory inside the target only when the user explicitly selects it and the parent verifies that version control ignores the whole directory. Otherwise stop and request an external path.
- **Source ref**: the reviewed commit and whether the worktree is dirty. Do not treat unreviewed generated or modified files as another revision.

### Write isolation

The parent creates and is the only writer of shared run files:

- `run-metadata.json`
- `architecture.md`
- `coverage-ledger.json`
- `findings.json`
- `REPORT.md`
- `FINDINGS-DETAIL.md`
- `NEEDS-VALIDATION.md`

Each hunter or verifier receives a unique root under `<output-dir>/agents/<agent-id>/`, with separate `scratch/` and `artifacts/` directories. Canonical agent IDs match `^[a-z0-9][a-z0-9_-]{0,63}$` and must not equal a Windows device name such as `con`, `prn`, `aux`, `nul`, `com1` through `com9`, or `lpt1` through `lpt9`. Lowercase IDs prevent case-fold collisions. The agent and every target-controlled process may write only to `scratch/`; retained `artifacts/` is parent-owned, is never exposed to the sandbox, and is writable only by trusted parent-side promotion code. Agents may not change shared files, target source, retained artifacts, or another agent's directory. Do not use `/tmp` or the host home directory as a writable fallback.

Before execution, the parent opens and retains trusted, non-inheritable directory descriptors for the agent's `scratch/` and `artifacts/` roots, and records an allowlist of expected scratch-relative artifact files plus explicit per-file and cumulative byte limits. Never pass those descriptors to the agent or sandbox. After the sandbox and all its processes terminate, trusted parent-side code promotes each allowlisted file separately:

1. Validate the declared relative path: reject absolute, empty, `.`, `..`, or symlinked components.
2. Walk each parent component from the retained scratch-root descriptor with no-follow directory-relative operations; never reopen by path.
3. Open the leaf no-follow and nonblocking.
4. Verify with `fstat` that it is a regular file with link count exactly one and within the recorded per-file and cumulative byte limits.
5. Enforce those limits again while reading from that descriptor.
6. Copy exactly the verified size, repeat `fstat`, and reject a changed identity, type, link count, or size.
7. For the destination, walk every parent component from the retained artifacts-root descriptor with no-follow directory-relative operations; require each existing component to be a real directory, and create any missing directory exclusively before reopening and verifying it no-follow.
8. Create the leaf exclusively without following links, verify that the opened destination is a regular file with link count exactly one, and copy from the verified source descriptor without reopening either path.
9. Use equivalent race-safe APIs on non-POSIX systems.
10. Never recursively copy or glob scratch, extract an archive into artifacts, or open or promote a symlink, FIFO, socket, device, directory, hard-linked file, changing file, or file that exceeds its bound.
11. If any check is unavailable, cannot be enforced, or fails, discard the scratch entry; if it is decisive evidence, retain `needs_validation` with the exact promotion blocker.

[HUNTING.md](references/HUNTING.md) and [VALIDATION-AND-REPORTING.md](references/VALIDATION-AND-REPORTING.md) carry this procedure as one identical fenced block for hunter and verifier prompts; it states the same rules in the same order as this list.

For a reproduced check, record the command, exact test input, sandbox limits, and only the allowlisted environment variable names plus safe non-secret values needed to reproduce it. Never capture or copy the ambient environment, inherited variables, credential values, authentication state, or unrelated host paths. Launch from an empty environment rather than trying to redact one after execution.

Before delegation, the parent writes `run-metadata.json` with at least `run_id`, `repo`, `target`, `source_ref`, `profile`, `scope_paths`, `budget` (null if unset), `execution_policy: "sandboxed-source-and-local-only"`, selected companion files, prior-run paths, shared-file owners, and `run_status: "in_progress"`. Update metadata only when those facts change; candidate state belongs in the coverage ledger and `findings.json`.

## Full audit planning

The coverage, prior-run, profile, and budget requirements in this section apply only in full audit mode.

### Coverage and prior runs

No one pass is complete. Build a deterministic coverage plan before hunting and update it after every agent result. [RECONNAISSANCE.md](references/RECONNAISSANCE.md) defines the stable coverage units and [HUNTING.md](references/HUNTING.md) defines coverage-critic waves. The parent alone updates the ledger.

If prior runs exist, read every compatible `coverage-ledger.json` and `findings.json` before planning the current run:

1. Compare the relevant current source with each prior record and unit. A prior source ref alone is not evidence that a path is unchanged.
2. Carry a prior `confirmed` record into the current candidate set only when its relevant source and conditions are unchanged and its evidence still meets the current contract. Link it to a current ledger unit seeded `planned`, preserve its fingerprint, exclude only that carried root cause from hunters, and send the carried record through the current final verification path; the Phase 3 verifier that re-checks it becomes that unit's assignment owner and moves it to `candidate`.
3. When relevant source for a prior `confirmed` record changed, create a current planned revalidation unit. Do not put that record on the hunter exclusion list. It remains confirmed only if current independent validation establishes the current path and result.
4. Make prior `needs_validation`, `deferred`, `blocked`, `out_of_scope`, and any changed-source unit current work. A still-external `needs_validation` record may be carried only after the current source trace is checked and linked by fingerprint to a current `planned` unit whose verifier re-check supplies its owner and evidence; the record keeps the unresolved blocker. These prior states never suppress a current unit.
5. A prior same-source covered unit may inform priority, but it remains visible in the current ledger. A prior `rejected` record suppresses only the unchanged failed claim, not coverage of its unit; changed evidence creates current work.
6. Read the prior profile and scope. A prior `quick` or scoped ledger contributes only its recorded evidence and gaps, never an implied "rest is fine."

If no prior ledger exists, say so in the final coverage statement. Never imply that one run exhausts the target.

### Run profiles and scope

During full audit setup, pick a profile from the user's request or propose one from the target's size and stakes. Record it in `run-metadata.json` (`profile`, `scope_paths`) and state it in the report. The default is `standard`.

- **`quick`** — a bounded pass for small targets, re-runs, or a fast first look. Coarsen ledger units to surface × boundary × attack class (subsystem uses the fixed canonical `profile/quick/all-in-scope-subsystems` identifier), run exactly one hunter wave followed by exactly one final coverage-critic pass, and use one fresh verifier per candidate for both candidate validation and final record verification. Do not launch a follow-up hunter wave: record the critic's accepted discoveries and reassignments as `deferred`.
- **`standard`** — the workflow as written.
- **`deep`** — for high-stakes or large targets. Split ledger units per subsystem and lifecycle mode, run critic waves to a clean pass, keep candidate validation and final record verification as separate fresh agents, and give `prior_covered_same_source` units an independent second pass.

A **scoped run** audits a subset: named paths, one subsystem, one companion domain, or the diff between two source refs. Seed ledger units only for in-scope surfaces and record everything else as `out_of_scope` — never as `covered`. A scoped or `quick` run must present itself as partial coverage.

Profiles change breadth and redundancy, never the evidence bar. Do not scale away the candidate gate, the source/local execution boundary, `needs_validation` discipline, schema validation, or independent verification of `confirmed` records.

#### Cost budget

The ledger makes spend countable: one unit is roughly one hunter assignment, and one surviving candidate is one or two verifier assignments depending on profile. When the user sets a budget — or the parent proposes one for a large target — record `budget` in `run-metadata.json` as a maximum number of agent invocations across all phases.

Apply the strict budget gate before launching any reconnaissance agent. Reserve the four baseline reconnaissance calls, one final post-wave critic for `quick` or one post-wave plus one distinct final-clean critic for `standard`/`deep`, and at least one verifier call. Add focused reconnaissance only after repeating this gate for each extra call. If the requested budget cannot fund that minimum, launch no agent: ask for a larger budget, narrower scope, or different profile. If the request remains unchanged, set `run_status: "incomplete"` with `incomplete_reason: "budget_cannot_fund_reconnaissance_and_reserves"` and report that no audit pass ran.

Spend it in this order:

1. Count reconnaissance, every post-wave critic, and the separate final-clean critic as agent invocations.
2. **Reserve critics and validation before hunting.** For `quick`, reserve its one post-wave final critic. Before every `standard` or `deep` hunter wave, reserve one immediate post-wave critic plus one distinct final-clean critic. Also reserve verifier cost from the profile (about 1 or 2 agents per expected candidate; when in doubt reserve 30% of the balance after critic reservation). Never assign hunters into either reserve.
3. Assign hunters to units in priority order until the hunting allowance is spent. Spend the reserved post-wave critic immediately after that wave; keep the final-clean and validation reserves intact.
4. Before a later wave, reserve its new post-wave critic again. If the remaining budget cannot cover the required critic calls and validation reserve, launch no hunters from that wave, mark its planned units `deferred` with reason `budget_cannot_reserve_critics_and_validation`, and use the retained final-clean critic to record the resulting gap.

Before wave 1, update the pre-recon estimate with seeded units, implied hunter count, mandatory critic calls, validation reserve, and whether the remaining budget covers the plan. If it clearly cannot, say so and propose either a tighter scope or a coarser profile instead of silently thinning evidence. If later facts consume the required final-critic reserve, launch no hunters, mark all planned work deferred, set the run incomplete with reason `critic_budget_exhausted`, and make no complete-coverage claim.

A strict total-agent budget can still be exceeded by an unexpectedly large candidate set or by a material Phase 5 replacement that needs another independent verifier. If the remaining budget cannot validate every candidate, stop hunting, validate candidates in fingerprint order while the budget permits, and set `run_status: "incomplete"` plus `incomplete_reason: "validation_budget_exhausted"`. Keep each unvalidated fingerprint linked to a `candidate` ledger unit with that unresolved reason. Do not put an unvalidated candidate in `findings.json`, relabel it `needs_validation`, or report the run as complete. Phase 6 may produce a partial report only if its first section states that candidate validation is incomplete and lists the affected fingerprints and units. Never exceed a user-set strict budget silently.

## Core principles

### Require a boundary and result

For every candidate, name the lower-trust principal, accepted input or action, intended control, crossed boundary, affected principal or resource, and concrete observed or owner-observable result. Do not elevate a missing best practice, guessed deployment behavior, generic parser crash, or self-impact into a security finding.

### Use bounded local evidence

Static analysis establishes the source path. Sandboxed local tests resolve behavior when all execution controls are available: a minimal function harness, existing unit test, small parser fixture, dummy-tenant integration test, locally rendered configuration, or bounded isolated-loopback client. Stop at a wrong return value, unauthorized dummy record, sanitizer finding, policy difference, or other minimum effect. Do not extend the local check beyond the minimum boundary result or produce persistence, post-fault, or concealment material.

### Respect source visibility

Deployment controls, proxy behavior, provider settings, browser headers, identity policy, broker ACLs, packaging, and topology are real controls. If they are required and absent from the repository, do not assume either presence or absence. Use `needs_validation` with the exact missing fact and a safe owner-observed or local plan.

### Separate priority from certainty

Only `confirmed` records receive severity. Likelihood and impact must reflect the demonstrated conditions and result; overall severity cannot exceed demonstrated impact. `needs_validation` means a specific source-grounded boundary hypothesis is blocked, not a low-confidence confirmed vulnerability, and it has no severity.

Calibrate overall severity with these anchors:

- **critical** — an unauthenticated actor gains code execution, full data-store access, or takeover of arbitrary accounts.
- **high** — an actor fully defeats an explicit security control with real consequences: authentication bypass, cross-tenant read or write, stored script execution affecting other users, authenticated code execution, or an unauthenticated remote stop of a shared service.
- **medium** — a real boundary violation with limited blast radius, uncommon preconditions, or consequences confined to a narrow resource set.
- **low** — disclosure of non-secret internals, or an effect requiring sustained effort for minimal gain.
- **informational** — a confirmed but minimal-impact observation, useful mainly as a prerequisite inside a larger finding.

The high/medium discriminator: does the demonstrated result fully defeat an explicit control for an action with real consequences, or only weaken it? If you cannot state the concrete damage, the severity is lower than it feels.

### Recommend the smallest effective source fix

For each confirmed finding, identify the invariant the code must enforce and the narrowest source change that enforces it at the last trusted decision point. Prefer specific repository-relative changes and regression tests over generic hardening advice. The audit describes fixes; it does not modify target source.

## Full audit workflow

In full audit mode, follow all six phases in order:

1. **Reconnaissance** — map the source, trust boundaries, local build paths, companion selections, prior evidence, and initial deterministic coverage ledger with [RECONNAISSANCE.md](references/RECONNAISSANCE.md).
2. **Coverage-led hunting waves** — assign isolated hunters from the ledger and collect structured candidate results with [HUNTING.md](references/HUNTING.md), [ATTACK-CLASSES.md](references/ATTACK-CLASSES.md), and the selected domain companions.
3. **Candidate validation** — consolidate fingerprints and give every candidate to a fresh source verifier as defined in [VALIDATION-AND-REPORTING.md](references/VALIDATION-AND-REPORTING.md).
4. **Structured output** — write all final `confirmed`, `needs_validation`, and `rejected` records to `findings.json`; validate it with `report-schema.json` and `validate-findings.cjs`, and validate the coverage claim with `validate-coverage-ledger.cjs`.
5. **Independent record verification** — use fresh agents to verify final source claims and reconcile corrections or state changes.
6. **Target-neutral report** — derive `REPORT.md`, `FINDINGS-DETAIL.md`, and `NEEDS-VALIDATION.md` from the final records, with no live-probe instructions.

Do not end the run before one of exactly two terminal states: (a) all Phase 6 artifacts are written and both validators pass, or (b) `run_status: "incomplete"` is recorded with its exact reason and the gap is disclosed in the report. Never stop mid-phase.

## Anti-patterns

1. Checklist deviations presented as vulnerabilities.
2. Defense-in-depth advice with no reachable boundary violation.
3. Live or shared-environment testing where bounded local evidence is insufficient.
4. Guessing provider, proxy, browser, identity, or deployment behavior not present in source.
5. Treating intended same-principal authority or self-impact as a cross-boundary result.
6. Reporting a parser or runtime effect stronger than the observed effect.
7. Emitting prose-only hunter results that cannot be deduplicated or verified.
8. Re-reporting carried same-source prior confirmed records or using them as exemplars that anchor the hunt.
9. Assigning severity to `needs_validation` records.
10. Writing the report before independent verification or letting prose and JSON disagree.

## Context Forge integration

This section sits on top of the upstream workflow above. Where the two differ on
process, this section wins; the evidence bar, sandbox rules, verdict contracts, and
anti-patterns above never relax.

### Where it sits among the gates

- `forge-gatekeeper` — the release diff, minutes, `SHIP`/`HOLD`. "Is this safe to
  ship" goes there.
- `forge-health` — a whole-codebase hygiene sweep; its security dimension is basic.
- **`forge-security-audit`** — the whole codebase (or a scoped subset), six phases,
  many isolated agents, hours. Run it before a major release, after adopting the
  plugin on a brownfield codebase, on a cadence, or when a "find vulnerabilities" /
  "pen-test" request arrives. Repeated runs are additive (prior ledgers are read).

### Argument

`/forge-security-audit [<path>…] [--plan] [--profile quick|standard|deep]
[--budget <N>] [--output <dir>] [--diff <base>..<head>]`

- Paths or `--diff` make it a **scoped run**; nothing else is `covered`.
- No profile → `standard`, or propose `quick` for a small target / `deep` for a
  high-stakes one and say why.
- `--plan` — reconnaissance only: map the target, seed the ledger, print ranked
  scan targets, stop. Costs 4 agents, no hunters. See the `--plan` section.
- A bare question ("is this JWT check safe?") stays in **guidance mode**. When the
  request could mean either mode, ask one question before writing any file.

### Platform map

- **Parent** = this session. **Task tool** = the `Agent` tool.
- `research` agent → `Explore` (read-only source exploration, verification).
- `general` agent → `general-purpose` (broad investigation, bounded local execution).
- Both inherit the session model. For a `deep` profile or a high-stakes target, run
  the session on opus; hunters and verifiers are the highest-leverage tokens of the
  run. Do not route hunting or verification to `forge-scout` (haiku) — it is below
  the evidence bar; it may do Phase 1 file-inventory fan-out only.
- Title every spawn `"Audit — <role> <agent-id>"` (e.g. `"Audit — hunter h-auth-01"`)
  so `forge-office` and the agent-status hook show the run.
- One agent per Task call, its own `<output-dir>/agents/<agent-id>/` root, never a
  shared scratch. Verifiers never receive the hunter's conclusion, only the record.

### Inputs from the context directory

Read before Phase 1 (substitute `.forge/` for `context/` when that is the context
directory):

- `context/architecture.md` — **Trust Boundaries** and **Production Constraints**
  seed the trust-boundary map and the deployment facts. Treat them as claims to
  verify against source, never as evidence.
- `context/security-rules.txt`, `context/security-checklist.md` — project rules;
  hand them to hunters as extra "obvious things".
- `context/review-ledger.md` — earlier `## Gate` and `## Security audit` entries are
  prior evidence for recon. Only a prior `coverage-ledger.json` / `findings.json`
  counts as a prior *run*.

Run the deterministic scan first in full audit mode, it is nearly free:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-gatekeeper/scripts/security-check.sh" --all
```

Every hit becomes a recon lead, not a finding: it still goes through Phase 3.

### Output directory and validators

Default stays upstream: `~/security-audit-skill/<repo-name>/run-<N>`. In-repo
alternative: `<context-dir>/security-audits/run-<N>`, only after
`git check-ignore -q <context-dir>/security-audits` succeeds; otherwise stop and
ask for an external path. The validators need Node ≥ 18 and no dependencies:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/forge-security-audit/scripts/validate-coverage-ledger.cjs" <output-dir>/coverage-ledger.json
node "${CLAUDE_PLUGIN_ROOT}/skills/forge-security-audit/scripts/validate-findings.cjs"        <output-dir>/findings.json
```

`scripts/report-schema.json` is the schema hunters and verifiers receive verbatim.

### `--plan` — map first, scan later

For a large or unfamiliar target, run the map before paying for hunters:

1. Apply the budget gate for the four reconnaissance calls only; run
   `security-check.sh --all` and save its output as `<output-dir>/security-check.log`.
2. Run Phase 1 exactly as written: the four `research` agents, `architecture.md`,
   the seeded `coverage-ledger.json` (every unit `planned`), validated. Write
   `run-metadata.json` with `run_status: "planned"`.
3. Launch no hunter, critic, or verifier. Do not write `findings.json` or any report.
4. Rank the units and print the table:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/forge-security-audit/scripts/plan-rank.cjs" \
  <output-dir>/coverage-ledger.json --hits <output-dir>/security-check.log --repo <target>
```

   One row per subsystem × boundary: unit count, estimated agents (one hunter per
   unit plus about half a verifier), and the signals that put it there — tool hits
   under its paths (×3), files changed in the last 90 days (×1), and a low-trust
   surface such as unauthenticated, public, external, or webhook (×5). Add one
   line of judgment per top row only where the ledger labels hide something the
   agents reported (a boundary that guards money, a parser fed by the internet).
5. Stop. Report the output directory, the table, and the command for the top row:

```
/forge-security-audit <paths of row 1> --profile quick --budget <est. agents + 4> --output <output-dir>
```

A later run with the same `--output` continues that run: it flips `run_status` to
`in_progress`, marks units outside the new scope `out_of_scope`, and hunts the rest
from the existing ledger, so reconnaissance is paid once. A run with a different
output directory treats the plan as a prior run (its ledger, no findings).

### Sandbox reality

The upstream workflow executes target code only inside an OS-enforced sandbox (no
network, allowlisted env, read-only target, resource limits). A plain Claude Code
session has none of that, and `forge-exec.sh` is an output wrapper, not a sandbox.
Without a sandbox: static analysis only, every execution-dependent lead stays
`needs_validation` with its exact blocker and a safe validation plan, and the report's
first section says so. Do not "just run the tests" against the target to confirm a
candidate.

### Record and route

After Phase 6, append to `<context-dir>/review-ledger.md` (same file `forge-review`
and `forge-gatekeeper` use) under `## Security audit — <profile> — <date>`: run
directory, source ref, counts (`confirmed` by severity, `needs_validation`,
`rejected`), the coverage statement, and one line per confirmed fingerprint.

Then route, never fix in this skill:

- Each `confirmed` finding → one `forge-fix` unit (red regression test first), its
  remediation block as the spec.
- Anything a regex would have caught → propose one `security-rules.txt` line via
  `forge-lesson`, so the next gatekeeper run is deterministic.
- A trust boundary the audit found that `architecture.md` does not name → tell the
  user; `forge-audit` / `forge-decision` update the file, not this skill.
- `needs_validation` records with an owner-observable check → list them for the
  human; they are the report's action items, not debt to hide.

### Boundaries

- Read-only on target source. Writes go only to the output directory and the
  review-ledger entry.
- Reports; never patches, never rotates a leaked secret, never opens a PR.
- Not a substitute for a live pentest or infra review — `needs_validation` carries
  what the repo alone cannot show.
