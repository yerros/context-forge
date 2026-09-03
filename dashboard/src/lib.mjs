// lib.mjs — pure readers for Context Forge project state.
// Everything here is read-only: forge-office NEVER writes to a project.
// Writers must go through the plugin's own scripts (forge-lock.sh etc.).

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

/* ---------------- context dir (same rule as the plugin's detect.sh) ------- */

export function resolveContextDir(root) {
  const has = (p) => fs.existsSync(path.join(root, p));
  if (has(".forge/progress-tracker.md") || has(".forge/project-overview.md")) return ".forge";
  if (has("context/progress-tracker.md") || has("context/project-overview.md")) return "context";
  if (has(".forge")) return ".forge";
  return "context";
}

/* ---------------- git common dir (worktree-aware, no exec) ---------------- */

export function resolveGitCommonDir(root) {
  const dotGit = path.join(root, ".git");
  let st;
  try { st = fs.statSync(dotGit); } catch { return null; }
  let gitDir = dotGit;
  if (st.isFile()) {
    // linked worktree: ".git" is a file "gitdir: <path>"
    const m = fs.readFileSync(dotGit, "utf8").match(/^gitdir:\s*(.+)\s*$/m);
    if (!m) return null;
    gitDir = path.resolve(root, m[1].trim());
  }
  // a linked worktree's gitdir contains a "commondir" pointer to the shared .git
  const commonPtr = path.join(gitDir, "commondir");
  if (fs.existsSync(commonPtr)) {
    return path.resolve(gitDir, fs.readFileSync(commonPtr, "utf8").trim());
  }
  return gitDir;
}

/* ---------------- tracker parsing (tolerant markdown) --------------------- */

// Real-world trackers drift in wording — match the intent, not one spelling.
const SECTION_MAP = [
  [/in\s*progress|\bwip\b/i, "inProgress"],
  [/next\s*up|up\s*next|\bbacklog\b/i, "nextUp"],
  [/completed|recently\s*shipped|\bshipped\b|\bdone\b/i, "completed"],
  [/session\s*notes?|^notes?\b/i, "notes"],
  [/open\s*questions?/i, "openQuestions"],
];

export function parseTracker(md) {
  const out = { phase: "", inProgress: [], nextUp: [], completed: [], notes: [], openQuestions: [] };
  if (!md || typeof md !== "string") return out;

  const phase = md.match(/^#{2,3}\s*current\s*phase[^\n]*\n+([^\n#]+)/im)
    || md.match(/^[-*]?\s*\*{0,2}current\s*phase\*{0,2}\s*[:—-]\s*(.+)$/im);
  if (phase) out.phase = phase[1].trim();

  let bucket = null;
  for (const raw of md.split("\n")) {
    const line = raw.replace(/\r$/, "");
    const h = line.match(/^#{2,4}\s+(.+)$/);
    if (h) {
      bucket = null;
      for (const [re, key] of SECTION_MAP) if (re.test(h[1])) { bucket = key; break; }
      continue;
    }
    if (!bucket) continue;

    const attempt = line.match(/^\s+attempt\s+(\d+)\s*:\s*(.+)$/i);
    if (attempt && bucket === "inProgress" && out.inProgress.length) {
      out.inProgress[out.inProgress.length - 1].attempts.push(attempt[2].trim());
      continue;
    }
    const item = line.match(/^\s*(?:[-*]|\d+[.)])\s+(.+)$/);
    if (!item) continue;
    const text = item[1].trim();
    if (!text || /^\(none\)/i.test(text)) continue;
    if (bucket === "inProgress") out.inProgress.push({ text, attempts: [] });
    else out[bucket].push(text);
  }
  // Real trackers often carry the live unit in the Current Phase line itself
  // ("**In Progress: Unit 111** — …") instead of a bullet under a section.
  if (!out.inProgress.length && /in\s*progress\s*[:—-]/i.test(out.phase)) {
    const text = out.phase.replace(/^\**\s*in\s*progress\s*[:—-]\s*/i, "").replace(/\*\*/g, "").trim();
    if (text) out.inProgress.push({ text, attempts: [] });
  }
  return out;
}

/* ---------------- build plan ---------------------------------------------- */

export function parseBuildPlan(md) {
  const out = { pending: [], completed: [] };
  if (!md) return out;
  let bucket = "pending";
  for (const line of md.split("\n")) {
    const h = line.match(/^#{2,3}\s+(.+)$/);
    if (h) { bucket = /completed/i.test(h[1]) ? "completed" : "pending"; continue; }
    const item = line.match(/^\s*(?:[-*]|\d+[.)])\s+(.+)$/);
    if (item) {
      const text = item[1].trim();
      const unit = text.match(/(?:unit\s*)?0*(\d{1,3})\b/i);
      const complexity = /\[complexity:\s*high\]/i.test(text);
      out[bucket].push({ text, unit: unit ? Number(unit[1]) : null, high: complexity });
    }
  }
  return out;
}

/* ---------------- claims & locks ------------------------------------------ */

function parseKv(content) {
  const obj = {};
  for (const line of content.split("\n")) {
    const m = line.match(/^([A-Za-z_]+)=(.*)$/);
    if (m) obj[m[1]] = m[2];
  }
  return obj;
}

export function readClaims(commonDir) {
  const dir = commonDir && path.join(commonDir, "forge-claims");
  if (!dir || !fs.existsSync(dir)) return [];
  const claims = [];
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (!st.isFile()) continue;
    claims.push({ unit: f, ageMin: ageMinutes(st.mtimeMs), ...parseKv(safeRead(full)) });
  }
  return claims.sort((a, b) => a.unit.localeCompare(b.unit));
}

