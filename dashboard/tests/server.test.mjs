// Server smoke test: boots the real server against a fixture project and
// exercises /api/state, /api/feed, /events (SSE handshake), and 404s.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(__dirname, "..", "src", "server.mjs");
const PORT = 4899;
const BASE = `http://127.0.0.1:${PORT}`;

let proc;
let root;

before(async () => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "fo-proj-"));
  fs.mkdirSync(path.join(root, "context", "specs"), { recursive: true });
  fs.writeFileSync(path.join(root, "context", "progress-tracker.md"),
    "## In Progress\n\n- unit 01: hello\n\n## Next Up\n\n- unit 02: world\n");
  fs.writeFileSync(path.join(root, "context", "specs", "00-build-plan.md"),
    "## Units\n\n- 02 world\n\n## Completed\n\n- 01 hello\n");

  proc = spawn(process.execPath, [SERVER, root], {
    env: { ...process.env, FORGE_OFFICE_PORT: String(PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });
  // wait until it listens
  for (let i = 0; i < 50; i++) {
    try { await fetch(BASE + "/api/state"); return; } catch { await sleep(100); }
  }
  throw new Error("server did not start");
});

after(() => { proc?.kill(); });

test("GET /api/state returns the parsed project snapshot", async () => {
  const r = await fetch(BASE + "/api/state");
  assert.equal(r.status, 200);
  const s = await r.json();
  assert.equal(s.project, path.basename(root));
  assert.equal(s.tracker.inProgress[0].text, "unit 01: hello");
  assert.equal(s.plan.pending.length, 1);
});

test("GET /api/feed returns an array (empty is fine)", async () => {
  const r = await fetch(BASE + "/api/feed?n=5");
  assert.equal(r.status, 200);
  assert.ok(Array.isArray(await r.json()));
});

test("GET /events performs an SSE handshake", async () => {
  const ctrl = new AbortController();
  const r = await fetch(BASE + "/events", { signal: ctrl.signal });
  assert.equal(r.headers.get("content-type"), "text/event-stream");
  const reader = r.body.getReader();
  const { value } = await reader.read();
  assert.match(new TextDecoder().decode(value), /event: hello/);
  ctrl.abort();
});

test("state updates are visible on re-fetch after a file change", async () => {
  fs.appendFileSync(path.join(root, "context", "progress-tracker.md"), "- unit 03: extra\n");
  const s = await (await fetch(BASE + "/api/state")).json();
  assert.equal(s.tracker.nextUp.length, 2);
});

test("path traversal outside public/ is rejected", async () => {
  const r = await fetch(BASE + "/..%2f..%2fpackage.json");
  assert.equal(r.status, 404);
});

test("GET / serves the UI", async () => {
  const r = await fetch(BASE + "/");
  assert.equal(r.status, 200);
  assert.match(await r.text(), /forge-office/i);
});

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
