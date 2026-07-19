# Changelog

All notable changes to the **context-forge** plugin are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.43.0] — 2026-07-20

### Fixed (background agents never disappeared — root cause found in a hook trace)
`hook-logger` recorded a full 5-agent parallel review. The trace settled every
open question and exposed a self-inflicted bug from 0.40.1:

- **PostToolUse for a background agent fires AT SPAWN** (0–1 s after start:
  `pre Agent 00:14:12` → `post Agent 00:14:13`), not at completion.
- **SubagentStop fires at real completion** (49 s+ after start) **and it DOES
  carry `subagent_type`** — it names the agent that finished. Every observed
  stop matched the correct line. (The logger reported it "unnamed" only
  because it truncated the payload to 4 KB; the field sits deeper.)
- **There is no "spawn echo" SubagentStop.** The absorber built for one was
  swallowing genuine completions.
- **The bug**: because SubagentStop is named, it entered the named branch,
  found a B-stamped entry, and hit 0.40.1's "spawn ack → refresh the stamp,
  keep alive" path. Proof in the trace — each completion *refreshed* its
  agent's stamp instead of removing it (`forge-commenter … B1784481279` →
  `B1784481328` at the exact second of its SubagentStop). Background agents
  therefore never left the dashboard.

Each signal now has one unambiguous meaning and its own hook mode:

- `stop` (PostToolUse): plain entry → foreground finished → remove;
  B entry → spawn ack → leave untouched.
- `subagent-stop` (new, wired to the SubagentStop hook): always a completion →
  remove that agent's entry EXACTLY (prefer its B line), with an
  oldest-B fallback for unnamed payloads. No positional guessing.
- Echo absorption deleted entirely.
- `hook-logger.sh` now extracts fields from the FULL payload (only the stored
  copy is truncated) and records payload `bytes`, so a deep field can never
  mislead a future investigation again.
- Tests: real-trace replay (5 parallel agents completing out of spawn order,
  each removal exact), spawn-ack-never-removes regression, TaskOutput-poll
  immunity retained.

## [0.42.0] — 2026-07-19

### Added (hook diagnostic logger — stop guessing, start recording)
Agent lifecycle detection infers state from hook side-effects; when it
misbehaves, the fix must come from evidence. New `hooks/scripts/hook-logger.sh`
records ground truth, opt-in (`touch ~/.claude/forge-debug/enabled`):

- one NDJSON line per hook event (PreToolUse all tools, PostToolUse all
  tools, SubagentStop, UserPromptSubmit, Stop pre+post cleanup, SessionEnd):
  timestamp, event, session_id, tool_name, raw subagent_type,
  run_in_background flag, a snapshot of EVERY `.agents` state file at that
  instant (catches cross-session writes), and the first 4 KB of the raw
  payload — safely escaped, rotated at ~8 MB.
- `hook-logger.sh report`: events by type/tool, sessions seen, agent
  lifecycle timeline with state snapshots, recent-event tail.
- Zero cost when disabled (one file-stat); never writes to stdout.

## [0.41.0] — 2026-07-19

### Changed (presence mirrors the CLI — stopped agents leave the UI fast)
- **Single-session presence**: multiple CLI sessions on one machine mixed
  their agents into one "live" pool, so the dashboard showed workers from
  another window long after the session you were watching went idle. The
  header KPI, live card and office now follow ONLY the most recently active
  session (freshest tool/stream/skill/agent timestamp).
- **Background ghost TTL 20 min** (was 2 h): Claude Code does not reliably
  deliver completion signals for background agents; a hard TTL on B entries
  (write-side prune + read-side filter) guarantees finished agents disappear
  quickly even when every signal is missed. Foreground entries keep the 2 h
  net but are already swept at every turn end.

## [0.40.1] — 2026-07-19

### Fixed (spawned agents invisible in the dashboard — root-caused for good)
Five parallel background review agents ran in the CLI while the dashboard
said "AGENTS LIVE 0". Two compounding causes, both eliminated:

- **Unanchored hook matchers**: `"Task|Agent"` is an unanchored regex, so
  PreToolUse/PostToolUse also fired for tools like `TaskOutput` — and a
  `TaskOutput` PostToolUse carries no agent name, fell into the unnamed
  branch, and deleted one LIVE background entry per output poll. Matchers are
  now anchored (`^(Task|Agent)$`, `^Skill$`, `^(Write|Edit|MultiEdit|NotebookEdit)$`),
  and `agent-status.sh` additionally hard-rejects any named tool other than
  Task/Agent (defense in depth, works even with sloppy matchers).
- **Phrase-sniffing background detection**: background agents were only
  recognized if the spawn response contained the words "backgrounded agent" —
  wording that changes across Claude Code versions; when it didn't match, the
  spawn ack was treated as a foreground completion and removed the agent at
  birth. Detection is now STRUCTURAL: `run_in_background:true` in the
  tool_input stamps the entry `B<epoch>` at start; the spawn ack refreshes
  the stamp; only real SubagentStops (or the 2 h prune) remove it. The
  foreground removal path now explicitly never touches B entries. The phrase
  heuristic remains as a fallback for older wordings.
- Regression tests: TaskOutput-poll immunity, structural bg stamp + ack
  survival, and foreign named-tool rejection (bats).

## [0.40.0] — 2026-07-19

### Added (Live Work Engine — the kanban goes truly realtime)
- **Per-session tool stream**: `now-status.sh` now also appends every tool
  call to `~/.claude/forge-status/<sid>.stream` (rolling, trimmed to 80 once
  past 200 lines). `lib.mjs` parses it with a 2 h TTL.
- **Live card v2** in the In Progress column: the static "working now" pill is
  replaced with realtime session telemetry — current skill + who, the exact
  tool + target being executed right now, a timeline of the last 6 actions
  with per-tool colour coding (write/exec/read/agent/skill), run duration
  (gaps over 15 min start a new run), and action/target counts. Updates live
  over the existing SSE channel.

### Changed
- **The redesigned sprite office is now the DEFAULT.** `?classic=1` restores
  the old procedural office; `?sprites=1` remains accepted (redundant).
- Board badges are colour-coded: `spec ready` green, `archived spec` violet,
  `claimed` amber, `live` pulsing cyan, `high` red, failed attempts orange.

### Fixed (characters flickering while working)
- Desk footprints in the sprite office ended below the seat row, so seat
  cells were unwalkable — arriving agents oscillated at the rug edge
  (push-apart → walk-back every frame read as "blinking"). Footprints now end
  above the seats, and the crowd-separation pass skips anyone settling onto a
  seat.
- Speech bubbles no longer resize with the animated dots (fixed label width,
  dots render in reserved space), and the seated typing pose alternates at a
  calmer rate.

## [0.39.0] — 2026-07-19

### Added (redesigned sprite office — the `?sprites=1` mode grows a real office)
The sprite mode now renders a fully redesigned office scene (user-approved
mockup, 100% original pixel art): brick accent wall with a glowing neon
"FORGE · OFFICE" sign, a central glass meeting room (framed glass walls,
door gap, interior table + screen — the glass front renders OVER the people
inside for real depth), oak parquet floor, patterned zone rugs with legible
sign badges (PLANNING / BUILD / MEETING / LOUNGE), a server rack with
blinking LEDs, a coffee bar with espresso machine + menu board + stools, a
lounge (sofa with throw pillows, coffee table, bookshelf, glowing floor
lamp), wall dashboard TV with a chart, hanging plants, pendant lights, and a
warm light grade with window pools + soft vignette.

- Layout is data-driven: sprite mode swaps DESKS / MEET / OBSTACLES /
  BREAK_SPOTS so A* pathfinding, seats, meetings and breaks all work in the
  new floor plan. Claude works in the glass room; the archivist gets a bar
  seat; break spots move to the coffee bar, vending, lounge and ping-pong.
- Desks in sprite mode are detailed (dual monitors with animated code when
  working, cable tray, mug, papers, desk plant).
- Default (no flag) remains the classic procedural office, byte-for-byte
  unchanged behaviour.

## [0.38.0] — 2026-07-19

### Added (optional original agent sprites — `?sprites=1`)
The office can now render the ten forge agents as hand-authored pixel-art
sprites instead of the procedural characters. Every pixel is generated by
`dashboard/sprites/forge_sprites.py` — 100% original art, **no third-party
assets and no license attached**; the script is the source of truth and the
atlas (`dashboard/public/sprites.png`, 24×32 cells) is a regenerable build
artifact.

- Each agent keeps its identity: ROSTER color + a role accessory (Claude a
  headset, Architect a hard hat, Reviewer/Hunter a magnifier/target, Tester a
  flask, Aligner a level, Typer glasses, Commenter a quill, Scout a cap,
  Archivist an archive box). Poses: idle + walk in four directions + a
  seated/typing back view.
- Opt-in and non-breaking: add `?sprites=1` to the dashboard URL. Without it,
  or before the atlas loads, the proven procedural office renders unchanged.
  Guest (non-forge) agents always stay procedural — their per-name color can't
  come from the atlas.
- The realtime speech bubble, presence dots, break/idle behaviour and A*
  movement all carry over to the sprite path.
- Test: headless `?sprites=1` run asserts agents blit via `drawImage` (31
  dashboard tests pass).

## [0.37.0] — 2026-07-19

### Added (forge-office goes live — realtime + interactive)
Inspired by the pixel-office UX of `agent-office`, the dashboard now shows what
Claude Code is doing *as it happens* and can talk back — without ever writing
to the project.

- **Realtime "now working on"**: new `now-status.sh` hook (PreToolUse, all
  tools) records `<tool> <target>` per session to
  `~/.claude/forge-status/<sid>.now`; cleared on Stop. Claude's character shows
  it in a speech bubble, the header chip shows `⌁ Edit · …/file.ts`, and
  presence is truly live (tools firing = Claude at his desk typing).
- **Chat with the session**: chat bar under the office (click a character to
  address them). Messages POST to `/api/chat` → appended to
  `~/.claude/forge-office/inbox/<project>.ndjson` → the new `office-inbox.sh`
  UserPromptSubmit hook injects them as context at the next prompt, exactly
  once (atomic claim, no double delivery).
