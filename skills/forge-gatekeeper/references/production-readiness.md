# Gatekeeper production-readiness checklist (GK-P)

What a **Production Readiness Review** (Google SRE Book ch. 32, SRE Workbook
ch. 18) asks of a change, reduced to what a read-only repo review can verify.
Supplemented by the Twelve-Factor App (config, logs, disposability) and the
AWS Well-Architected Reliability / Operational Excellence pillars (vendor-neutral
questions). `architecture.md` **Production Constraints** decides which rows apply
(e.g. no DB → P1x rows struck).

Each item: stable ID · what the reviewer checks · default severity. IDs are never
renumbered or reused. Project additions: `<context-dir>/production-readiness.md`,
IDs `GK-Pnnn` ≥ 900.

## Rollback and data safety

| ID | Check | Severity |
| -- | ----- | -------- |
| GK-P10 | Every schema migration has a tested **down** path, or is explicitly additive-only (new nullable column, new table) and says so. | Critical |
| GK-P11 | **Expand/contract**: a destructive change (drop column/table, rename, type narrowing) ships in a later release than the code that stops using the data. The previous binary must still run against the new schema. | Critical |
| GK-P12 | Data backfills and one-off scripts are idempotent, batched, and resumable; they do not lock hot tables for the full run. | Important |
| GK-P13 | Deletion paths are soft or recoverable, or the spec explicitly accepted hard delete. New cascade deletes are called out. | Important |
| GK-P14 | The change can be turned off without a deploy — feature flag, config switch, or route toggle — when it is user-facing and non-trivial. Money, auth, or deletion paths: Critical. | Important |

## Failure modes and limits

| ID | Check | Severity |
| -- | ----- | -------- |
| GK-P20 | Every outbound call (HTTP, DB, queue, cache, LLM) has an explicit **timeout**. Library defaults of "none" count as none. | Critical |
| GK-P21 | Retries are bounded, use backoff + jitter, and only wrap idempotent operations. No retry around a payment or send. | Important |
| GK-P22 | No unbounded growth: in-memory caches/maps have eviction, queues have max length, list endpoints paginate, uploads and bodies have size limits. | Important |
| GK-P23 | A dependency being down degrades the feature, not the process: no dependency call in a startup path that crash-loops the service; circuit or fallback where architecture.md requires it. | Important |
| GK-P24 | New list/detail endpoints do not introduce N+1 queries or full-table scans on unindexed columns (check the query + the index). | Important |
| GK-P25 | Background jobs and consumers are idempotent (at-least-once delivery is the default everywhere) and dead-letter on repeated failure. | Important |
| GK-P26 | Concurrency safety on shared state: transactions or unique constraints for check-then-act; no per-process locks pretending to be global in multi-instance deploys. | Critical |

## Observability

| ID | Check | Severity |
| -- | ----- | -------- |
| GK-P30 | Failures on the new path emit an error-level log (or metric) with what failed, where, for whom (id, not PII), and with what input class. Swallowed errors: Critical. | Important |
| GK-P31 | Logs are structured and go to stdout/stderr (twelve-factor XI), not to files the platform does not collect. | Important |
| GK-P32 | A new critical path has a success/failure metric or is covered by an existing SLI named in architecture.md. If nobody can tell it is broken, it is not production-ready. | Important |
| GK-P33 | Health/readiness endpoints reflect new hard dependencies (readiness fails if the new required dependency is unreachable; liveness does not). | Important |
| GK-P34 | Request/trace IDs propagate through the new path (incoming header → logs → outbound calls). | Advisory |

## Configuration and deploy

| ID | Check | Severity |
| -- | ----- | -------- |
| GK-P40 | Config comes from the environment (twelve-factor III); new config keys are documented (`.env.example`, deploy manifest) and have safe production defaults or none. | Important |
| GK-P41 | The build is reproducible: lockfile committed and updated, no floating versions introduced, no build step that reaches the network for unpinned content. | Important |
| GK-P42 | Startup does not depend on ordering with other services or on a migration having already run, unless the deploy pipeline guarantees it and architecture.md says so. | Important |
| GK-P43 | Graceful shutdown: in-flight requests and jobs finish or are safely abandoned on SIGTERM (twelve-factor IX). New long-running loops honor the shutdown signal. | Important |
| GK-P44 | Resource limits: new processes, workers, or containers declare CPU/memory limits where the platform expects them; new cron/scheduled work has a concurrency guard. | Advisory |

## Verification evidence

| ID | Check | Severity |
| -- | ----- | -------- |
| GK-P50 | The unit's tests cover the failure paths of the new code (timeout, dependency error, invalid input, unauthorized), not only the happy path. | Important |
| GK-P51 | Migrations were exercised against realistic data volume or the spec states the table size and why it is safe. | Advisory |
| GK-P52 | Release notes / PR body state the rollback procedure in one line ("revert PR; migration is additive" or "run `down` first"). | Important |

## How to use

1. Read `architecture.md` **Production Constraints** — platform, deploy model
   (rolling / blue-green / single instance), data stores, SLOs. Strike rows that
   cannot apply and say which.
2. P10–P14 and P20 decide most HOLDs. Check them first, on every changed
   migration, handler, and outbound call.
3. Cite the ID in every finding. Advisory rows never affect the verdict; report
   them only when cheap and clearly right.
