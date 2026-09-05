# Gatekeeper security checklist (GK-S)

Subset of **OWASP ASVS 5.0 Level 2** plus **CWE Top 25** items that a read-only
release review can actually verify from a repository. Level 2 is the bar for any
application that handles user data or money; Level 3 items (HSM, formal threat
model artifacts) are out of scope for this gate.

Each item: stable ID · ASVS 5.0 chapter · CWE · what the reviewer checks · default
severity when violated. IDs never change or get reused; add new ones at the end
of a section. Project-specific additions go in `<context-dir>/security-checklist.md`
with IDs `GK-Snnn` ≥ 900.

Sources: OWASP ASVS 5.0 (owasp.org/www-project-application-security-verification-standard),
OWASP API Security Top 10 (2023), CWE Top 25 (cwe.mitre.org/top25), OWASP Cheat Sheet Series.

## Secrets and configuration — ASVS V13 Configuration

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S01 | 798 | No credential, API key, token, or private key literal in source, fixtures, IaC, or CI files. (`security-check.sh` GK-01x catch the common shapes; confirm anything it flags.) | Critical |
| GK-S02 | 540 | `.env`, key, cert, and keystore files are not tracked; `.gitignore` covers them. | Critical |
| GK-S03 | 1188 | Config read from env has **no insecure default** when the variable is absent (e.g. `JWT_SECRET \|\| "dev"`, `DEBUG = true`). Missing required config fails startup loudly. | Critical |
| GK-S04 | 489 | Debug/dev toggles (verbose errors, stack traces to client, mock auth, `console.log`) are unreachable in production builds. | Important |
| GK-S05 | 16 | Security headers on HTML responses: CSP, `X-Content-Type-Options`, `Referrer-Policy`, HSTS behind TLS. Only when the repo serves HTML. | Important |

## Authentication and sessions — ASVS V6 Authentication, V7 Session Management, V9 Self-contained Tokens

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S10 | 916 | Passwords hashed with argon2id / bcrypt / scrypt (cost tuned), never MD5/SHA-x, never reversible. | Critical |
| GK-S11 | 613 | Session/token lifetime bounded; logout and password change invalidate existing sessions or refresh tokens. | Important |
| GK-S12 | 1004, 614 | Session cookies: `HttpOnly`, `Secure`, `SameSite=Lax` or stricter. | Important |
| GK-S13 | 347 | JWTs: algorithm pinned server-side (no `alg: none`, no `HS`/`RS` confusion), `exp` enforced, audience/issuer checked. | Critical |
| GK-S14 | 307 | Login, OTP, password-reset, and other credential endpoints are rate limited or lock out. | Important |
| GK-S15 | 640 | Password reset / magic-link tokens: single-use, expiring, random (≥128 bits), not logged. | Critical |

## Authorization — ASVS V8 Authorization; API Top 10 API1/API5

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S20 | 862 | Every new or changed route, RPC, job trigger, webhook, and message consumer has an explicit authentication check or is explicitly listed as public in architecture.md. | Critical |
| GK-S21 | 639 | **Object-level** authorization: the handler verifies the caller owns/may access the specific record (BOLA/IDOR), not merely that they are logged in. | Critical |
| GK-S22 | 285 | Function-level authorization: admin/privileged actions check role or permission server-side; UI hiding is not a control. | Critical |
| GK-S23 | 915 | Mass assignment: request bodies are mapped to an allow-list of fields, never spread straight into an update. | Important |
| GK-S24 | 284 | Authorization decisions live in one place (middleware/policy layer) and are not re-implemented ad hoc in the new handler. | Important |

