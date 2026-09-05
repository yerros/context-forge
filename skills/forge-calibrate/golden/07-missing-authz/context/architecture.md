# Architecture Context

## Auth and Access Model
- Every request is authenticated by `requireUser` (session cookie).
- Every invoice has exactly one owner; only the owner may read or mutate it.

## Trust Boundaries
- HTTP API (`src/routes/`) — public internet, authenticated users. Object ownership is enforced per handler via `ownerId`.

## Production Constraints
- Single Postgres, rolling deploy.
