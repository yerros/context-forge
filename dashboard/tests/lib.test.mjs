import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  parseTracker, parseBuildPlan, resolveContextDir, resolveGitCommonDir,
  readClaims, readLocks, readSessions, readFeed, getState,
} from "../src/lib.mjs";

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "fo-"));

/* ---------------- parseTracker -------------------------------------------- */

const TRACKER = `# Progress Tracker

## Current Phase

Phase 3 — media features

## In Progress

- unit 110: gallery lightbox
  attempt 1: [lint] — tried: quick fix — result: broke build
  attempt 2: [lint] — tried: proper types — result: still red

## Next Up

- unit 111: banner scheduling

## Completed

- unit 109: gallery wiring (2026-07-17)
- unit 108: media banner

## Session Notes

- 2026-07-17: shipped PR #121
`;

test("parseTracker: sections, items, attempts, phase", () => {
  const t = parseTracker(TRACKER);
  assert.equal(t.phase, "Phase 3 — media features");
  assert.equal(t.inProgress.length, 1);
  assert.equal(t.inProgress[0].attempts.length, 2);
  assert.deepEqual(t.nextUp, ["unit 111: banner scheduling"]);
  assert.equal(t.completed.length, 2);
  assert.equal(t.notes.length, 1);
});

test("parseTracker: tolerant of empty/corrupt input", () => {
  for (const input of ["", null, undefined, "just prose\nno headings", "## In Progress\n\n(none)\n"]) {
    const t = parseTracker(input);
    assert.deepEqual(t.inProgress, []);
  }
});

test("parseTracker: numbered lists and * bullets work", () => {
  const t = parseTracker("## Next Up\n\n1. unit 5\n* unit 6\n");
  assert.deepEqual(t.nextUp, ["unit 5", "unit 6"]);
});

test("parseTracker: real-world heading aliases (Recently Shipped, Notes, WIP)", () => {
  const t = parseTracker(
    "## WIP\n\n- unit 9\n\n## Recently Shipped\n\n- unit 8\n\n## Notes\n\n- a note\n"
  );
  assert.equal(t.inProgress[0].text, "unit 9");
  assert.deepEqual(t.completed, ["unit 8"]);
  assert.deepEqual(t.notes, ["a note"]);
});

/* ---------------- parseBuildPlan ------------------------------------------- */

test("parseBuildPlan: pending vs completed + unit numbers + complexity", () => {
  const p = parseBuildPlan(
    "## Units\n\n- 04 auth middleware [complexity: high]\n- 05 profile page\n\n## Completed\n\n- 03 login form (2026-07-01)\n"
  );
  assert.equal(p.pending.length, 2);
  assert.equal(p.pending[0].unit, 4);
  assert.equal(p.pending[0].high, true);
  assert.equal(p.pending[1].high, false);
  assert.equal(p.completed.length, 1);
});

/* ---------------- context dir + git common dir ----------------------------- */

test("resolveContextDir mirrors detect.sh precedence", () => {
  const d = tmp();
  assert.equal(resolveContextDir(d), "context");
  fs.mkdirSync(path.join(d, ".forge"));
  assert.equal(resolveContextDir(d), ".forge");
  fs.mkdirSync(path.join(d, "context"));
  fs.writeFileSync(path.join(d, "context", "progress-tracker.md"), "x");
  assert.equal(resolveContextDir(d), "context"); // context has the files, empty .forge loses
  fs.writeFileSync(path.join(d, ".forge", "progress-tracker.md"), "x");
  assert.equal(resolveContextDir(d), ".forge"); // .forge wins when it holds the files
});

test("resolveGitCommonDir: plain repo and linked worktree", () => {
  const repo = tmp();
  fs.mkdirSync(path.join(repo, ".git"));
  assert.equal(resolveGitCommonDir(repo), path.join(repo, ".git"));

  const wt = tmp();
  const wtGitDir = path.join(repo, ".git", "worktrees", "wt1");
  fs.mkdirSync(wtGitDir, { recursive: true });
  fs.writeFileSync(path.join(wt, ".git"), `gitdir: ${wtGitDir}\n`);
  fs.writeFileSync(path.join(wtGitDir, "commondir"), "../..\n");
  assert.equal(resolveGitCommonDir(wt), path.join(repo, ".git"));

  assert.equal(resolveGitCommonDir(tmp()), null); // no git at all
});