## Input handling and injection — ASVS V1 Encoding & Sanitization, V2 Validation, V5 File Handling

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S30 | 20 | Every value crossing a trust boundary (body, query, header, path, file, webhook, queue message, env) is parsed into a typed shape before use; unknown fields rejected or dropped. | Critical |
| GK-S31 | 89 | SQL/NoSQL: parameterized queries or ORM query builders only; no string-built queries, including `ORDER BY`/table names from input. | Critical |
| GK-S32 | 78 | OS commands: no shell string built from input; `execFile`/`spawn`/argv arrays, allow-listed binaries. | Critical |
| GK-S33 | 79 | HTML output is escaped by the template engine; raw-HTML sinks (`innerHTML`, `dangerouslySetInnerHTML`, `\|safe`) only with a sanitizer on the value. | Critical |
| GK-S34 | 22 | Filesystem paths built from input are resolved and checked to stay under the intended root; uploads renamed, type-checked by content, size-limited. | Critical |
| GK-S35 | 918 | Outbound requests to URLs derived from input: scheme + host allow-list, no redirects followed to internal ranges (SSRF). | Critical |
| GK-S36 | 601 | Redirect targets from input are relative-only or allow-listed (open redirect). | Important |
| GK-S37 | 502 | No deserialization of untrusted data with unsafe loaders (`pickle`, `yaml.load`, Java native, PHP `unserialize`). | Critical |
| GK-S38 | 1333 | Regexes applied to input are linear (no nested quantifiers on user-controlled length) or have a length cap (ReDoS). | Important |
| GK-S39 | 352 | State-changing browser requests carry CSRF protection (token, `SameSite` + origin check) when cookies authenticate. | Critical |

## Data protection and privacy — ASVS V14 Data Protection, V16 Logging

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S40 | 532 | No PII, credentials, tokens, or full request bodies in logs, error messages, or analytics events. | Critical |
| GK-S41 | 209 | Error responses to clients are generic; stack traces and SQL text never leave the server. | Important |
| GK-S42 | 200 | Responses return only fields the caller needs (no full-object serialization of users, orders, etc. — API3 excessive data exposure). | Important |
| GK-S43 | 311 | New storage of sensitive data follows architecture.md's at-rest rules (encrypted columns / KMS / hashed) and retention. | Critical |
| GK-S44 | 598 | Secrets and PII never travel in URLs or query strings (they land in logs and referrers). | Important |

## Cryptography and transport — ASVS V11 Cryptography, V12 Secure Communication

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S50 | 327 | Standard, current algorithms via a maintained library: AES-GCM / ChaCha20-Poly1305, SHA-256+, no home-grown crypto, no ECB. | Critical |
| GK-S51 | 330 | Randomness for anything security-relevant comes from the CSPRNG (`crypto.randomBytes`, `secrets`, `crypto/rand`), never `Math.random`/`random`. | Critical |
| GK-S52 | 295 | TLS verification is never disabled; outbound calls use HTTPS. | Important |
| GK-S53 | 328 | MD5/SHA-1 not used for any security purpose (checksums of non-security data are fine — say so). | Important |

## Supply chain — NIST SSDF PW.4, SLSA, OpenSSF Scorecard

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S60 | 1395 | New or updated dependencies have no known HIGH/CRITICAL advisories (`npm audit`, `pip-audit`, `osv-scanner`, `trivy`). | Critical |
| GK-S61 | 829 | New dependencies are justified (not replacing a few lines), from the canonical registry, actively maintained, and lockfile-pinned. | Important |
| GK-S62 | 1104 | CI/CD and build scripts do not pipe remote content into a shell (`curl \| sh`) or pull unpinned actions/images (`@main`, `:latest`). | Important |

## Business logic and abuse — ASVS V2 Business Logic; API Top 10 API4/API6

| ID | CWE | Check | Severity |
| -- | --- | ----- | -------- |
| GK-S70 | 770 | Public or costly endpoints (search, export, email/SMS send, LLM calls, file processing) are rate limited or quota'd per caller. | Important |
| GK-S71 | 841 | Multi-step flows (checkout, verification, approval) enforce step order and cannot be replayed to skip a step. | Important |
| GK-S72 | 362 | Money, inventory, or quota changes are atomic (transaction, unique constraint, idempotency key) — no check-then-act race. | Critical |

## How to use

1. Read `architecture.md` **Trust Boundaries** first; strike every row that does
   not apply to this repo and say which (e.g. "no HTML served → S05, S33, S39
   not applicable").
2. Walk the diff's entry points against S20–S24 and S30–S39 line by line. These
   are where releases actually fail.
3. Everything else: check what the diff touches, not the whole codebase.
4. Cite the ID and CWE in every finding. A finding that cites neither is an
   opinion and does not affect the verdict.
