# Reference: mksglu/context-mode — what it does, what Context Forge can learn

Analyzed 2026-09-13 against context-mode v1.0.169 (main) and Context Forge v0.54.0.
Source: https://github.com/mksglu/context-mode (22.5k stars, ELv2 license, TypeScript,
Node ≥22.5 or Bun, 17 platforms).

> **License note.** context-mode is Elastic License v2, not MIT. Ideas, formulas, and
> prompt-craft patterns are fair game; do not copy source verbatim into this MIT repo.
> Everything below is described so it can be re-implemented in shell.

## 1. What context-mode is (and is not)

context-mode is an **MCP server + hook bundle** that keeps raw tool output out of the
model's context window and restores session state after compaction. It solves a
different problem from Context Forge:

| | context-mode | Context Forge |
|---|---|---|
| Problem | Tool output floods context; compaction erases working memory | Agent has no architectural system or cross-session project memory |
| Unit of memory | Session events (SQLite, per project, ephemeral, 7-day GC) | Project context files (markdown in git, permanent) |
| Enforcement | Runtime: PreToolUse deny/redirect + sandbox execution | Methodology: skills, agents, deterministic gates, guard on protected files |
| Runtime dep | Node ≥22.5 + native/WASM SQLite | bash + sqlite3 CLI |
| Scope | Per session, any project, any workflow | Per project, spec-driven workflow |

They are complementary. A team could run both. The value for Context Forge is in
**four mechanisms** context-mode has that we lack, plus a body of empirically tested
prompt-craft, not in re-implementing the sandbox.

## 2. context-mode architecture (condensed)

### 2.1 Sandbox (`ctx_execute`, `ctx_execute_file`, `ctx_batch_execute`)
- Runs code in 12 languages in a subprocess; cwd is the project root; a per-call temp
  dir holds the script. Only stdout returns to the model.
- Environment is a **denylist copy** of the parent env (`BASH_ENV`, `NODE_OPTIONS`,
  `LD_PRELOAD`, `PYTHONSTARTUP`, `GIT_SSH*`, ~80 entries, each with a CVE/MITRE note).
- Two output layers: 100 MB hard cap (process killed) and a 100 KB context-facing
  threshold. Above 100 KB the output is **indexed into FTS5 and replaced by a
  pointer**, never blind-truncated ("index, don't truncate"). With an `intent`
  parameter and >5 KB output, it returns only matching section titles.
- Every response is prefixed by an echo of the code (capped at 2000 chars) for
  provenance.
- Shell exit code 1 with non-empty stdout is **not** an error (grep-no-match case).
- Batch mode: serial = one shared timeout budget with cascading skip; concurrency>1 =
  per-command timeout, `allSettled` isolation, output order preserved.

### 2.2 Routing enforcement (PreToolUse)
Three separate files: a pure router (`route(tool, input) → {action, reason}`), a
prompt-text module, and a per-platform wire formatter. Rules, in order:

1. Security: user's `permissions.deny/allow` patterns → deny/ask. Never claims a
   decision when nothing matches, so native permission engine still runs.
2. `curl`/`wget` → redirected, **segment-aware**: the command is split on `&&`, `||`,
   `;` and each segment judged alone. A segment passes if it writes to a file
   (`-o`, `>`), is silent (`-s`/`-q`), and has no `-v`. Quoted content is stripped
   first so `gh issue edit --body "…curl…"` is not a false positive.
3. Inline HTTP in code (`fetch('http`, `requests.get(`) → redirected.
4. Build tools (`gradle`, `mvn`, `sbt`) → redirected with the original command
   pre-wrapped: `<cmd> 2>&1 | tail -30`.
5. **Structurally bounded** commands pass silently (allowlist: `pwd`, `ls`, `git
   status`, `git log -N`, `git diff --stat`, `--version`, …) but only if the command
   has **no shell control operators** (`|`, `;`, `&&`, `$(`, `>`, newline).
6. Everything else gets a once-per-session advisory nudge.

Read: files >50 KB nudge every time (`statSync` in the hook); smaller ones nudge once.
Grep: one-shot nudge. WebFetch: hard deny. External MCP tools: nudge every 10th call
(a once-per-session nudge was lost after compaction in MCP-heavy sessions).

**Agent tool**: the hook rewrites the subagent prompt (`updatedInput`) to append the
routing block, sniffing the prompt field across `prompt|request|objective|question|
query|task`, and upgrades `subagent_type: "Bash"` to `general-purpose` so the subagent
actually has the tools it is being told to use.

