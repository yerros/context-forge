# Architecture Context

## Stack

| Layer     | Technology                  | Role   |
| --------- | --------------------------- | ------ |
| Framework | [e.g. Next.js + TypeScript] | [Role] |
| UI        | [e.g. Tailwind + shadcn/ui] | [Role] |
| Auth      | [e.g. Clerk]                | [Role] |
| Database  | [e.g. Prisma + PostgreSQL]  | [Role] |
| [Layer]   | [Technology]                | [Role] |

## System Boundaries

- `[folder]` — [What this folder owns and is responsible for]
- `[folder]` — [What this folder owns and is responsible for]
- `[folder]` — [What this folder owns and is responsible for]
- `[folder]` — [What this folder owns and is responsible for]

## Storage Model

- **[Storage type e.g. Database]**: [What lives here —
  e.g. metadata, ownership, relationships]
- **[Storage type e.g. Blob/File Storage]**: [What lives
  here — e.g. generated files, media, large artifacts]

## Auth and Access Model

- [How authentication works — e.g. Every user signs in
  via Clerk]
- [How ownership works — e.g. Every project has a single
  owner]
- [How access control works — e.g. Only the owner or a
  collaborator can mutate project resources]

## Trust Boundaries

<!-- Read by forge-gatekeeper to scope the security gate. One line per surface
     where untrusted or less-trusted input enters. Strike what does not exist:
     a repo with no public HTTP surface gets no CORS/CSRF findings. -->

- **[Surface — e.g. Public HTTP API `src/routes/`]** — [who calls it — e.g.
  internet, authenticated users] — [control — e.g. session via `requireUser`,
  object ownership checked per handler by `ownerId`]
- **[Surface — e.g. Webhooks `src/webhooks/`]** — [caller — e.g. Stripe] —
  [control — e.g. signature verified before parsing]
- **[Surface — e.g. Background jobs / queue consumers]** — [caller] — [control —
  e.g. payloads validated with the same schemas as HTTP]
- **[Sensitive data]** — [what is PII/secret — e.g. email, payment tokens] —
  [rule — e.g. never logged, encrypted at rest via KMS, 90-day retention]
- **Public (unauthenticated) endpoints**: [list, or "none"]

## Production Constraints

<!-- Read by forge-gatekeeper to scope the readiness gate. -->

- **Deploy model**: [rolling | blue/green | single instance] — [implication —
  e.g. old and new binaries overlap; migrations must be expand/contract]
- **Migrations**: [tool + rule — e.g. run before start; every migration has a
  tested down path; destructive changes ship one release after the code]
- **Kill switch**: [how a feature is disabled without a deploy — e.g. flags in
  `config/flags.ts` read at request time]
- **Timeouts / limits**: [defaults — e.g. every outbound call ≤ 5 s; request
  body ≤ 1 MB; list endpoints paginate at 100]
- **Observability**: [where errors and metrics go, SLIs that exist — e.g.
  structured logs to stdout, `http_request_errors` metric per route]

## Invariants

1. [Rule the codebase must never violate — e.g. Request
   handlers do not run long-lived background work]
2. [Invariant two]
3. [Invariant three]
4. [Invariant four]