/* ---------------- claims, locks, sessions, feed ----------------------------- */

test("readClaims + readLocks parse the plugin's on-disk formats", () => {
  const common = tmp();
  fs.mkdirSync(path.join(common, "forge-claims"));
  fs.writeFileSync(path.join(common, "forge-claims", "07"),
    "unit=07\nbranch=feat/07-x\nworktree=/tmp/x\nclaimed_at=2026-07-18 10:00\n");
  fs.mkdirSync(path.join(common, "forge-locks", "tracker.lock"), { recursive: true });
  fs.writeFileSync(path.join(common, "forge-locks", "tracker.lock", "owner"), "host=h pid=1 user=u at=now\n");

  const claims = readClaims(common);
  assert.equal(claims.length, 1);
  assert.equal(claims[0].unit, "07");
  assert.equal(claims[0].branch, "feat/07-x");

  const locks = readLocks(common);
  assert.equal(locks.length, 1);
  assert.equal(locks[0].name, "tracker");
  assert.match(locks[0].owner, /pid=1/);
  assert.equal(readClaims(null).length, 0);
});

test("readSessions merges skill state and active agents per session", () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, "sess-1"), "active forge-build 1752800000\n");
  fs.writeFileSync(path.join(dir, "sess-1.agents"), "forge-reviewer 1752800100\nforge-tester 1752800200\n");
  const s = readSessions(dir);
  assert.equal(s.length, 1);
  assert.equal(s[0].skill, "forge-build");
  assert.equal(s[0].agents.length, 2);
  assert.equal(s[0].agents[1].agent, "forge-tester");
});

test("readFeed: newest first, corrupt lines skipped, window respected", () => {
  const f = path.join(tmp(), "events.ndjson");
  fs.writeFileSync(f,
    '{"ts":"2026-07-18T10:00:00","event":"a"}\nnot json\n{"ts":"2026-07-18T11:00:00","event":"b"}\n');
  const feed = readFeed(10, f);
  assert.equal(feed.length, 2);
  assert.equal(feed[0].event, "b");
  assert.equal(readFeed(10, path.join(tmp(), "missing.ndjson")).length, 0);
});

/* ---------------- archived units ------------------------------------------- */

test("readArchivedUnits: filenames become completed units, newest first", async () => {
  const { readArchivedUnits } = await import("../src/lib.mjs");
  const ctx = tmp();
  fs.mkdirSync(path.join(ctx, "specs", "archived"), { recursive: true });
  for (const f of ["03-login-form.md", "12-media-banner.md", "notes.txt", "00-build-plan.md"])
    fs.writeFileSync(path.join(ctx, "specs", "archived", f), "x");
  const units = readArchivedUnits(ctx);
  assert.deepEqual(units.map(u => u.unit), [12, 3]);
  assert.equal(units[0].name, "media banner");
  assert.equal(readArchivedUnits(tmp()).length, 0);
});

/* ---------------- getState end-to-end -------------------------------------- */

test("getState assembles a full project snapshot", () => {
  const root = tmp();
  fs.mkdirSync(path.join(root, ".forge", "specs"), { recursive: true });
  fs.writeFileSync(path.join(root, ".forge", "progress-tracker.md"), TRACKER);
  fs.writeFileSync(path.join(root, ".forge", ".schema-version"), "1\n");
  fs.writeFileSync(path.join(root, ".forge", "specs", "00-build-plan.md"), "## Units\n\n- 110 lightbox\n");
  fs.mkdirSync(path.join(root, ".git"));

  const st = getState(root);
  assert.equal(st.contextDir, ".forge");
  assert.equal(st.schema, "1");
  assert.equal(st.tracker.inProgress.length, 1);
  assert.equal(st.plan.pending.length, 1);
  assert.equal(st.project, path.basename(root));
  assert.ok(Array.isArray(st.claims) && Array.isArray(st.locks));
  assert.ok(Array.isArray(st.archivedUnits));
});
