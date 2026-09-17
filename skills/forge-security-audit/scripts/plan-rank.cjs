#!/usr/bin/env node
/**
 * plan-rank.cjs — rank coverage-ledger units into scan targets for `--plan`.
 *
 * Usage: node plan-rank.cjs <coverage-ledger.json> [--hits <security-check.log>] [--repo <dir>] [--json]
 *
 * Groups ledger units by (subsystem, boundary) and scores each group:
 *   tool hits under its starting paths x3  +  files changed in 90 days  +  low-trust boundary x5
 * Prints a ranked table (or JSON with --json). Zero dependencies; git is optional.
 */
"use strict";
const fs = require("node:fs");
const { spawnSync } = require("node:child_process");

function usage(code) {
  console.error("Usage: node plan-rank.cjs <coverage-ledger.json> [--hits <security-check.log>] [--repo <dir>] [--json]");
  return code;
}

function parseArgs(argv) {
  const o = { ledger: null, hits: null, repo: null, json: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--hits") o.hits = argv[++i];
    else if (a === "--repo") o.repo = argv[++i];
    else if (a === "--json") o.json = true;
    else if (!o.ledger && !a.startsWith("--")) o.ledger = a;
    else return null;
  }
  return o.ledger ? o : null;
}

function loadUnits(file) {
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  const units = Array.isArray(data) ? data : Array.isArray(data && data.units) ? data.units : null;
  if (!units) throw new Error("ledger must be a JSON array of units");
  return units;
}

// ponytail: a "tool hit" is any security-check.sh output line that starts with `path:line:`.
function loadHitPaths(file) {
  if (!file) return [];
  return fs.readFileSync(file, "utf8").split("\n")
    .map((l) => (l.match(/^([^\s:]+):\d+:/) || [])[1]).filter(Boolean);
}

function loadChurn(repo) {
  if (!repo) return [];
  const r = spawnSync("git", ["-C", repo, "log", "--since=90.days", "--name-only", "--format="], { encoding: "utf8" });
  if (r.status !== 0) return [];
  return [...new Set(r.stdout.split("\n").map((s) => s.trim()).filter(Boolean))];
}

const under = (file, prefixes) => prefixes.some((p) => file === p || file.startsWith(p.replace(/\/?$/, "/")));
const LOW_TRUST = /unauth|anonym|public|guest|external|untrusted|internet|webhook/i;

function rank(units, hitPaths, churnFiles) {
  const groups = new Map();
  for (const u of units) {
    if (!u || typeof u !== "object") continue;
    if (u.status === "out_of_scope") continue;
    const key = `${u.subsystem || "?"} ${u.boundary || "?"}`;
    let g = groups.get(key);
    if (!g) {
      g = { subsystem: u.subsystem || "?", boundary: u.boundary || "?", units: 0, paths: new Set(), surfaces: new Set(), low_trust: false };
      groups.set(key, g);
    }
    g.units++;
    for (const p of u.starting_paths || []) g.paths.add(p);
    if (u.surface) g.surfaces.add(u.surface);
    if (LOW_TRUST.test(`${u.boundary || ""} ${u.surface || ""}`)) g.low_trust = true;
  }
  const rows = [...groups.values()].map((g) => {
    const paths = [...g.paths];
    const hits = hitPaths.filter((h) => under(h, paths)).length;
    const churn = churnFiles.filter((f) => under(f, paths)).length;
    // ponytail: one hunter per unit + about half a verifier per unit; profile-specific math lives in SKILL.md.
    const est = [g.units, g.units + Math.ceil(g.units / 2)];
    return {
      subsystem: g.subsystem, boundary: g.boundary, units: g.units, surfaces: g.surfaces.size,
      paths, hits, churn, low_trust: g.low_trust,
      est_agents: est, score: hits * 3 + churn + (g.low_trust ? 5 : 0),
    };
  });
  rows.sort((a, b) => b.score - a.score || b.units - a.units || a.subsystem.localeCompare(b.subsystem) || a.boundary.localeCompare(b.boundary));
  return rows;
}

function table(rows) {
  const why = (r) => [r.low_trust && "low-trust surface", r.hits && `${r.hits} tool hit${r.hits > 1 ? "s" : ""}`, r.churn && `${r.churn} files changed 90d`]
    .filter(Boolean).join(", ") || "no signal";
  const out = ["#  | Subsystem / boundary | Units | Est. agents | Why first"];
  rows.forEach((r, i) => out.push(`${String(i + 1).padStart(2)} | ${r.subsystem} / ${r.boundary} | ${r.units} | ${r.est_agents[0]}-${r.est_agents[1]} | ${why(r)}`));
  const total = rows.reduce((s, r) => s + r.units, 0);
  out.push(`total: ${rows.length} targets, ${total} units, ~${total}-${total + Math.ceil(total / 2)} agents for everything`);
  return out.join("\n");
}

function run(argv) {
  const o = parseArgs(argv);
  if (!o) return usage(2);
  let rows;
  try {
    rows = rank(loadUnits(o.ledger), loadHitPaths(o.hits), loadChurn(o.repo));
  } catch (e) {
    console.error(`plan-rank: ${e.message}`);
    return 1;
  }
  console.log(o.json ? JSON.stringify(rows, null, 2) : table(rows));
  return 0;
}

module.exports = { rank, table, parseArgs };
if (require.main === module) process.exit(run(process.argv.slice(2)));
