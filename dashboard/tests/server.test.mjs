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
let fakeHome;

before(async () => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "fo-proj-"));
  fs.mkdirSync(path.join(root, "context", "specs"), { recursive: true });
  fs.writeFileSync(path.join(root, "context", "progress-tracker.md"),
    "## In Progress\n\n- unit 01: hello\n\n## Next Up\n\n- unit 02: world\n");
  fs.writeFileSync(path.join(root, "context", "specs", "00-build-plan.md"),
    "## Units\n\n- 02 world\n\n## Completed\n\n- 01 hello\n");

  // Isolated HOME so inbox writes (chat/assign) never touch the real ~/.claude.
  fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), "fo-home-"));
  proc = spawn(process.execPath, [SERVER, root], {
    env: { ...process.env, FORGE_OFFICE_PORT: String(PORT), HOME: fakeHome, USERPROFILE: fakeHome },
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

test("GET /api/spec serves a unit's spec content", async () => {
  fs.writeFileSync(path.join(root, "context", "specs", "01-hello.md"), "# Spec 01\ncontent");
  const s = await (await fetch(BASE + "/api/spec?unit=1")).json();
  assert.equal(s.unit, 1);
  assert.match(s.content, /Spec 01/);
  const miss = await (await fetch(BASE + "/api/spec?unit=42")).json();
  assert.equal(miss.error, "not found");
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

test("POST /api/chat appends to the home-dir inbox (never the project)", async () => {
  const r = await fetch(BASE + "/api/chat", { method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ to: "forge-reviewer", message: "please re-check unit 2" }) });
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.ok, true);
  assert.ok(body.pending >= 1);
  const inbox = path.join(fakeHome, ".claude", "forge-office", "inbox",
    path.basename(root) + ".ndjson");
  const lines = fs.readFileSync(inbox, "utf8").trim().split("\n").map(JSON.parse);
  const chat = lines.find((l) => l.kind === "chat");
  assert.equal(chat.to, "forge-reviewer");
  assert.equal(chat.message, "please re-check unit 2");
  // and the project itself stays untouched
  assert.ok(!fs.existsSync(path.join(root, ".claude")));
});

test("POST /api/assign queues a unit; bad input rejected", async () => {
  const ok = await (await fetch(BASE + "/api/assign", { method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ unit: 2 }) })).json();
  assert.equal(ok.ok, true);
  const bad = await fetch(BASE + "/api/assign", { method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ unit: "nope" }) });
  assert.equal(bad.status, 400);
  const empty = await fetch(BASE + "/api/chat", { method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "   " }) });
  assert.equal(empty.status, 400);
});

test("GET /api/inbox reports the pending count", async () => {
  const r = await (await fetch(BASE + "/api/inbox")).json();
  assert.ok(r.pending >= 2);
});

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