- **Assign from the kanban**: "▶ assign" on Next Up cards queues
  "build unit NN next" through the same inbox (`/api/assign`).
- **Presence dots** on every name tag: green = working, yellow = on a break,
  gray = idle at desk.
- **Visual polish**: desk shadows, work glow on active desks, meeting rug,
  clamped pixel speech bubbles.
- Server: `POST /api/chat`, `POST /api/assign`, `GET /api/inbox` (pending
  count). Writes go ONLY to `~/.claude/forge-office/` — the "never writes to
  the project" guarantee is unchanged. Still 127.0.0.1-only.
- Tests: `.now` parsing, agent TTL at read time, chat/assign endpoints with an
  isolated `HOME`, inbox delivered-once smoke test.

## [0.36.2] — 2026-07-19

### Fixed (ghost agents from dead sessions now clean themselves)
0.36.1 fixed the protocol going forward, but state files from already-ended
sessions stayed on disk forever — the per-session prune only runs when a hook
touches that same session's file, which never happens once the session is gone.
Users had to delete `~/.claude/forge-status/*.agents` by hand. Now automatic,
three layers:

- **`Stop` hook (`agent-status.sh turnend`)** — when the main turn ends, every
  foreground subagent's tool has returned, so leftover foreground entries are
  missed signals, not live agents: cleared on the spot (background `B` entries
  survive). Also sweeps orphaned `*.agents` files older than 2 h from OTHER
  dead sessions.
- **`SessionEnd` hook (`agent-status.sh end`)** — deletes the session's state
  file outright.
- **Dashboard read-time TTL** — `readSessions()` skips entries older than 2 h,
  so even a stale file that survives (hooks not yet reloaded, crashed session)
  can never render ghosts.

## [0.36.1] — 2026-07-19

### Fixed (agents stuck "working" in the dashboard)
Parallel subagent spawns (e.g. forge-review's seven lenses) left permanent
"working" ghosts in forge-office and the status line: the old stop protocol
needed TWO paired signals per agent, and since `SubagentStop` carries no agent
name the script guessed by position — under parallel distinct-name agents the
marks landed on the wrong entries and removals never matched (and when
`SubagentStop` didn't fire at all, the single named `PostToolUse` only *marked*,
so every agent stayed live until the 2 h prune).

- **Single-signal protocol**: a named `PostToolUse` means the Task/Agent tool
  returned → the foreground subagent is done → remove immediately. No pairing,
  no positional guessing; correct under any parallel spawn/finish interleaving
  and when `SubagentStop` never fires.
- `SubagentStop` now only serves background agents (echo absorption + true-end
  removal of `B` stamps); otherwise it is a no-op.
- Background detection tightened: response must say "backgrounded agent" AND
  arrive within 15 s of the spawn entry — a foreground agent whose output merely
  mentions the word is no longer misclassified.
- Regression test: 7 parallel distinct-name agents, three signal orderings
  (paired / burst / post-only) — zero leftovers.

## [0.36.0] — 2026-07-19

### Added (forge-reconcile — adopt out-of-band work)
Work that bypasses the process (manual hotfixes, teammate commits, sessions that
skipped `forge-build`) used to stay invisible to the tracker and specs — the exact
drift the methodology exists to prevent. New skill + hook close the gap:

- **`/forge-reconcile`** — detects commits with no unit/spec trail, groups them
  into clusters, delegates diff analysis to `forge-scout` (intent, files, invariant
  /standards check, test coverage), and — cluster by cluster, with approval —
  adopts each as a **retroactive spec** (`specs/archived/R-YYYYMMDD-slug.md`) plus
  tracker/build-plan entries, or dismisses it via `.reconcile-ignore`. Violations
  are never silently absorbed: they route to a fix unit or a conscious
  `forge-decision`. Done = detector reports CLEAN.
- **`detect-oob.sh`** — deterministic, read-only detector. In-band = message
  references a unit/spec, or the diff touches the context dir, or merge commit.
  Baseline = the commit that first added the tracker (pre-adoption history never
  flagged). Adopted commits are excluded via the `Reconciles: <shas>` line in the
  bookkeeping commit; dismissed ones via `context/.reconcile-ignore`. Scan window
  capped (`FORGE_RECONCILE_WINDOW`, default 200).
- **`SessionStart` hook** — runs the detector in `--hook` mode: prints nothing
  when clean, a ≤5-line token-free warning when out-of-band commits exist.
- Division of labor: `forge-audit` = what the docs *say* (docs vs code);
  `forge-reconcile` = what the process *knows* (git history vs tracker/specs).

## [0.35.1] — 2026-07-19

### Changed
- **Human-readable activity feed.** Raw `event key=value` rows become sentences:
  "**Architect** started working", "**Architect** finished · worked 4m 32s"
  (duration computed by pairing the stop with its start in the feed), "Skill
  **review** invoked", "Session ended — 9 files changed · context over budget".
  Timestamps are relative ("3m ago", "2h ago"; absolute on hover), unknown
  events keep a prettified raw fallback.

## [0.35.0] — 2026-07-18

### Changed (forge-brainstorm becomes a senior IT consultant)
The skill no longer just facilitates divergence — it consults. Persona: fifteen
years of production systems; bills for judgment, not options.

- **New step 0 "Consult first"**: interrogate the problem behind the request
  (pain, frequency, cost today), find the binding constraint (budget, team size,
  operational maturity, regulation), and classify the decision as a one-way or
  two-way door — which sets the thinking depth for everything after.
- **Diverge upgraded**: buy/SaaS/OSS must be considered before build (build is
  the most expensive option in the room), and every option gets an **industry
  reference point** — how real teams solve this today, or the admission that
  nobody does (novelty vs known dead end).
- **Stress-test doubled**: alongside the project checks (scope, invariants,
  lessons, effort), an industry checklist applied selectively — total cost of
  ownership, boring technology, YAGNI/speculative generality (≥2 consumers or
  build scoped), OWASP/security & data-regulation exposure, operability (failure
  story, 12-factor, who gets paged), scale honesty (10× not 1000×), team
  reality (match solution sophistication to operational maturity), and exit
  cost for vendors.
- **Converge is now opinionated**: one primary recommendation stated plainly
  ("if this were my project…"), honest trade-offs plus the cheapest way to find
  out you're wrong, a runner-up with its flip condition, and explicit
  "what NOT to do". "It depends" is a non-answer by rule.
- **Routing enriched**: ADR handoffs carry the industry reference points and
  rejected options as the alternatives-considered section.
- New rules: no cargo cult in either direction; contested practices are labeled
  contested; judgment labeled as judgment; respectful pushback over agreeable
  drift.

## [0.34.1] — 2026-07-18

### Fixed (background agents were still dying 5 s after spawn)
Live-verified failure: `agent_started 23:46:41` → `agent_stopped 23:46:46`
while the CLI showed the backgrounded architect still running. Root cause:
for background handoffs BOTH stop signals fire at spawn — `PostToolUse`
returns immediately AND a spurious `SubagentStop` ECHO follows seconds later,
so 0.31.2's two-signal protocol completed the pair instantly.

- **Background detection from the tool_response.** `PostToolUse` for a
  backgrounded Task carries "Backgrounded agent…" — the stop handler now
  recognizes it and stamps the entry `B<epoch>` instead of counting a signal:
  the plugin KNOWS the agent is still running.
- **Echo absorption.** A `SubagentStop` within 15 s of a fresh `B` stamp is
  consumed as the spawn echo (stamp → `B0`, presence intact, no metrics
  event); the NEXT `SubagentStop` is the true completion — entry removed,
  `agent_stopped` emitted at the real end.
- Foreground protocol unchanged; a foreground agent whose OUTPUT merely
  mentions "backgrounded" is not misclassified (order makes it safe — covered
  by a regression test). 15 agent-status bats cases total, including the
  exact observed trace.

## [0.34.0] — 2026-07-18

### Changed (dashboard visual redesign — ui-ux-pro-max pass)
Full visual overhaul against the design database (Developer Tool/IDE palette,
glassmorphism guidance, UX priority rules); all logic and realtime behavior
unchanged, 25 headless tests green.

- **Design system**: semantic tokens (surface/line/text/status scales),
  aurora background (violet/cyan/green radial glows on deep navy),
  glass panels (backdrop-blur 14px, translucent borders, layered shadows),
  Space Grotesk / Inter / JetBrains Mono type stack (system fallbacks).
- **New KPI strip**: Shipped / In Progress / Next Up / Agents Live tiles with
  status accent rails; office header shows live occupancy.
- **Sticky glass topbar** with gradient logo mark, live pill (cyan when
  working), pulsing connection ring.
- **Kanban polish**: colored column dots + count pills, hover lift cards,
  animated gradient border + blinking dot on the LIVE card, refined tags,
  SVG chevron pagers, pill search field with icon.
- **Feed as timeline**: color-coded event dots (skill=violet, start=green,
  stop=red, changes=amber), monospace timestamps, row fade-in.
- **Drawer**: dim overlay, smooth slide, refined markdown styles.
- **Standards**: SVG icons everywhere in chrome (no emoji UI glyphs),
  focus-visible rings, aria labels/roles (log, dialog, status), 4.5:1 text
  contrast on glass, transitions 150–300 ms, `prefers-reduced-motion`
  honored, responsive down to single column.

## [0.33.1] — 2026-07-18

### Changed
- **Spec drawer renders markdown** instead of raw text: headings, lists,
  checkboxes, tables, fenced code blocks, inline code, bold/italic, links,
  quotes, hr — via a tiny built-in renderer (zero deps; content HTML-escaped
  before transforming, so specs can never inject markup). Styled to match the
  dashboard; raw-`**`-soup is gone. Renderer covered by headless assertions
  (structure + escaping).

## [0.33.0] — 2026-07-18

### Changed (the dashboard is a realtime mirror, and the office behaves like an office)
- **Live header.** The headline badge now shows what Claude Code is doing RIGHT
  NOW ("⚒ review — Reviewer, Typer, Tester"), cyan while active; the tracker
  phase (markdown-stripped, truncated) only shows when nothing is running —
  history never masquerades as the present again.
- **No more work-flapping.** Presence is now snapshot membership: a character
  works for exactly as long as the state file lists its agent — not a
  time-based linger that expired between SSE refreshes and made working agents
  stand up and sit back down. The 3 s linger only covers the walk-off.
- **Office-like idle.** Idle characters sit at their own desks (dim monitor,
  still arms, occasional doze) like real employees, and every ~35–95 s take a
  short break — coffee at the kitchen, water cooler, vending machine, couch,
  or ping-pong (☕ 🥤 🏓 bubbles) — then return to their desk. The constant
  aimless wandering is gone; monitors light up only under real typing.
- **Layout**: Session notes moved to the right column under The Office.

## [0.32.1] — 2026-07-18

### Fixed (found by watching the live dashboard during a real forge-review run)
- **Guest characters.** Non-forge subagents (external review agents etc.) had
  no character — the live card named them while the office looked idle. Any
  unknown agent now gets a visiting character (deterministic color from its
  name, shortened label) that walks in, works at the meeting table, and leaves
  when truly done.
- **Claude's seat mirrors the CLI.** The main-session character now sits at
  the command desk exactly while a skill is sticky-active (linger only smooths
  the tail), instead of standing up after a fixed 16 s.
- **Honest live-card label.** With agents running, the label is the skill that
  actually launched them (most recent `skill_invoked` in the feed, <15 min) —
  an "active" flag from another/stale session no longer mislabels the work
  (observed: "worktree" shown during a forge-review run). Skill "active"
  older than 2 h is treated as stale everywhere (header, live card, seat).
- Verified end-to-end against a live run: 5 lenses spawned 23:03:22–40,
  stops recorded at real completions (60 s–2 m 09 s later), live card shrank
  agent-by-agent, meeting formed and dissolved, finished agents walked off.

## [0.32.0] — 2026-07-18

### Added (kanban v2 — the board is live, deep, and navigable)
- **LIVE card.** Whenever the CLI is actually doing something — an active skill
  and/or running subagents — In Progress leads with a pulsing live card
  ("⚒ review — Reviewer, Typer, Hunter working now"), even when no unit is
  tracked: live work is not always unit work, and the board should never say
  "(none)" while three agents are visibly busy in the office next to it.
- **Click a card → spec drawer.** Every unit card opens a slide-in drawer with
  the unit's full spec (`/api/spec?unit=N` — active spec first, archived
  fallback, integer-validated; Esc closes). The board is now the index into
  the project's entire spec history.