export function readLocks(commonDir) {
  const dir = commonDir && path.join(commonDir, "forge-locks");
  if (!dir || !fs.existsSync(dir)) return [];
  const locks = [];
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith(".lock")) continue;
    const full = path.join(dir, f);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (!st.isDirectory()) continue;
    locks.push({
      name: f.replace(/\.lock$/, ""),
      ageMin: ageMinutes(st.mtimeMs),
      stale: ageMinutes(st.mtimeMs) >= 15,
      owner: safeRead(path.join(full, "owner")).trim(),
    });
  }
  return locks;
}

/* ---------------- live session state (skill + agents) --------------------- */

export function readSessions(statusDir = path.join(os.homedir(), ".claude", "forge-status")) {
  const sessions = [];
  if (!fs.existsSync(statusDir)) return sessions;
  for (const f of fs.readdirSync(statusDir)) {
    const full = path.join(statusDir, f);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (!st.isFile()) continue;
    if (f.endsWith(".agents")) {
      const sid = f.replace(/\.agents$/, "");
      // TTL guard: never render entries older than 2 h — same safety net as
      // the recorder's prune, but applied at read time so a stale file from a
      // dead session (which no hook will ever touch again) can't show ghosts.
      const now = Date.now() / 1000;
      const agents = safeRead(full).split("\n").filter(Boolean).map((l) => {
        const [agent, epoch, mark] = l.split(/\s+/);
        return { agent, since: Number(epoch) || 0, bg: !!(mark && mark.startsWith("B")) };
      // background agents expire after 20 min (their completion signal is not
      // reliably delivered), foreground after the 2 h safety net
      }).filter((a) => a.since > 0 && now - a.since < (a.bg ? 1200 : 7200));
      if (agents.length) merge(sessions, sid).agents = agents;
    } else if (f.endsWith(".now")) {
      // "<epoch>\t<tool>\t<detail>" — what the session is doing right now.
      const sid = f.replace(/\.now$/, "");
      const [epoch, tool, detail] = safeRead(full).trim().split("\t");
      if (tool) merge(sessions, sid).now = { tool, detail: detail || "", since: Number(epoch) || 0 };
    } else if (f.endsWith(".wait")) {
      // "<waiting|permission> <epoch>" — the session is blocked on the user.
      const sid = f.replace(/\.wait$/, "");
      const [state, epoch] = safeRead(full).trim().split(/\s+/);
      const since = Number(epoch) || 0;
      if (/^(waiting|permission)$/.test(state) && Date.now() / 1000 - since < 7200)
        merge(sessions, sid).wait = { state, since };
    } else if (f.endsWith(".stream")) {
      // rolling per-session tool log — the dashboard's realtime work timeline.
      const sid = f.replace(/\.stream$/, "");
      const now = Date.now() / 1000;
      const events = safeRead(full).split("\n").filter(Boolean).map((l) => {
        const [epoch, tool, detail] = l.split("\t");
        return { ts: Number(epoch) || 0, tool, detail: detail || "" };
      }).filter((e) => e.tool && e.ts > now - 7200);
      if (events.length) merge(sessions, sid).stream = events.slice(-40);
    } else {
      const [state, skill, epoch] = safeRead(full).trim().split(/\s+/);
      if (state && skill) Object.assign(merge(sessions, f), { skillState: state, skill, skillSince: Number(epoch) || 0 });
    }
  }
  return sessions;

  function merge(list, sid) {
    let s = list.find((x) => x.session === sid);
    if (!s) { s = { session: sid, agents: [] }; list.push(s); }
    return s;
  }
}