Every redirect degrades to passthrough when the MCP server is not alive (sentinel
file with PID probe and 90 s freshness window). Throttles are marker files created
with `O_CREAT|O_EXCL`, keyed on the payload `session_id` (never `ppid`: unstable on
Windows/Git Bash and under `bash -c` wrappers).

### 2.3 Session continuity
- **Capture.** PostToolUse classifies each tool call into ~26 event categories
  (file edit, git, error, error-resolution, retry-loop, decision via
  `AskUserQuestion`, constraint, plan enter/exit/approved/rejected, skill, subagent,
  external ref, env change, cwd). UserPromptSubmit stores the raw prompt plus derived
  events. Stop stores a `turn_end` marker and the last assistant message (2000 chars).
- **User correction detection is structural, not keyword-based**: a prompt counts as a
  decision if it has a clause separator (`, ; ，；、،`), is 15–500 codepoints, contains
  letters, and is not a question. Language-agnostic by design because the raw text is
  replayed to the next model anyway; the gate only needs to be coarse.
- Roles ("you are…", "always…", "never…") require an explicit cue prefix after a bug
  where "that's fine for now" was frozen as a role and re-injected every turn.
- **Storage.** SQLite per project (`sessions/<hash><worktree>.db`), WAL, busy_timeout
  30 s, bounded retry. Max 1000 events per session; eviction removes lowest priority
  then oldest. Dedup by content hash within the last 5 rows. Multi-writer by design
  (ADR-0001 rolled back a lockfile that broke multi-window users).
- **PreCompact** builds an XML snapshot (session goal, files, errors, decisions, rules,
  git, tasks, env, subagents, skills, roles, intent, last 3 user messages). Each
  section ends with a **pre-built, copy-runnable search call** with queries derived
  from that section's own data. No truncation: the snapshot is a table of contents;
  full data stays in the DB.
- **SessionStart** branches on the `source` field:
  - `compact` → inject Session Guide (15 markdown sections) + a 500-token behavioral
    block (role, last 5 decisions, skills, intent) + `<continue_from>Continue working
    on the last request. Do NOT ask the user to repeat themselves.</continue_from>`.
  - `resume` → Session Guide from live events for that session id only (a broader
    "latest session" lookup caused cross-worktree bleed); fall back to the stored
    snapshot when `/resume` hands a fresh session id.
  - `startup` → no guide; run 7-day GC; capture CLAUDE.md files as rule events.
  - `clear` → nothing.
- **Plan Mode section** carries explicit status: `APPROVED AND EXECUTED — Do NOT
  re-enter plan mode or re-propose the same plan`, `REJECTED BY USER — Ask what they
  want changed`, `ACTIVE`. Prevents stale-plan re-proposal after compaction.
- Events are also written to a markdown file the MCP server indexes into FTS5 under
  `source: "session-events"`, then deletes.

### 2.4 Knowledge base and search
- Two FTS5 tables over the same rows: `tokenize='porter unicode61'` and
  `tokenize='trigram'`. Column weights `bm25(chunks, 5.0, 1.0)` (title 5×).
- Query sanitization: strip FTS operators, drop ~110 stopwords (including
  changelog-ish words: `add`, `fix`, `update`, `test`), quote each word, OR-join.
- **Reciprocal Rank Fusion** (Cormack 2009, K=60) over the porter and trigram result
  lists; identity `source::title`; fetch `2×limit` from each leg.
- Proximity rerank: title-hit boost (0.3 prose, 0.6 code), min-span boost
  `1/(1+span/len)`, adjacent-pair phrase boost capped at 0.5.
- Levenshtein fuzzy correction against a `vocabulary` table (edit distance 1/2/3 by
  word length), LRU-cached, run only when the exact query returns nothing.
- Snippets from FTS5 `highlight()` positions (±300 chars, windows merged), so stemmed
  matches are found correctly.
- Chunking: markdown split on H1–H4 and horizontal rules, **code fences kept intact**,
  breadcrumb titles (`H1 > H2 > H3`), 4 KB cap with paragraph-boundary splitting.
  Plain text: 20-line groups with 2-line overlap. JSON: key paths become titles.
- Re-index of the same label deletes old chunks in the same transaction (idempotent).
  Stale file sources are re-hashed on search and refreshed.
- Search results are throttled (2 results per query, 40 KB per response, flood guard
  per agent) so the retrieval layer cannot itself flood context.