- **Dates on Completed** (spec archive mtime), **branch links on claim cards**
  (origin remote normalized ssh→https via the new `repoUrl`), and a **filter
  box** that searches all three columns across 110+ units before pagination.

## [0.31.2] — 2026-07-18

### Fixed (background agents were invisible in the office)
Root cause: for **backgrounded** subagents the Task tool returns at SPAWN, so
0.29's `PostToolUse` stop removed the agent the instant it started — a 52-second
review lens never appeared as working. Neither hook alone can be right:
`PostToolUse` knows WHO but (for background runs) not WHEN; `SubagentStop`
knows WHEN but not WHO.

- **Two-signal stop protocol.** Every subagent instance produces exactly two
  stop signals — `PostToolUse` (named) and `SubagentStop` (unnamed) — in
  mode-dependent order (foreground: SubagentStop→Post at the same moment;
  background: Post at spawn → SubagentStop at the true end). The FIRST signal
  only marks the state entry (`P` suffix); the SECOND removes it. In both
  orders, removal lands on real completion, and the office shows the agent
  seated and typing for its entire actual runtime.
- `SubagentStop` hook re-registered alongside `PostToolUse`; `agent_stopped`
  metrics now emit only at true completion; prune rewritten (awk, line-preserving
  — the old `read a t` loop silently dropped marked entries).
- Bats scenarios for both orders, three parallel background lenses (the exact
  forge-review case), mixed names, and marker-aware metrics.

## [0.31.1] — 2026-07-18

### Changed (dashboard: live WIP/Next Up truth + board pagination)
- **In Progress reads the phase line too.** Real trackers carry the live unit
  as `**In Progress: Unit 111** — …` in Current Phase rather than a section
  bullet — that now becomes a WIP card (an explicit In Progress section still
  wins). Live claims continue to appear as WIP.
- **Next Up reads `specs/`.** An unarchived spec file is the ground truth that
  a unit is planned — `forge-spec` writes the spec before the build plan grows
  a line. Active specs (tagged "spec ready") lead the column, then tracker
  Next Up, then build-plan lines; anything archived or currently in progress
  is excluded. The specs listing joined the realtime change signature, so the
  board moves within ~1.5 s of `forge-spec`/close-unit touching the dir.
- **Pagination: 5 cards per column** with ‹ n/m › pagers (counts stay in the
  column header) — 110 archived units no longer produce an endless Completed
  scroll.

## [0.31.0] — 2026-07-18