/* ---------------- subagent transcripts (per-agent live activity) ---------- */
// Claude Code writes every subagent's own transcript to
//   ~/.claude/projects/<project-dir>/<session_id>/subagents/agent-<id>.jsonl
// plus agent-<id>.meta.json {agentType, description, toolUseId}. The hooks
// only see the MAIN session's tools, so this is the only source for "what is
// forge-reviewer doing right now". Read-only; unofficial format — every
// parse failure degrades to "no detail", never to an error.

// Same rule Claude Code uses for the project directory name.
export const projectDirName = (root) => String(root).replace(/[^a-zA-Z0-9-]/g, "-");

const SUB_TAIL_BYTES = 64 * 1024;   // only the recent tail of a transcript matters
const SUB_TTL_S = 7200;

// Human detail for a tool call — mirrors now-status.sh (first matching key).
function toolDetail(input) {
  if (!input || typeof input !== "object") return "";
  let v = "";
  for (const k of ["file_path", "notebook_path", "path", "pattern", "skill", "subagent_type", "url", "command", "description", "prompt", "query"]) {
    if (typeof input[k] === "string" && input[k]) { v = input[k]; break; }
  }
  v = v.replace(/[\t\n]/g, " ");
  // shorten deep PATHS to their tail; commands (contain spaces) stay intact
  if (!/\s/.test(v) && (v.match(/\//g) || []).length >= 3) v = "…/" + v.slice(v.lastIndexOf("/") + 1);
  return v.slice(0, 90);
}

function tailRead(file, bytes) {
  let fd;
  try {
    const size = fs.statSync(file).size;
    const start = Math.max(0, size - bytes);
    fd = fs.openSync(file, "r");
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    let text = buf.toString("utf8");
    if (start > 0) text = text.slice(text.indexOf("\n") + 1);   // drop the cut first line
    return text;
  } catch { return ""; }
  finally { if (fd !== undefined) fs.closeSync(fd); }
}

// Parse one subagent transcript tail into a compact activity record.
export function parseSubagentTranscript(text) {
  const out = { model: "", since: 0, last: 0, done: false, tool: null, detail: "", stream: [] };
  const open = new Map();   // tool_use id -> stream event (awaiting its result)
  for (const line of String(text).split("\n")) {
    if (!line) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    const ts = Math.floor(Date.parse(r.timestamp || "") / 1000) || 0;
    if (ts) { if (!out.since) out.since = ts; out.last = ts; }
    const m = r.message;
    const content = m && Array.isArray(m.content) ? m.content : [];
    if (r.type === "assistant") {
      if (m && m.model) out.model = m.model;
      for (const c of content) {
        if (c.type === "tool_use") {
          const ev = { ts, tool: String(c.name || ""), detail: toolDetail(c.input) };
          out.stream.push(ev);
          if (c.id) open.set(c.id, ev);
          out.done = false;
        } else if (c.type === "text" && c.text) {
          out.done = true;   // a final text answer = the agent finished its turn
        }
      }
    } else if (r.type === "user") {
      for (const c of content) if (c.type === "tool_result" && c.tool_use_id) open.delete(c.tool_use_id);
    }
  }
  // current tool = the newest tool_use without a result yet
  const pending = [...open.values()];
  if (pending.length && !out.done) { const cur = pending[pending.length - 1]; out.tool = cur.tool; out.detail = cur.detail; }
  out.stream = out.stream.slice(-20);
  return out;
}

export function readSubagents(root, projectsDir = path.join(os.homedir(), ".claude", "projects")) {
  const projDir = path.join(projectsDir, projectDirName(root));
  const bySession = {};
  let sessions;
  try { sessions = fs.readdirSync(projDir); } catch { return bySession; }
  const now = Date.now() / 1000;
  for (const sid of sessions) {
    const dir = path.join(projDir, sid, "subagents");
    let files;
    try { files = fs.readdirSync(dir); } catch { continue; }
    for (const f of files) {
      const m = f.match(/^agent-([A-Za-z0-9]+)\.jsonl$/);
      if (!m) continue;
      const jsonl = path.join(dir, f);
      let st; try { st = fs.statSync(jsonl); } catch { continue; }
      if (now - st.mtimeMs / 1000 > SUB_TTL_S) continue;   // long-dead subagent
      let meta = {};
      try { meta = JSON.parse(safeRead(path.join(dir, `agent-${m[1]}.meta.json`))); } catch { /* optional */ }
      const rec = parseSubagentTranscript(tailRead(jsonl, SUB_TAIL_BYTES));
      (bySession[sid] ||= []).push({
        id: m[1],
        agentType: String(meta.agentType || "").replace(/^.*:/, "") || "unknown",
        description: String(meta.description || "").slice(0, 120),
        toolUseId: meta.toolUseId || "",
        ...rec,
        mtime: Math.floor(st.mtimeMs / 1000),
      });
    }
    if (bySession[sid]) bySession[sid].sort((a, b) => a.since - b.since);
  }
  return bySession;
}

/* ---------------- metrics feed --------------------------------------------- */

export function readFeed(n = 200, file = path.join(os.homedir(), ".claude", "forge-metrics", "events.ndjson")) {
  if (!fs.existsSync(file)) return [];
  const lines = safeRead(file).trim().split("\n");
  const events = [];
  for (const line of lines.slice(-n)) {
    try { events.push(JSON.parse(line)); } catch { /* skip corrupt line */ }
  }
  return events.reverse(); // newest first
}

/* ---------------- archived specs = ground truth for "done" ----------------- */
// The plugin's close-unit procedure moves a finished unit's spec into
// specs/archived/ — filenames are therefore a reliable completed-units source
// even when the tracker's Completed section is prose or rotated away.
function readSpecDir(dir) {
  if (!fs.existsSync(dir)) return [];
  const units = [];
  for (const f of fs.readdirSync(dir)) {
    const m = f.match(/^0*(\d{1,3})-(.+)\.md$/);
    if (m && Number(m[1]) > 0) {  // unit 00 = the build plan, not a unit
      let mtime = 0;
      try { mtime = fs.statSync(path.join(dir, f)).mtimeMs; } catch { /* raced */ }
      units.push({ unit: Number(m[1]), name: m[2].replace(/-/g, " "), file: f, mtime });
    }
  }
  return units;
}

// Full spec content for the card drawer — active spec first, then archived.
export function getSpec(root, unit) {
  const n = Number(unit);
  if (!Number.isInteger(n) || n <= 0) return null;
  const ctxDir = path.join(root, resolveContextDir(root));
  for (const [dir, archived] of [
    [path.join(ctxDir, "specs"), false],
    [path.join(ctxDir, "specs", "archived"), true],
  ]) {
    const hit = readSpecDir(dir).find((u) => u.unit === n);
    if (hit) return { unit: n, name: hit.name, archived, content: safeRead(path.join(dir, hit.file)) };
  }
  return null;
}

// origin remote -> https link base (for branch/PR links on cards).
export function repoUrl(commonDir) {
  if (!commonDir) return null;
  const cfg = safeRead(path.join(commonDir, "config"));
  const m = cfg.match(/\[remote "origin"\][^[]*?url\s*=\s*(\S+)/);
  if (!m) return null;
  let u = m[1].replace(/\.git$/, "");
  const ssh = u.match(/^(?:ssh:\/\/)?git@([^:/]+)[:/](.+)$/);
  if (ssh) u = `https://${ssh[1]}/${ssh[2]}`;
  return /^https?:\/\//.test(u) ? u : null;
}

export function readArchivedUnits(ctxDir) {
  return readSpecDir(path.join(ctxDir, "specs", "archived")).sort((a, b) => b.unit - a.unit);
}

// Specs still in specs/ (not archived) = planned or in-flight units — the
// truthful "Next Up" source even before the build plan mentions them.
export function readActiveSpecs(ctxDir) {
  return readSpecDir(path.join(ctxDir, "specs")).sort((a, b) => a.unit - b.unit);
}

// Join transcript activity onto the hook-recorded agent list. Match is by
// agent type, oldest-first on both sides (two forge-reviewers = two entries).
// Hook entries stay authoritative for presence; transcripts only add detail.
// Transcript-only agents (hook signal missed) are appended as `fromTranscript`.
export function attachSubagents(sessions, bySession) {
  for (const [sid, subs] of Object.entries(bySession)) {
    let s = sessions.find((x) => x.session === sid);
    const now = Date.now() / 1000;
    // ponytail: a transcript with no final text but no activity for 20 min is
    // a crashed/killed agent, not a live one — same TTL as background entries.
    const live = subs.filter((x) => !x.done && now - x.last < 1200);
    if (!s) {
      if (!live.length) continue;
      s = { session: sid, agents: [] }; sessions.push(s);
    }
    const pool = new Map();
    for (const x of live) (pool.get(x.agentType) || pool.set(x.agentType, []).get(x.agentType)).push(x);
    for (const a of s.agents) {
      const q = pool.get(a.agent);
      const x = q && q.shift();
      if (x) Object.assign(a, { tool: x.tool, detail: x.detail, description: x.description, model: x.model, stream: x.stream, last: x.last });
    }
    for (const q of pool.values()) for (const x of q)
      s.agents.push({ agent: x.agentType, since: x.since, bg: false, fromTranscript: true,
        tool: x.tool, detail: x.detail, description: x.description, model: x.model, stream: x.stream, last: x.last });
  }
  return sessions;
}

/* ---------------- whole-project state -------------------------------------- */

export function getState(root) {
  const ctx = resolveContextDir(root);
  const ctxDir = path.join(root, ctx);
  const common = resolveGitCommonDir(root);
  const tracker = parseTracker(safeRead(path.join(ctxDir, "progress-tracker.md")));
  const plan = parseBuildPlan(safeRead(path.join(ctxDir, "specs", "00-build-plan.md")));
  return {
    project: path.basename(root),
    root,
    contextDir: ctx,
    schema: safeRead(path.join(ctxDir, ".schema-version")).trim() || "pre-schema",
    digestPresent: fs.existsSync(path.join(ctxDir, "context-digest.md")),
    tracker,
    plan,
    archivedUnits: readArchivedUnits(ctxDir),
    activeSpecs: readActiveSpecs(ctxDir),
    claims: readClaims(common),
    locks: readLocks(common),
    sessions: attachSubagents(readSessions(), readSubagents(root)),
    repoUrl: repoUrl(common),
    lastSession: safeRead(path.join(ctxDir, ".last-session.md")),
    generatedAt: new Date().toISOString(),
  };
}

/* ---------------- change signature (cheap polling) ------------------------- */

export function stateSignature(root, statusDir, metricsFile) {
  const parts = [];
  const ctxDir = path.join(root, resolveContextDir(root));
  const common = resolveGitCommonDir(root);
  const add = (p) => { try { const s = fs.statSync(p); parts.push(p + ":" + s.mtimeMs + ":" + s.size); } catch { /* absent */ } };
  add(path.join(ctxDir, "progress-tracker.md"));
  add(path.join(ctxDir, "specs", "00-build-plan.md"));
  add(path.join(ctxDir, "progress-archive.md"));
  add(path.join(ctxDir, ".last-session.md"));
  const archDir = path.join(ctxDir, "specs", "archived");
  if (fs.existsSync(archDir)) parts.push("arch:" + fs.readdirSync(archDir).join(","));
  const specDir = path.join(ctxDir, "specs");
  if (fs.existsSync(specDir)) parts.push("specs:" + fs.readdirSync(specDir).join(","));
  for (const sub of ["forge-claims", "forge-locks"]) {
    const d = common && path.join(common, sub);
    if (d && fs.existsSync(d)) for (const f of fs.readdirSync(d)) add(path.join(d, f));
  }
  if (fs.existsSync(statusDir)) for (const f of fs.readdirSync(statusDir)) add(path.join(statusDir, f));
  add(metricsFile);
  // subagent transcripts: only the recent ones (readSubagents skips the rest)
  const projDir = path.join(os.homedir(), ".claude", "projects", projectDirName(root));
  let sids = []; try { sids = fs.readdirSync(projDir); } catch { /* no transcripts yet */ }
  const cutoff = Date.now() - SUB_TTL_S * 1000;
  for (const sid of sids) {
    const d = path.join(projDir, sid, "subagents");
    let files = []; try { files = fs.readdirSync(d); } catch { continue; }
    for (const f of files) if (f.endsWith(".jsonl")) {
      try { const s = fs.statSync(path.join(d, f)); if (s.mtimeMs > cutoff) parts.push(f + ":" + s.mtimeMs + ":" + s.size); } catch { /* raced */ }
    }
  }
  return parts.join("|");
}

/* ---------------- utils ----------------------------------------------------- */

function safeRead(p) { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } }
function ageMinutes(mtimeMs) { return Math.floor((Date.now() - mtimeMs) / 60000); }