### 2.5 Stats (ADR-0004)
Reported savings = `1 − returned/(avoided + returned)`. Hook-captured payload bytes
are excluded from both sides because they never entered the model's context. The
previous formula counted them and reported 56% where the honest number was 95%.

### 2.6 Prompt-craft ADRs (the most transferable part)
- **ADR-0002, tool description style.** Locked template `headline / WHEN: / WHEN NOT:
  / RETURNS: / EXAMPLE:` with markdown bullets, uppercase headers, ≤1000 chars. Forbidden
  in descriptions: `MANDATORY:` opener, `BLOCKED`, `PREFER X OVER Y`, `Do NOT use`,
  `Never use`, emoji bullets. Backed by 38 A/B trials: heavy forbidding framing
  degrades tool selection; `"blocked"` → `"redirected"` fixed Opus 4.6 capitulation
  6/6 → 0/6; the parenthetical "NOT a network restriction" made Haiku *worse*
  (a bare NOT primes the frame it denies). A unit test reads the source as text and
  asserts the rules on every commit.
- **ADR-0003, deny reasons.** CASE A (context routing): open with "redirected", name
  the replacement as an imperative call, affirm capability, end with a positive retry
  hint. CASE B (security policy): "Blocked by security policy: …". Never mix.
- **Affirmative disambiguation** instead of prohibition: "Read stays correct when you
  intend to Edit the file (Edit needs the exact bytes)". Give the native tool its
  legitimate niche so the model trusts the redirect elsewhere.
- **Anti-lock-in clause** for injected memory: "Skills, roles, and decisions captured
  earlier are a memory aid, not a standing order. The user's most recent message
  always takes precedence."
- Cost tables with real numbers (`135K tokens → 430 B`) move models better than
  adjectives.

## 3. Defects found in context-mode (do not copy blindly)
1. `## Last Request` and `<continue_from>` never render: the guide groups on
   `category === "prompt"` but every producer writes `"user-prompt"`.
2. README and the precompact docstring promise a priority-tiered ≤2 KB snapshot; the
   implementation dropped both the budget and priority dropping (only the 500-token
   behavioral block still has tiers).
3. `CLAUDE.md` still says `curl/wget — BLOCKED … Do NOT retry`, contradicting the
   hook's own ADR-0003 wording. The contract test does not scan CLAUDE.md.
4. Claude Code formatter does not unescape `\"` in the build-tool redirect text.
5. BENCHMARK numbers measure a hand-written summarizer's aggressiveness, top-1 result
   only, and exclude the 2 KB code-echo preamble. "30 min → 3 h" is unbacked.
6. `withRetry` busy-waits synchronously (up to 2.6 s of CPU spin) inside the
   long-lived MCP server.

## 4. Gap analysis: Context Forge v0.54.0

| Gap | Evidence in this repo | context-mode equivalent |
|---|---|---|
| **No compaction recovery** | `hooks.json` has no `PreCompact`; the SessionStart command ignores the `source` field, so after auto-compact the digest injected at startup is gone and nothing re-injects it | PreCompact snapshot + SessionStart `compact` branch |
| **Subagents never see Tier 1** | SessionStart output goes to the main session only; forge agents get whatever the skill pastes into the prompt | PreToolUse on `Agent` appends the routing block to every subagent prompt |
| **No tool-output hygiene** | Skills *ask* for quiet reporters; nothing enforces `| tail` on build/test commands | Structurally-bounded allowlist + build-tool redirect + once-per-session nudge |
| **Retrieval index is basic** | `forge-index.sh`: default tokenizer (no stemming), no title weight, splits sections on any line starting with `#` including comments inside code fences, OR-of-words with no stopword filter | porter tokenizer, `bm25(…,5.0,1.0)`, fences intact, stopwords, RRF with trigram |
| **Corrections are captured manually** | `forge-lesson` and the build loop write lessons; nothing watches user prompts for correction shape | Structural decision detector on UserPromptSubmit |
| **No plan-status memory** | Plan approval/rejection lives only in the conversation | Plan Mode section with explicit status directives |
| **No contract test on prompt text** | 26 SKILL.md descriptions and hook messages are unchecked for the framing ADR-0002 shows to hurt | Static test over source text |

## 5. Recommendations, ranked (shell-only, no MCP server)

### Do now (each under an afternoon, zero model tokens)