### Changed (dashboard: a truthful board and humans that walk like humans)
- **The kanban now mirrors the project's real context, not just one file.**
  `specs/archived/` is read as the ground truth for done work (the close-unit
  procedure moves every finished spec there — verified live: 109 units on the
  reference project): Completed shows tracker bullets first, then archived
  specs the tracker no longer lists (tagged "archived spec", `00-build-plan`
  excluded); Next Up drops any unit whose spec is already archived (stale
  build-plan lines can't resurrect shipped work); In Progress adds live claims
  the tracker doesn't mention yet ("unit 07 — claimed on feat/07-x"). Markdown
  artifacts (`**`, backticks) stripped from card text.
- **Realtime covers everything the board shows** — the change signature now
  includes `progress-archive.md` and the `specs/archived/` listing, so closing
  a unit updates the board within the 1.5 s poll → SSE push.
- **A\* pathfinding on a 10 px walk grid** — characters route AROUND desks,
  tables, the kitchen, and the ping-pong table (no corner cutting, seat cells
  reachable only as the exact final hop). Constant walking speed, facing-aware
  sprite (back of the head when walking away, eye shift when sideways),
  separation pushes clamped to walkable cells, and the pet re-picks its path
  when blocked. Nobody phases through furniture anymore.

## [0.30.1] — 2026-07-18

### Changed (the office is now a real simulation of the CLI session)
Feedback-driven rework of the dashboard's office view — state must read as work:

- **Working = seated & typing.** An active character walks to its desk and sits
  with its back to the viewer: chair drawn, arms alternating on the keyboard,
  monitor lit with scrolling code lines (dark when the desk is empty), pulsing
  work bubble. Painter's-order rendering keeps desks/characters layered right.
- **"Claude" (10th character)** — the main CLI session itself, at a distinct
  command desk: whenever a forge skill is active in any session, Claude sits and
  the bubble names it ("align…", "build…"). Subagents remain the other nine.
- **Idle = free roam + doze.** Idle characters wander the whole office
  (obstacle-aware waypoints — desks, tables, kitchen, ping-pong are no-go
  zones), with a soft separation force so they never stack, and float "z z z"
  when they stop. The lounge huddle is gone.
- **Presence linger** — events are momentary, so presence persists ~8 s after
  the last sighting (Claude 16 s): short-lived agents (a haiku scout) visibly
  arrive, sit, type, and leave instead of flickering. 3+ concurrent agents
  still convene at the meeting table ("review in session").

## [0.30.0] — 2026-07-18

### Added (forge-office: the dashboard ships inside the plugin)
No separate repo, no separate install — the dashboard is part of the plugin and
one command (or nothing at all, with autostart) away.

- **`dashboard/`** — the forge-office web dashboard bundled at the plugin root:
  zero-dependency Node (≥18) server + single-file pixel-art UI. Kanban parsed
  from `progress-tracker.md` (tolerant of real-world heading variants) merged
  with the build plan; live claims/locks from the git common dir (worktree-aware);
  live agent presence from the agent-status state files; activity feed from the
  local metrics. 2D office: procedurally drawn rooms (lounge/kitchen), desks,
  meeting table, ping-pong, pet — the nine agents as walking pixel characters
  with name tags; active agents sit at their desks, 3+ gather at the meeting
  table, idle ones wander the lounge. Read-only (never writes to a project),
  binds 127.0.0.1 only. 18 node tests (parser, resolvers, live-server smoke,
  headless 30-frame UI run) wired into CI on both OSes.
- **`forge-office`** (new, 22nd skill) + `forge-office.sh` launcher —
  `/forge-office` starts it for the current project (idempotent, verifies the
  server actually serves, opens the browser on macOS), `stop` / `status`
  manage it, **`autostart on`** makes the `SessionStart` hook start it
  automatically in every Context Forge project (silent; one URL line when it
  starts fresh; skips non-forge directories). Port via `$FORGE_OFFICE_PORT`
  (default 4820); state in `~/.claude/forge-office/`.
- 6 bats cases for the launcher (idempotent start against a real served
  request, stop/status, autostart marker, hook-mode silence rules, hooks.json
  wiring). Skill count: 21 → 22.

## [0.29.0] — 2026-07-18

### Changed (zero-manual-step observability)
- **Precise agent stop tracking.** `agent-status.sh stop` moved from `SubagentStop`
  (which never says which agent finished — 0.28.0 used a LIFO guess) to
  **`PostToolUse` matcher `Task|Agent`**, whose payload carries the same
  `tool_input.subagent_type` as the start event: stop now removes exactly the
  named agent (oldest instance for duplicates), with the LIFO pop retained only
  as a fallback for name-less payloads. The 0.28.0 approximation is gone.
- **Local metrics are ON by default** (opt-out: `touch
  ~/.claude/forge-metrics/disabled`). Rationale: the data never leaves the
  machine and records only event names, skill/agent names, and the project
  basename — while requiring a manual opt-in meant nobody had the data (or a
  working forge-office feed) in practice. Still NOT telemetry; still silent;
  still one file-existence check when disabled. The old `enabled` marker is
  ignored.
- Tests updated/extended (precise stop, duplicate instances, fallback pop,
  default-on + opt-out); suite now 100 cases.

## [0.28.0] — 2026-07-18

### Added (agent-lifecycle events — the plugin becomes observable)
Groundwork for the forge-office dashboard (external repo): live visibility into
which subagents are running, with zero model tokens and no behavior change.

- **`agent-status.sh`** (new hook script) — `start` on `PreToolUse` matcher
  `Task|Agent` records the spawning subagent (defensive `subagent_type` key
  extraction, plugin prefix stripped, path-safe session ids) into
  `~/.claude/forge-status/<session_id>.agents` (one `"<agent> <epoch>"` line per
  active agent, stack order). `stop` on the new `SubagentStop` hook pops the
  newest entry — the event doesn't say which agent finished, so LIFO is the
  documented approximation, with a 2 h prune as the safety net for crashed
  sessions. Same contract as skill-status.sh: silent stdout, always exit 0.
- When local metrics are enabled, both transitions also emit
  `agent_started` / `agent_stopped` events (with the agent name) through
  metrics.sh — the office view's history feed.
- 9 new bats cases (stacking, LIFO pop, pruning, unsafe ids, metrics emission,
  hooks.json wiring). Hook count: the plugin now registers `SubagentStop` for
  the first time.

## [0.27.0] — 2026-07-18

### Changed (schema migration is now automatic where it's safe to be)
Fixes 0.26.0's adoption gap: expecting every user to manually run migrate-schema.sh
after upgrading was never realistic. The rule that resolves the tension with "moving
the project's memory must never happen as a side effect" (0.18.2): **additive-only
steps run unattended; content-rewriting steps never do.**

- **`migrate-schema.sh --auto`** — SessionStart mode: applies migrations listed in
  `AUTO_SAFE_STEPS` (additive-only — new files/markers, existing content never
  rewritten; 0→1 qualifies since it's just the marker) silently and never fails or
  nags: non-forge dirs, half-set-up projects (forge-init's job), corrupt markers,
  and already-current projects all exit 0 with no output. On action it emits exactly
  one line ("schema stamped … commit it") so the session is told what happened;
  a future non-auto-safe step emits a one-line notice telling the user to run the
  migration deliberately (`--dry-run` first) instead of touching anything.
- **`SessionStart` hook** gained a second command entry running `--auto` — existing
  projects get stamped on their next session with zero manual steps. Manual-mode
  behavior (loud, refusing, idempotent) is unchanged.
- 6 new bats cases for `--auto` (15 schema tests total), including a jq check that
  hooks.json actually wires it; README + forge-init docs updated.

## [0.26.0] — 2026-07-18

### Added (the plugin gets its own engineering discipline: tests, CI, locks, schema, metrics)

- **Test suite for every deterministic script** (`tests/`, bats-core; 58+ cases).
  Hooks first: `guard.sh` (deny/allow, protected-paths globs vs absolute paths,
  corrupt/CRLF/junk config, notebook_path), `track.sh` (no-git, `.forge/`
  resolution, 0-byte tracker, budget thresholds, overwrite-never-append, silent
  stdout), `skill-status.sh` (plugin-prefixed names, path-traversal session ids,
  idle stickiness, pruning), and the **SessionStart inline command extracted from
  hooks.json via jq at test time** — the suite runs exactly what ships, including
  the pre-digest (old format) fallback and empty/metachar digest edge cases. Plus
  the `forge-worktree` claim lifecycle (atomic double-claim loss, rollback on
  failed worktree add, dirty-worktree refusal, cross-worktree visibility).
- **CI** (`.github/workflows/ci.yml`): shellcheck (`--severity=warning`) over every
  script in the repo, `claude plugin validate .`, a plugin.json/marketplace.json
  **version-drift gate**, the bats suite on **ubuntu + macos** (BSD stat/date/touch
  portability is tested, not assumed), and a **fixture matrix** — brownfield-empty /
  modules / no-git projects generated by `tests/fixtures/make-fixture.sh` and swept
  by `smoke.sh` (detect, SessionStart, track, guard, forge-index against each).
  Shellcheck immediately paid for itself: redundant lock-file patterns in guard.sh
  (SC2221/SC2222) cleaned up.
- **`forge-lock.sh`** (bundled with forge-worktree) — multi-engineer coordination
  beyond worktrees: `lock <name> [--wait N] [--steal]` / `unlock` is a **portable
  mkdir-based mutex** (no `flock` on stock macOS) with holder metadata
  (host/pid/user), stale detection (>15 m flagged, `--steal` to take over), used to
  wrap tracker edits during close-unit when others are active; `claim <NN>` /
  `release <NN>` extends the **same atomic claims dir** to in-place builds (no
  worktree), so worktree and in-place claims conflict correctly in both directions.
  close-unit.md gained a "Multi-engineer mode (shared checkout)" section; the
  tracker deliberately stays ONE file (an active window is one cheap Tier-1 read —
  per-unit splitting would tax every session to save rare merge conflicts; claims +
  lock + own-lines edits solve the actual race).
- **Context-schema versioning + migration** — one `.schema-version` marker per
  context dir (the files migrate together; per-file tags would add token cost and
  a drift source). `migrate-schema.sh` (forge-init scripts) migrates **stepwise
  and idempotently** with `--dry-run`, refuses half-set-up projects and
  newer-than-known schemas, and follows migrate-to-forge.sh's discipline (never
  auto-commits). `detect.sh` reports `schema: N|pre-schema`; forge-init stamps new
  setups (schema 1 = the 0.25.x layout) and offers the migration during Adopt &
  reconcile. Location moves stay `forge-migrate`'s job; format changes are now
  this script's job.
- **Opt-in local metrics** (`hooks/scripts/metrics.sh` + `forge-stats.sh`) — NOT
  telemetry: NDJSON appended to `~/.claude/forge-metrics/events.ndjson`, nothing
  ever leaves the machine, off until `~/.claude/forge-metrics/enabled` exists (one
  file-existence check when disabled). skill-status.sh records `skill_invoked`,
  track.sh records `stop_with_changes` (changed-file count + over-budget flag);
  only the project **basename** is stored, never full paths. `forge-stats.sh
  [days]` aggregates per event/skill/project and prints a **debug-pressure ratio**
  (forge-debug per forge-build — rising means specs or lessons need attention):
  data-driven iteration on the methodology, privacy intact.

### Changed
- `guard.sh`: lock-file deny patterns deduplicated (`*.lock|*-lock.json|*-lock.yaml`
  covers the previously listed named locks); behavior unchanged.
- `forge-worktree` SKILL: documents same-checkout parallelism via forge-lock.sh.
- README: version badge, testing section, metrics note, repo structure (tests/,
  .github/), forge-worktree row.

## [0.25.3] — 2026-07-18

### Changed (review calibration vs the /review-pr reference)
Benchmarked forge-review against the /review-pr reference on a real PR (#119).
Result: no Critical missed (the reference's own reviewers returned APPROVE after
forge-review's pass); most round-2 findings were order artifacts (issues introduced
by round-1's own fixes) or Advisory-class items forge-review filters by design. Two
genuine misses, both fixed:

- **`forge-commenter` (Eleonor)**: new hunt item 1b — comments stating verifiable
  technical facts (magic bytes, protocol constants, units, limits) must be checked
  against both the code AND the actual fact; a comment quoting wrong byte values
  misleads with authority (missed: wrong GIF/WebP byte docs). Model raised
  haiku → sonnet — factual verification needs the capability, and the comments
  lens is small so the cost delta is minor.
- **`forge-tester` (Karen)**: hollow-test definition sharpened — a test asserting
  only status/shape while skipping the core contract (exact query args, payload
  written, value transformed) is hollow even though it asserts *something*
  (missed: a GET filter test that never pinned the Prisma where/take args).

## [0.25.2] — 2026-07-17

### Changed
- Agent personas renamed to the user's real team roster: **DevTeam** (architect —
  the chief architect, deliberately holding the highest-leverage opus role),
  **Giuseppe** (reviewer), **Tatti** (aligner), **Karen** (tester), **Pat**
  (failure-hunter), **Adam** (typer), **Eleonor** (commenter), **Tim** (scout —
  fittingly, transport), **Tooba** (archivist). Same persona mechanics as v0.25.1:
  labels and signatures only, identifiers and rigor unchanged.

## [0.25.1] — 2026-07-17

### Added (agent personas)
- Every bundled agent now has an Indonesian-name **persona** — a display/signature
  layer on top of the unchanged technical identifier (renaming the identifiers
  would break skill references and strip the semantic signal the model uses to
  pick agents): Arif (architect, "the wise one"), Bima (reviewer, blunt and
  fearless), Laras (aligner, harmony), Titi (tester, meticulous), Galih
  (failure-hunter, digs to the core), Wanda (typer, form), Citra (commenter),
  Kelana (scout, the wanderer), Tata (archivist, order). Carried in each agent's
  frontmatter description (so callers see it and title spawns
  "Bima — multi-lens review of PR 42"), and each agent opens and signs its report
  with its persona (`Bima: RECOMMEND PASS`, `Laras: CONSISTENT`). Explicit rule:
  the persona changes the label, never the rigor. `forge-review` titles its
  fan-out with the crew's names; README agents table shows them.

## [0.25.0] — 2026-07-17

### Added (parallel builds)
Run multiple `forge-build`s at once — one per terminal — without collisions.
Naive parallelism in one working tree crashes three ways (shared test suite runs a
sibling's half-finished code; shared git state breaks under branch switches; shared
context files get clobbered), so parallelism = isolation:

- **`forge-worktree`** (new, 21st skill) + **`forge-worktree.sh`**: one unit = one
  git worktree = one branch = one terminal. `new <NN> <slug>` dependency-gates the
  unit (only claimable when every dependency is Completed), **claims it atomically**
  in the shared git common dir (`forge-claims/<NN>`, noclobber — visible to every
  worktree, double claims lose cleanly, claim rolls back if worktree creation
  fails), creates `../<repo>-uNN` on `feat/NN-<slug>`, and prints the exact
  next-terminal commands. `list` shows claims + ages; `done <NN>` refuses dirty
  worktrees, then removes and releases. Worktrees always hang off the MAIN repo
  even when invoked from inside a linked worktree; portable mtime (GNU/BSD stat).
- **`forge-build` is parallel-aware**: in a linked worktree it hard-stops unless
  the unit's claim names that worktree, and close follows close-unit.md's new
  **Parallel mode**: tracker edits touch only the unit's own lines (no rotation —
  merge conflicts stay small and mechanical), digest + index refresh are SKIPPED
  and reconciled once on main.
- **`forge-resume` reconciles after the merges**: refreshes the digest State from
  the merged tracker, rebuilds the retrieval index, and surfaces stale claims.
- Honest framing in the skill: parallel sessions buy wall-clock time, not tokens —
  each burns quota independently; 2–3 parallel units is the sweet spot.

## [0.24.0] — 2026-07-16

### Added (forge-review: multi-lens diff review)
- **`forge-review`** (new skill) — a comprehensive, multi-perspective review of a
  pull request, a branch, or the local working changes, adapted from the standalone
  `/review-pr` workflow into Context Forge conventions. Resolves the scope (PR via
  `gh`, the branch's PR, or the working diff), loads the project's context files
  (invariants, standards, lessons, the unit spec when the diff maps to one), and
  reviews across quality lenses — spec, standards, invariants, tests, errors, types,
  comments, silent-breakage, simplicity — with `--focus=` flags whose aliases match
  the external command's focus values. Findings are confidence-gated (≥80), deduped
  across lenses, and ranked Critical / Important / Advisory with a
  `RECOMMEND MERGE / CHANGES` verdict. Fans out per lens to the bundled review
  agents (below) — one pass for the `forge-reviewer`-owned lenses plus each applicable
  specialist; `parallel` launches them concurrently for a big diff. Read-only: it
  reports; fixes route back through `forge-fix` / `forge-build`. It is the wide
  quality sweep to `forge-verify`'s per-unit close gate.
- **Four bundled review specialists** (new agents) so `forge-review`'s per-lens
  fan-out is fully self-contained — no dependency on globally-installed agents, the
  review runs identically on any machine: `forge-tester` (tests lens, sonnet),
  `forge-failure-hunter` (errors/silent-failure lens, sonnet), `forge-typer` (types
  lens, sonnet), `forge-commenter` (comments lens, haiku). All read-only, each
  returning severity-ranked findings + a `RECOMMEND PASS/FAIL` verdict. Adapted from
  the external `/review-pr` specialist agents into Context Forge conventions
  (context-file aware, plugin severity vocabulary). The spec / standards / invariants
  / simplify / silent-breakage lenses remain owned by the existing `forge-reviewer`.
  Agent count: 5 → 9.

## [0.23.0] — 2026-07-14

### Added (scaling: module contexts + retrieval index)
Answers the growth problem: budgets keep the per-session cost flat, but a large
project saturates the curated files and makes history unfindable. Two layers, both
keeping markdown as the single source of truth:

- **Module contexts** (`context/modules/<area>.md`, ~8 KB each): when a core file
  genuinely outgrows tightening, `forge-compact` proposes the module split — per
  boundary, that area's architecture/conventions/gotchas move into its own budgeted
  file; the core file shrinks to the boundary map + global invariants and stays
  lean forever. Tier 2 loads only the module(s) a task touches (forge-build load
  step + architect read list), so the per-session cost stays flat regardless of
  module count. Budget-checked by `track.sh`; offered by `forge-init` for large
  projects; canonical convention in token-economy.md.
- **`forge-index.sh`** (new bundled script) — deterministic retrieval at zero
  model-token search cost: `build` indexes every markdown section under the
  context dir (specs, **archives**, decisions, lessons, patterns, progress
  history) into SQLite FTS5 (`.index.db` — git-ignored rebuildable cache; sqlite3
  ships with macOS/Linux, no new dependencies); `query "terms" [k]` returns top-k
  BM25-ranked `path:line` + title + snippet. Wired in: close-unit refreshes the
  index (new step 6; steps renumbered); `forge-resume` queries it for
  session-focus history; `forge-architect` queries for prior art (an existing
  decision must be honored or explicitly superseded, never unknowingly re-made);
  `forge-debug` queries for prior encounters with the symptom. Deliberately **not**
  a vector DB: no runtime deps, no embedding costs, deterministic — and the
  semantic-recall niche is already served by claude-mem for those who run it.

## [0.22.0] — 2026-07-14

### Added (loop engineering)
Codifies when an agent may loop on its own work — premise: models fail confidently,
so the source of truth must sit outside the model. New canonical reference
`skills/forge-build/references/loop-contract.md` (four rules: completion is
external; claims require evidence; retries add information; state survives
compaction), wired into forge-build, forge-build-all, forge-verify, forge-fix, and
forge-debug. Two of the four were already the plugin's architecture (external
completion conditions; file-based state); the release closes the other two:

- **Evidence-cited claims.** Every checklist "passes" must cite fresh external
  evidence — command + exit code for mechanical checks, file:line/observed output
  for inspectable ones; items with no obtainable external evidence are reported
  `UNVERIFIED — needs human check`, never silently self-attested (an honest
  UNVERIFIED beats a confident lie). forge-verify lists UNVERIFIED items separately
  in its verdict.
- **The attempt log.** Every failed verification appends
  `attempt N: [check] — tried: [approach] — result: [error]` to the unit's
  In Progress entry in the tracker (a file — survives compaction). Retries must
  read the log and **differ materially** from every logged approach (rewording the
  same fix is not a retry); the 2-failure escalation now **hands the log to
  forge-debug**, whose diagnosis starts from what is known to not work and may not
  relabel a logged failed attempt as a hypothesis. The close-unit procedure clears
  the log (recurring root causes become lessons first).

## [0.21.0] — 2026-07-14

### Added
- **`forge-health`** (new, 19th skill) — whole-codebase QA/QC. Rationale: every unit
  passes `forge-verify` individually, but nobody owned aggregate quality. Five
  dimensions: test-suite health (coverage gaps, hollow/skipped tests), error
  handling on critical paths, basic security hygiene (committed secrets,
  injection-prone spots, dependency audit — hygiene, not a pentest), performance
  smells (flag for measurement, never guess numbers), and dead-code inventory
  (mention, don't delete). Cheap by design: `forge-scout` sweeps with evidence,
  deterministic tools (coverage, `npm audit`) run as commands, `forge-reviewer`
  judges only the riskiest hotspots. Findings route through the existing pipeline
  (`forge-fix` / spec'd refactor units / lessons / linter recommendations) — never
  a mass edit. Deliberately NOT a new agent: per-unit QA is already
  `forge-verify` + `forge-reviewer`, and a second reviewer would duplicate, not
  deepen. Explicitly cross-referenced against `forge-audit` (docs vs code) and
  `forge-align` (consistency) to avoid overlap.

## [0.20.1] — 2026-07-14

### Changed (standards compliance gate)
Fixes real-world rule drift (e.g. "no `any`" written in code-standards.md, `any`
still appearing in builds). Root cause: rules were treated as *context* — read once,
then trusted to memory, which is exactly what drifts mid-session. Rules are now
treated as **contracts checked explicitly against the diff**:

- **`forge-build`**: implement step declares every `code-standards.md` rule and
  every lesson a hard constraint that *will be checked*; the verify loop gains a
  **standards compliance gate** — re-read `code-standards.md` + `lessons.md`, walk
  the diff **rule by rule** (from the files, never from memory), each rule pass or
  violating file:line; violations fail the unit like any red test. Same gate in
  `forge-build-all` (per unit) and `forge-fix` (per fix).
- **`forge-verify`**: new step 4 — the same rule-by-rule gate, explicitly **never
  tiered away**; explicit-rule violations are Critical ("the code works" is not a
  defense). Repeat offender rules get a lesson line so the build loop is pre-warned;
  mechanically-checkable rules get a recommendation to move into the linter.
  (Steps renumbered 4–7.)
- **`forge-audit`**: code-standards section now flags prose rules that could be
  mechanized into linter/compiler config — tooling enforces at zero token cost and
  never drifts.

## [0.20.0] — 2026-07-13

### Changed (branding)
- **The methodology now stands on its own name.** All references to the former
  methodology branding across the 18 skills, 5 agents, hooks (`[Context Forge]`
  SessionStart tag), `detect.sh` report header (`=== CONTEXT FORGE: STATE REPORT
  ===`), manifests, and CONTRIBUTING replaced with "Context Forge methodology" /
  "Context Forge project". README rewritten earlier with the same identity and no
  external references; historical CHANGELOG entries left untouched. The `context/`
  data layout and all commands are unchanged — this is naming only, no behavior
  change (minor bump because the SessionStart injection text and detector header
  are observable outputs).

## [0.19.1] — 2026-07-13

### Changed (Karpathy-guidelines adoption)
Adopted the gaps from the Karpathy-inspired guidelines
(github.com/multica-ai/andrej-karpathy-skills, MIT; credited in the README) —
injected where they're used (skills/agents/templates), NOT into always-loaded
context, per the token economy:

- **Simplicity first** — the real gap: all prior discipline governed *scope*, none
  governed simplicity *within* scope (a spec'd feature could ship 1000 bloated
  lines and pass review). Now in `forge-build`'s implement rules (minimum code, no
  single-use abstractions, no unrequested configurability, no impossible-scenario
  error handling, the senior-engineer test) and `forge-reviewer`'s hunt list
  (finding #7: overengineering).
- **Orphan rule** — clean up imports/variables/functions *your* change orphaned;
  leave pre-existing dead code (mention, don't delete); no orthogonal "improvements"
  to adjacent code — reviewer hunt #8 checks both directions.
- **Surface interpretations** — if the spec allows two readings, present both, never
  pick silently; push back when a simpler approach exists. In `forge-build`;
  ambiguity is an explicit stop condition in `forge-build-all`.
- Template `ai-workflow-rules.md` gained a **Code Discipline** section so new
  projects are born with these rules (Tier 2 — read when relevant, zero always-on
  cost). Goal-Driven Execution was already covered (specs + verify loop) and needed
  no adoption.

## [0.19.0] — 2026-07-13

### Added (sibling-consistency system)
Targets the classic vibe-coding failure: functionally-equivalent sibling features
(CRUDs, parallel screens) written in different dialects because the emergent pattern
lived only in code, never in the context files. Two-pronged:

- **Prevention — `context/patterns.md` exemplar registry** (template bundled,
  ~2 KB budget): one entry per repeatable shape — pattern name, **exemplar file
  path**, 3–5 must-match bullets. Registered at close-unit (new step 8) when a unit
  establishes a pattern; `forge-architect` must reference the pattern + exemplar in
  sibling specs; `forge-build` reads the exemplar before writing and mimics its
  dialect; `forge-verify` gained a sibling-consistency check (divergence from the
  exemplar = Warning, Critical when the spec required the pattern). Budget-wired
  into track.sh, token-economy.md, and forge-compact (drop dead exemplars, merge
  near-duplicates).
- **Detection — `forge-aligner` agent (sonnet, read-only, 6th agent)**: discovers
  feature families (parallel folders, same-suffix files), compares siblings
  pairwise against the registered exemplar or dominant member across seven
  dimensions (naming, layout, error handling, validation, data access, state
  wiring, tests), and reports Align/Info divergences with a
  `CONSISTENT` / `DRIFT: n families` verdict — the map, never the refactor.
- **`forge-align`** (new, 18th skill) — orchestrates: aligner report → judge with
  the user (majority is evidence, not authority; accepted divergences get a lesson
  line so they stop being flagged) → register patterns → fix via **alignment
  units** through forge-spec/forge-build (zero behavior change, suite stays green)
  — never a mass edit.

## [0.18.2] — 2026-07-13

### Added
- **`forge-migrate`** (new, 17th skill) — `/forge-migrate` wraps the migration
  script so nobody has to locate it: dry-run preview → explicit confirmation → run
  (git mv + entry-point rewrite + `.gitignore` guard) → detector verification →
  offered commit. Deliberately a command, not an auto-migration: moving the
  project's memory must never happen as a side effect. The script's refusals
  (framework `context/` folder, populated `.forge/`) are relayed, never bypassed.

## [0.18.1] — 2026-07-13

### Added
- **`migrate-to-forge.sh`** — one-command migration of `context/` → `.forge/`
  (bundled in forge-init's scripts; `--dry-run` supported). Safety-first and
  idempotent: refuses to move a `context/` folder that doesn't hold the
  methodology's files (i.e. your framework's context folder) and refuses when
  `.forge/` already has them; uses `git mv` so history is preserved; rewrites
  `context/` → `.forge/` paths in `CLAUDE.md`/`AGENTS.md`; and guards `.gitignore`
  using a **hypothetical-new-file probe** (tracked files pass `git check-ignore`
  even under matching ignore patterns — the real risk is future files like
  `progress-archive.md` silently not being committed), appending `!.forge/` when
  needed and warning if a later rule still overrides it. Never auto-commits.
  Referenced from forge-init's Placement step and the README.

## [0.18.0] — 2026-07-13

### Added (configurable context directory)
- **`.forge/` as an alternative context directory.** Motivations: avoid clashes
  with frameworks that use a `context/` folder, and a tidier repo root. One
  deterministic resolution rule everywhere — `.forge/` wins when it exists,
  otherwise the classic `context/` default: implemented in `detect.sh` (new
  `context_dir_path` report line), the `SessionStart` hook (injects the resolved
  dir and says so explicitly), `track.sh`, and `guard.sh` (protected-paths in
  either location). `.forge/` was chosen over `.claude/context/` deliberately:
  tool-agnostic (works for AGENTS.md/Codex users too) and absent from common
  `.gitignore` templates.
- `forge-init` **Placement step**: asks once on fresh setups, auto-recommends
  `.forge/` when a root `context/` already holds code, rewrites entry-point paths
  accordingly, and **guards `.gitignore`** (adds `!.forge/` if a pattern would
  ignore it) — the context files are the project's memory and must stay committed.
- Migration for existing projects: `git mv context .forge` — picked up
  automatically.
- Canonical rule documented in token-economy.md ("every `context/...` path means
  the resolved dir"); entry-point templates carry the substitution note; README
  updated.

## [0.17.0] — 2026-07-13

### Added
- **`forge-brainstorm`** (new, 16th skill) — the fuzzy front-end the flow was
  missing: every existing skill assumes you already know what you want
  (`forge-prompt` sharpens a request, `forge-feature` assumes a feature,
  `forge-decision` records a decision); vague-idea conversations happened in free
  chat, ungrounded and evaporating with the session. The flow: **diverge** (3–6
  genuinely different options, always including "don't build it") → **stress-test**
  each against project-overview scope/out-of-scope, architecture invariants,
  recorded lessons, and rough effort in units → **converge** (1–2 survivors with
  honest trade-offs) → **route** so ideas never evaporate: `forge-feature` (build),
  `forge-decision` (ADR), the new **`context/ideas.md` parking lot** (one line per
  idea with wake condition, ~1.5 KB budget, never auto-read, template bundled), or
  an explicit dead end. Planning only — never touches code; in-session by design
  (dialogue, not a subagent job); Tier-1 + project-overview load.
- `ideas.md` integrated into the discipline: budget row in token-economy.md, `Stop`
  hook budget check, and a forge-compact treatment (drop dead ideas, promote ripe
  ones).

## [0.16.2] — 2026-07-12

### Changed (quota cost tuning)
- **Tiered adversarial review.** `forge-verify` now spawns the `forge-reviewer`
  subagent automatically only for `[complexity: high]` units, invariant/protected-area
  changes, code other units depend on, or on request; standard units are reviewed
  in-session against the same hunt list and severity format — same rigor, no extra
  subagent session per small unit. `forge-build-all` follows the same tiering.
- **Quiet verification output.** `forge-build` / `forge-build-all` now run tests and
  linters with quiet/failures-only reporters — a green suite costs one summary line
  instead of thousands of passing-test lines re-read every verify-loop iteration.
- **Subagent & background cost section in token-economy.md**, including a
  **claude-mem interop note**: claude-mem's `PostToolUse` background compression
  calls a model on every tool output — invisible in context but counted against the
  same usage quota; recommendation is to disable it during long build runs (this
  plugin's tracker/lessons/archives already record the build trail
  deterministically) and re-enable it for exploratory sessions.

## [0.16.1] — 2026-07-12

### Added
- **Per-unit complexity marker → model recommendation.** `forge-architect` (who has
  read everything) now marks build-plan units `[complexity: high]` (+ short reason)
  per canonical criteria in unit-rules.md: cross-boundary logic, concurrency/state
  machines/subtle migrations, large multi-file refactors, or irreducibly ambiguous
  specs; standard units carry no marker. At build time, `forge-build` recommends
  `/model opus` when picking a high-marked unit, and `forge-build-all` lists
  high-marked units at scope confirmation and recommends a stronger model for the
  run (or excluding them for a supervised pass) — because an autonomous run has no
  human checkpoint between units. Always a recommendation, never a gate: the
  rationale is simply that a failed verify loop + debug session costs more than the
  model-price difference.

## [0.16.0] — 2026-07-12

### Added (model-pinned agents)
- **Four bundled subagents** in `agents/`, routing each kind of work to the right
  model — maximum intelligence at the highest-leverage/lowest-frequency point, cheap
  models for bulk work, and the agent's reading stays out of the main session's
  context:
  - **`forge-architect` (opus)** — decomposition + six-section spec writing + deep
    ADR analysis; follows unit-rules.md and the spec template; writes spec files
    directly and returns a summary + open questions; never invents answers to
    design-changing ambiguities. Used by `forge-spec`, `forge-feature`,
    `forge-decision`.
  - **`forge-reviewer` (sonnet)** — adversarial, read-only diff-vs-spec review with
    a prioritized hunt list (spec mismatch, invariant violations, missing/hollow
    tests, silent breakage, edge cases, convention drift) and a
    `RECOMMEND PASS/FAIL` verdict. Used by `forge-verify` (replaces the
    general-purpose subagent), `forge-pr`, `forge-fix`.
  - **`forge-scout` (haiku)** — read-many-conclude-little sweeps with three mission
    types: stack & structure (forge-init brownfield), drift evidence (forge-audit),
    failure isolation (forge-debug). Compact findings with file:line evidence.
  - **`forge-archivist` (haiku)** — mechanical close-unit bookkeeping per
    close-unit.md and forge-compact's measurement pass; no judgment calls, never
    deletes content.
- Delegation points documented in the skills, each with an **in-session fallback**
  so the plugin still works where a pinned model isn't available (edit `model:` in
  `agents/*.md`, e.g. to `inherit`). Deliberate non-delegations: `forge-build`
  executes in the main session (intelligence is paid up front in the spec);
  `forge-debug` keeps diagnosis in-session and delegates only evidence gathering.
- README: new **Agents** section (model table + rationale), features bullet,
  repo-structure entry.

## [0.15.0] — 2026-07-12

### Changed (build loop hardened — tests first-class, explicit iterate/escalate)
- **Specs now have six sections**: a **Tests** section (level + behavior each test
  must prove, matching the project's real test stack) sits between Dependencies and
  "Verify when done". Tests are written *during* implementation, not after;
  "none — [reason]" is allowed for pure-visual/config units but must be stated.
  Template updated; unit-rules.md's good-unit checklist now includes the unit's tests.
- **`forge-build` step 4 is now an explicit loop with a hard escape**: run the unit's
  tests → **full suite (regression gate)** → build/typecheck/lint → spec checklist;
  on failure, correct in scope and **re-run from the top** (a fix can break something
  else); **the same check failing after two fix attempts → mandatory switch to
  `forge-debug`** — no third blind fix. Step 3 requires writing the spec'd tests as
  part of implementation (older specs without a Tests section: propose tests and
  confirm).
- **`forge-build-all`**: same test-inclusive implement/verify per unit, and "same
  check fails after two fix attempts" is now an explicit run-stop condition.
- **`forge-verify`**: new check — every test the spec's Tests section lists must
  exist and pass (spec'd-but-unwritten tests = FAIL; older spec without the section =
  Warning); the automated-checks step now runs the **full suite** as the regression
  gate, not just "tests if they exist".

## [0.14.0] — 2026-07-10

### Added (status line skill indicator)
- **`hooks/scripts/skill-status.sh`** — zero-token recorder maintaining a per-session
  state file (`~/.claude/forge-status/<session_id>`, format
  `active|idle <skill> <epoch>`). Wired via two new hook registrations:
  `UserPromptExpansion` (catches `/forge-*` slash commands via `command_name`) and
  `PreToolUse` matcher `Skill` (catches model-invoked skills; parses the undocumented
  tool_input defensively across several key names). The existing `Stop` hook now also
  downgrades `active` → `idle` for **sticky semantics**: `⚒ forge-fix` while the turn
  runs, `(forge-fix)` dimmed for 30 minutes across confirmation pauses, then gone.
  Silent by design (hook stdout can be injected as context), always exits 0, prunes
  state files older than a day, and validates session ids before using them as paths.
- **`statusline/statusline.sh`** — ready-made reference status line consuming that
  state file: skill indicator + model + git branch + cost + context %. Documented
  one-time setup in the README (copy + `statusLine` setting with
  `refreshInterval: 1000`, or merge via `/statusline`). The state-file format is the
  stable contract, so any custom status line can integrate it.

### Changed
- Skill `metadata.version` values bumped to 0.14.0.

## [0.13.1] — 2026-07-10

### Added
- **Explicit argument handling in all 15 skills.** Every SKILL.md now has an
  `## Argument` block defining what text after the command means and the fallback when
  it's absent — e.g. `/forge-fix login button dead on page A` is the intake description
  (no re-asking), `/forge-build unit 04` selects the unit (else Next Up from the
  tracker), `/forge-decision use Redis for cache` drafts the ADR directly,
  `/forge-lesson never use barrel files` distills the lesson, `/forge-resume unit 05`
  focuses the session, `/forge-audit architecture` narrows the audit,
  `/forge-compact the tracker` targets one file. Previously only `forge-build` and
  `forge-build-all` documented this; the rest relied on the model guessing.

## [0.13.0] — 2026-07-10

### Added
- **`forge-fix`** (new, 15th skill) — the intake for bug reports in shipped work,
  closing a trigger gap: "there's a bug in X" previously matched no skill (forge-debug
  targets being *stuck*; forge-build's correct step targets the *current* unit), so
  fixes happened outside the methodology with no tracker update, no lesson, and no
  scope discipline. The flow: intake (check `lessons.md` first — the bug may be a known
  rule) → reproduce → **triage** (obvious cause & small blast radius ⇒ fix in scope;
  non-obvious / invariant in question / two failed attempts ⇒ hand off to `forge-debug`
  — one diagnosis engine, not two) → verify (including the touched unit's archived
  checklist) → close with the shared close-unit discipline, a lesson when the root
  cause generalizes, and a `fix/NN` branch via `forge-pr`. Explicit boundaries route
  behavior-change requests to `forge-feature` and design-heavy fixes to `forge-spec`.
- `forge-debug` now documents the handoff contract with `forge-fix` in both directions.

### Changed
- Skill `metadata.version` values bumped to 0.13.0.

## [0.12.0] — 2026-07-10

### Added (persistent memory)
- **`context/lessons.md`** — per-project memory: one-line lessons
  (`- [area] symptom → rule`) capturing corrections and hard-won diagnoses so they are
  never re-paid in tokens. Auto-captured by `forge-debug` (step 7, when a confirmed root
  cause is likely to recur) and by the close-unit procedure (when the user corrected the
  approach in a generalizable way); read at load time by `forge-build`, `forge-build-all`,
  and `forge-debug` (which now checks lessons *before* diagnosing). Budget ~1.5 KB /
  ~400 tokens; when full, lessons are merged or **promoted** into
  `code-standards.md`/`ai-workflow-rules.md` — the file is a staging area for rules.
  Template bundled; created by `forge-init`; reported by `detect.sh` (`lessons: yes|no`);
  budget-checked by the `Stop` hook, `forge-audit` (with a contradiction/staleness
  check), and `forge-compact` (dedupe/promote/drop treatment).
- **`~/.context-forge/preferences.md`** — cross-project memory: the user's tooling,
  convention, and workflow defaults. Read **only** by `forge-init` to pre-fill greenfield
  answers and brownfield drafts (project evidence always wins); written only with
  explicit per-line approval. Never stores secrets or project-specific facts.
- **`forge-lesson`** (new, 14th skill) — "remember this" / "forget that" / "show my
  lessons": distills input to a one-line lesson, routes it (project vs global), dedupes,
  enforces budgets, and promotes recurring lessons into the real context files.
- **Memory contract** defined canonically in
  `skills/forge-lesson/references/memory.md` (formats, budgets, read/write rules,
  conflict order: code > context files > lessons > global preferences).

### Changed
- Tier map (digest template, `CLAUDE.md`/`AGENTS.md` templates, token-economy.md) now
  includes `lessons.md` as a small Tier-2 read for building/debugging.
- Skill `metadata.version` values bumped to 0.12.0.

## [0.11.0] — 2026-07-10

### Added (token economy — tiered context loading)
- **`context/context-digest.md`** — a compact (~2.5 KB / ~600 token) brief of the whole
  context set: project one-liner, stack shape, top invariants, key conventions, current
  state, and a tier map. Created by `forge-init` (new template bundled), refreshed in its
  State section at every unit close (new step in the shared close-unit procedure), and
  checked for staleness by `forge-audit`.
- **Tiered loading** across the whole plugin. Tier 1 (always): entry point + digest +,
  when implementing, the tracker. Tier 2 (per task): only the full context file(s) the
  task touches. Tier 3 (everything): `forge-init` / `forge-audit` / `forge-compact`.
  Canonical definition in `skills/forge-resume/references/token-economy.md`; the entry
  point templates (`CLAUDE.md`/`AGENTS.md`), `forge-resume`, `forge-build`, and
  `forge-build-all` now load by tier instead of reading all six files. Guiding rule:
  *never guess to save tokens* — if a decision depends on an unread file, read it first.
- **`forge-compact`** (new, 13th skill) — guided token-maintenance pass: measures every
  context file against its soft budget, compresses over-budget files with per-file
  approval (rewrites for density, never drops facts), rotates tracker history, moves
  rarely-needed detail into on-demand `context/reference/` files, and (re)generates the
  digest. For pre-digest projects, generating the digest is the single biggest saving.
- **`SessionStart` hook now injects the digest** (with tiered-loading instructions)
  instead of the full tracker, falling back to the old tracker injection for projects
  that predate the digest. Still a zero-token command hook.
- **Budget guard in the `Stop` hook** — `track.sh` now also lists any context file over
  its soft budget in `context/.last-session.md`, with the recommended fix. Deterministic
  `wc -c` check; costs nothing until read.
- `detect.sh` reports `digest: yes|no` so `forge-init` / `forge-audit` / `forge-resume`
  can see at a glance whether the project has a digest.

### Changed
- **Unit rules deduplicated**: what a good unit is + ordering rules now live once in
  `skills/forge-spec/references/unit-rules.md`; `forge-spec` and `forge-feature`
  reference it instead of carrying diverging copies.
- `forge-audit`'s budget section now defers to the canonical budgets in
  `token-economy.md` and gained a digest-staleness check.
- Skill `metadata.version` values bumped to 0.11.0.

## [0.10.1] — 2026-07-10

### Fixed
- **README brought back in sync**: version badge 0.8.0 → current, duplicate/broken Hooks
  table header removed, leftover "context-\* skills" label renamed to `forge-*`, and the
  0.9.0/0.10.0 features (`context/specs/archived/`, `context/progress-archive.md`,
  tracker rotation, `forge-audit` budget check) are now documented in Features and
  "The six files".
- **`marketplace.json` version drift** (was still 0.9.0 while the plugin was 0.10.0);
  both manifests now carry the same version.
- **`templates/AGENTS.md` synced with `templates/CLAUDE.md`** — the lean-window /
  `progress-archive.md` note now appears in both entry-point templates.
- **`detect.sh` accuracy**: `spec_files` no longer counts `00-build-plan.md` as a spec,
  and the placeholder counter no longer matches markdown links `[text](url)` or task
  checkboxes `[ ]`/`[x]` — fixing false REPAIR verdicts on fully filled files.
- **Shipping is one door again**: the Close step of `forge-build` and the three-prompt
  loop in `forge-spec` now point to `forge-pr` instead of instructing a raw branch push
  (also fixes the "suggest the suggested git step" typo).
- **`guard.sh`**: project-relative globs in `context/protected-paths` (e.g.
  `src/generated/*`) now also match when the tool sends an absolute path, and the guard
  reads `notebook_path` too; the `PreToolUse` matcher now covers `NotebookEdit`.
- `forge-audit`: `ai-workflow-rules.md` now has a soft budget like the other core files;
  minor formatting fix in the Output section.

### Changed
- **Close-unit logic deduplicated.** The full procedure (tracker update + rotation, spec
  archival, build-plan tidy, context-file sync) now lives once in
  `skills/forge-build/references/close-unit.md`; `forge-build`, `forge-build-all`, and
  `forge-pr` reference it instead of each carrying their own copy. The active-window
  numbers (~10 Completed / ~8 Session Notes / ~6 KB) are defined there canonically.
- All skill `metadata.version` values bumped to match the plugin version.

## [0.10.0] — 2026-06-15

### Added (token efficiency)
- **Automatic progress-tracker rotation.** The tracker now holds an *active window* only
  (current phase/goal, In Progress, Next Up, Open Questions, the ~10 most recent Completed
  units, and the ~8 most recent Session Notes). When a unit closes and the tracker grows
  past that window — or past ~6 KB / ~1,500 tokens — `forge-build`, `forge-build-all`, and
  `forge-pr` move the oldest Completed entries and Session Notes into a new
  `context/progress-archive.md` (history; appended newest-first). Because the tracker is
  re-read on every `forge-resume` / `forge-build`, this caps a file that previously grew
  unbounded — a pure token saving with no loss of active context. The archive is **not**
  auto-read.
- **Compact session notes.** Close steps now write a one- to two-line Session Note instead
  of an open-ended paragraph, keeping the recurring read cost low.
- **Context budget check in `forge-audit`.** The audit now measures each context file's
  size (bytes / approx tokens) against soft budgets and recommends trimming or rotating
  when a file is over — the tracker (~1,500 tokens) and core files (~2,500 tokens each).
- **Prompt-cache-friendly read order** documented in `forge-resume`: stable files first,
  the volatile tracker last, so the unchanged prefix stays cacheable across sessions.

### Changed
- `forge-init` templates (`progress-tracker.md`, `CLAUDE.md`) now declare the lean active
  window and the `progress-archive.md` convention, so new projects start token-efficient.

## [0.9.0] — 2026-06-15

### Changed (breaking)
- **All commands renamed from `context-*` to `forge-*`** for a shorter, faster-to-type
  prefix tied to the plugin name. `context-build` → `forge-build`, `context-spec` →
  `forge-spec`, and so on for all twelve skills (`forge-audit`, `forge-build`,
  `forge-build-all`, `forge-debug`, `forge-decision`, `forge-feature`, `forge-init`,
  `forge-pr`, `forge-prompt`, `forge-resume`, `forge-spec`, `forge-verify`). The
  **methodology name ("Six-File Context Methodology") and the `context/` data directory
  are unchanged** — only the command/skill names moved.

### Added
- **Completed specs are now archived.** When a unit closes, `forge-build` /
  `forge-build-all` / `forge-pr` move its spec from `context/specs/` into
  `context/specs/archived/`, and move its line in `context/specs/00-build-plan.md` from
  the active `## Units` list into a `## Completed` section at the bottom. The active
  `specs/` folder and build plan therefore only ever show work that is still pending,
  while finished specs stay on disk as a record. `forge-resume` and `forge-audit` are
  aware of the `archived/` folder (resume treats the active `specs/` as the remaining
  work; audit flags archive/build-plan drift).

## [0.8.0] — 2026-06-14

### Added
- **`context-build-all`** skill — runs the implement → verify → close loop across every
  remaining unit in the build plan, in order, updating the tracker after each. It is the
  autonomous, multi-unit counterpart to `context-build`. For safety it builds strictly to
  each spec, verifies every unit, and **stops at the first failure** (missing spec,
  failed verification, ambiguity, or invariant violation) instead of continuing on an
  unverified foundation. It does not auto-push or open PRs — shipping stays with
  `context-pr`. Supports an optional scope (e.g. "build units 3–7").

## [0.7.0] — 2026-06-14

### Changed
- **Both prompt-based hooks are now command-based (zero model tokens).** They run small,
  tested shell scripts instead of per-event model evaluations, removing the recurring
  token/latency cost while keeping the hooks active.
  - `PreToolUse` → `hooks/scripts/guard.sh`: deterministic guard that denies edits to
    generated/lock/vendor files (`node_modules`, `*.lock`, `*-lock.json`, etc.) and to any
    glob listed in an optional `context/protected-paths` file; allows everything else.
  - `Stop` → `hooks/scripts/track.sh`: if code changed (per git) without the tracker being
    updated, writes `context/.last-session.md` (timestamp + changed files). Overwrites, so
    it never grows; writes nothing to stdout, so it never re-wakes the model.
- `context-resume` now also reads `context/.last-session.md` when present.

### Notes
- Semantic/nuanced invariant checking now lives in `context-verify` (run per unit) instead
  of on every edit. Add `context/.last-session.md` to your project's `.gitignore` if you
  don't want to commit it.

## [0.6.2] — 2026-06-13

### Removed
- **`UserPromptSubmit` hook.** A prompt-based `UserPromptSubmit` hook can return a
  `block` decision, and in practice it blocked legitimate user messages it judged
  "not substantive" (e.g. bug reports and in-progress notes) instead of merely adding
  context. Because this hook intercepts every prompt and can block input, it is removed
  for reliability. Prompt optimization remains available, safely and on demand, via the
  **`context-prompt`** skill.

### Notes
- Remaining prompt-based hooks are `PreToolUse` (guards invariants on writes) and `Stop`
  (keeps the tracker in sync); neither blocks user input.

## [0.6.1] — 2026-06-13

### Fixed
- **Hook loading failure** in Claude Code (`Hook load failed: expected record, received
  undefined` at path `hooks`). The plugin's `hooks/hooks.json` listed events at the top
  level; Claude Code requires them wrapped under a top-level `"hooks"` key. All four
  events are now nested correctly under `hooks`.

## [0.6.0] — 2026-06-13

### Added
- **`context-prompt`** skill — an opt-in prompt refiner that turns a rough request into a
  high-quality, context-aligned prompt or spec (goal / scope / constraints / acceptance),
  asking 1–2 clarifying questions only when needed. It never silently changes intent.
- **`UserPromptSubmit`** hook — a conservative, *augmenting* hook: for substantive build
  requests in a `context/` project it injects relevant context pointers and, when the
  request is vague, a suggested sharper phrasing. It never rewrites the user's message and
  stays silent for casual chat and one-line fixes.

### Notes
- The plugin now has three prompt-based hooks (`UserPromptSubmit`, `PreToolUse`, `Stop`).
  Each adds a small evaluation; remove any block from `hooks/hooks.json` to disable it.

## [0.5.0] — 2026-06-13

### Added
- `.claude-plugin/marketplace.json` so the repository is installable as a Claude Code
  plugin marketplace (`/plugin marketplace add yerros/context-forge`).
- Open-source project files: a rewritten OSS-standard `README.md` (English), `LICENSE`
  (MIT), `CONTRIBUTING.md`, and `.gitignore`.

### Changed
- Renamed the plugin from `six-file-context` to **`context-forge`** for branding.
- Author set to **yerros** (https://github.com/yerros); added homepage.
- No functional changes to skills/hooks — all ten skills, three hooks, and the detector
  are unchanged.

## [0.4.0] — 2026-06-13

### Added
- **Deterministic state detection** (`skills/context-init/scripts/detect.sh`, read-only):
  reports a `verdict` of `SETUP`, `ADOPT`, or `REPAIR` plus the facts behind it (which of
  the six files exist, count of unfilled `[placeholder]` markers, entry point, decisions/
  specs presence, codebase detection). Skills act on facts instead of guessing — this is
  the core robustness fix for "project already has context files".
- **Adopt & reconcile flow** in `context-init` for projects that already use the
  methodology (manual setup or a prior run): recognizes the existing files, fills only
  gaps, **never overwrites real content**, confirms before every write, and is idempotent
  (running it on a healthy project changes nothing).

### Changed
- `context-init` now runs the detector first and branches on the verdict.
- `context-audit` and `context-resume` run the detector first and handle the
  not-set-up / incomplete cases gracefully.

## [0.3.0] — 2026-06-13

### Added
- **`context-feature`** skill — add a feature to a working project: updates scope in
  `project-overview.md`, inserts correctly-ordered units into the build plan, and
  generates the spec(s) without breaking existing work.
- **`context-debug`** skill — stop-and-diagnose strategy for when the agent is stuck or
  keeps getting something wrong (reproduce, isolate, re-read invariants, present options,
  fix root cause in scope).
- **`context-pr`** skill — closes a verified unit with git: branch `feat/NN`, Conventional
  Commit, and a PR with a spec-derived summary (uses `gh` when available).
- **`context-decision`** skill — logs ADRs to `context/decisions.md` and keeps
  `architecture.md` in sync; bundles a `decisions.md` template.
- **Stack profiles** — `context-init` now detects the project type (web / backend-API /
  mobile / CLI-library / data-ML) and adapts which files matter and what each emphasizes
  (e.g. drops or repurposes `ui-context.md` for a pure API). See
  `skills/context-init/references/stack-profiles.md`.

### Changed
- `Stop` hook now also maintains a dated "Resume here:" note in Session Notes.
- README documents ten skills, three hooks, and stack profiles.
- Version bumped to 0.3.0.

### Notes
- A `SessionEnd` LLM summary was considered but not added: the hook system only supports
  prompt-based hooks on `Stop`, `SubagentStop`, `UserPromptSubmit`, and `PreToolUse`.
  The `Stop` hook covers session continuity instead.

## [0.2.0] — 2026-06-13

### Added
- **`context-build`** skill — runs the disciplined implement → verify → close loop for
  a single spec'd unit, strictly in scope, and keeps the progress tracker in sync.
- **`context-verify`** skill — runs the unit's verification checklist plus
  build/typecheck/lint and an adversarial subagent review before a unit is closed.
- **`context-audit`** skill — detects drift between the six context files and the
  actual codebase and offers to update the docs.
- **Hooks** (`hooks/hooks.json`):
  - `SessionStart` — injects `progress-tracker.md` and a reminder to read the context
    files when the project has a `context/` folder; silent otherwise.
  - `Stop` — keeps `progress-tracker.md` in sync after a response that changed code.
  - `PreToolUse` (Write/Edit/MultiEdit) — checks changes against the invariants in
    `architecture.md` and rules in `code-standards.md`; flags or blocks clear violations.

### Changed
- README documents all six skills and the three hooks.
- `plugin.json` description and version bumped to 0.2.0.

### Notes
- The `Stop` and `PreToolUse` hooks are prompt-based and add a small LLM evaluation per
  response / per edit. Remove the relevant block in `hooks/hooks.json` to disable.

## [0.1.0] — 2026-06-13

### Added
- Initial release.
- **`context-init`** skill — scaffolds the `context/` folder (six files) plus the entry
  point (`CLAUDE.md`/`AGENTS.md`). Greenfield mode runs a planning conversation;
  brownfield mode analyzes the existing codebase, drafts files from evidence, and
  confirms before writing.
- **`context-spec`** skill — builds the ordered build plan and writes five-section spec
  files per feature unit.
- **`context-resume`** skill — reloads the six files + progress tracker and briefs the
  user at the start of a session.
- Bundled blank templates for all six context files, the entry point, and a spec file.
