# Unit 01 — Logout endpoint

## Goal
Add `POST /logout` that clears the session cookie and returns 204.

## Implementation
- `src/logout.ts`: one handler, clears cookie `sid`, responds 204.

## Tests
- Handler responds 204 and sets `sid` cookie to expired.

## Out of scope
Anything else. No changes to `src/util.ts`.
