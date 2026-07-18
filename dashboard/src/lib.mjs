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
      const agents = safeRead(full).split("\n").filter(Boolean).map((l) => {
        const [agent, epoch] = l.split(/\s+/);
        return { agent, since: Number(epoch) || 0 };
      });
      if (agents.length) merge(sessions, sid).agents = agents;
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
    sessions: readSessions(),
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
  return parts.join("|");
}

/* ---------------- utils ----------------------------------------------------- */

function safeRead(p) { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } }
function ageMinutes(mtimeMs) { return Math.floor((Date.now() - mtimeMs) / 60000); }