1. **PreCompact + source-aware SessionStart.** Add a `PreCompact` hook script that
   writes `$CTX/.compact-snapshot.md`: timestamp, `git status --porcelain` summary,
   the tracker's In Progress block, the last skill from `skill-status.sh`, the
   `.last-session.md` file list, and the active worktree claim if any. Change the
   SessionStart digest command to read stdin, and on `source` ∈ {`compact`,
   `resume`} inject the snapshot **after** the digest with a one-line continuation
   directive ("Continue the in-progress unit. Do not ask the user to re-explain; the
   tracker and snapshot above are current."). On `clear`, inject nothing extra.
   Add the anti-lock-in sentence.

2. **Inject Tier 1 into subagents.** PreToolUse matcher `^(Task|Agent)$` (already
   used by `agent-status.sh`) returns `updatedInput` with the prompt field appended:
   "[Context Forge] Before deciding anything read `$CTX/context-digest.md`; honor the
   invariants in `architecture.md`." Sniff the prompt field name the way context-mode
   does. Keep the injection short (a pointer, not the digest) so it does not double
   the cost of every forge agent launch.

3. **Harden `forge-index.sh`.** Four line-level changes: `tokenize='porter
   unicode61'`; `ORDER BY bm25(docs, 5.0, 1.0)`; make the awk splitter track a fence
   state so `#` inside ``` blocks does not open a section; strip a small stopword list
   before building the OR query. Rebuild is already a full rebuild so no migration.

4. **Prompt-text contract test.** A bats test that greps every `skills/*/SKILL.md`
   description, `guard.sh`, and the SessionStart injection for the tokens ADR-0002
   found harmful (`BLOCKED`, `Do NOT retry`, `NOT a …`, `Never use` in a description)
   and for missing CASE-A shape in any deny message. `guard.sh` already conforms
   (names the replacement action); the test keeps it that way.

### Do next (worth a small design pass)

5. **Bash output-hygiene nudge.** PreToolUse on `Bash`: if the command matches a
   build/test runner (`npm test`, `pytest`, `cargo test`, `gradle`, `mvn`, `go test`,
   `tsc`) and contains neither `| tail`, `| grep`, `--quiet`, `-q`, nor a reporter
   flag, return `additionalContext` once per session (marker file keyed by
   `session_id`, `mkdir` as the atomic test-and-set) suggesting
   `<cmd> 2>&1 | tail -40`. Advisory only, never deny; Claude Code ignores
   `updatedInput.command` under allow anyway. Skip the structurally-bounded allowlist
   unless the nudge proves noisy.

6. **Correction capture as lesson candidates.** UserPromptSubmit hook: if the prompt
   has a clause separator, 15–500 codepoints, letters, no `?`, and starts with a
   negation cue (`no`, `don't`, `not`, `jangan`, `bukan`, `stop`, `wrong`, `instead`),
   append it to `$CTX/.lesson-candidates.md`. `forge-lesson` and the Stop-hook budget
   report surface the file; nothing is auto-promoted. Language-agnostic by shape, cue
   list keeps false positives low.

7. **Plan status in the tracker.** When `forge-spec` / `forge-feature` produce a plan
   the user approves or rejects, write one line to the tracker's In Progress block
   (`Plan: approved 2026-09-13` / `Plan: rejected, awaiting changes`). The
   compaction snapshot in (1) then carries it, with the same "do not re-propose"
   directive context-mode uses.

### Skip (YAGNI for a shell plugin)
- Sandboxed code execution, trigram + RRF, Levenshtein: needs a long-lived process or
  a lot of SQL; recommend installing context-mode alongside Context Forge instead.
- SQLite session-event DB: files already survive compaction; the snapshot in (1)
  covers the restore path at 1% of the code.
- Multi-platform formatter layer: the Antigravity adapter already exists; revisit only
  if a third platform appears.
- Stats dashboard changes: `metrics.sh` is opt-in and honest; ADR-0004's lesson
  (never count bytes the model never saw) is already respected.

## 6. Patterns to keep in mind while implementing
- Key every throttle or marker on the hook payload's `session_id`, never on `$PPID`.
- Make stdout the last write in a hook; put marker writes before it.
- Always exit 0 from hooks; non-zero shows a banner on every tool call.
- A once-per-session nudge dies at the first compaction; periodic (every Nth call)
  survives.
- When a redirect target is unavailable, degrade to passthrough rather than deny.
- Read your own prompt files as text in a test; it is the only regression guard that
  costs no model tokens.
