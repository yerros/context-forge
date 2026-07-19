// server.mjs — forge-office: local, read-only, zero-dependency dashboard server.
//
//   node src/server.mjs [project-root]        # default: cwd
//   FORGE_OFFICE_PORT=4820                    # default port
//
// Security: binds to 127.0.0.1 ONLY. This is a window into your projects —
// never expose it to the internet; use a private tailnet for remote access.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { getState, getSpec, readFeed, stateSignature } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(__dirname, "..", "public");

const root = path.resolve(process.argv[2] || process.cwd());
const PORT = Number(process.env.FORGE_OFFICE_PORT || 4820);
const HOST = "127.0.0.1";
const STATUS_DIR = path.join(os.homedir(), ".claude", "forge-status");
const METRICS_FILE = path.join(os.homedir(), ".claude", "forge-metrics", "events.ndjson");

if (!fs.existsSync(root)) {
  console.error(`forge-office: project root not found: ${root}`);
  process.exit(1);
}

/* ------------- SSE clients + change poller -------------------------------- */

const clients = new Set();
let lastSig = "";

setInterval(() => {
  let sig;
  try { sig = stateSignature(root, STATUS_DIR, METRICS_FILE); } catch { return; }
  if (sig !== lastSig) {
    lastSig = sig;
    broadcast("update", { at: Date.now() });
  }
}, 1500);

setInterval(() => broadcast("ping", { at: Date.now() }), 25000); // keep-alive

function broadcast(event, data) {
  const frame = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) {
    try { res.write(frame); } catch { clients.delete(res); }
  }
}

/* ------------- http -------------------------------------------------------- */

const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".svg": "image/svg+xml" };

/* ------------- dashboard inbox (chat + assign) ----------------------------
   The ONLY writes forge-office ever makes go to ITS OWN home directory
   (~/.claude/forge-office/inbox/) — never to the project. The plugin's
   UserPromptSubmit hook (office-inbox.sh) drains this file into the next
   Claude Code turn as injected context.                                    */

const INBOX_DIR = path.join(os.homedir(), ".claude", "forge-office", "inbox");
const INBOX_FILE = path.join(INBOX_DIR, path.basename(root) + ".ndjson");

function inboxAppend(entry) {
  fs.mkdirSync(INBOX_DIR, { recursive: true });
  fs.appendFileSync(INBOX_FILE, JSON.stringify(entry) + "\n");
}
function inboxCount() {
  try { return fs.readFileSync(INBOX_FILE, "utf8").split("\n").filter(Boolean).length; }
  catch { return 0; }
}
const clean = (s, max) => String(s ?? "").replace(/[\r\n\t]/g, " ").trim().slice(0, max);

function readBody(req, cb) {
  let body = "";
  req.on("data", (c) => { body += c; if (body.length > 16384) req.destroy(); });
  req.on("end", () => {
    try { cb(JSON.parse(body || "{}")); }
    catch { cb(null); }
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);

  if (req.method === "POST" && (url.pathname === "/api/chat" || url.pathname === "/api/assign")) {
    return readBody(req, (b) => {
      if (!b) { res.writeHead(400, { "Content-Type": "application/json" }); return res.end('{"error":"bad json"}'); }
      const ts = new Date().toISOString().slice(0, 19);
      let entry;
      if (url.pathname === "/api/chat") {
        const message = clean(b.message, 500);
        if (!message) { res.writeHead(400, { "Content-Type": "application/json" }); return res.end('{"error":"empty message"}'); }
        entry = { kind: "chat", ts, to: clean(b.to, 40) || "main session", message };
      } else {
        const unit = Number(b.unit);
        if (!Number.isInteger(unit) || unit <= 0) { res.writeHead(400, { "Content-Type": "application/json" }); return res.end('{"error":"bad unit"}'); }
        entry = { kind: "assign", ts, unit: String(unit), message: clean(b.message, 200) };
      }
      try { inboxAppend(entry); } catch (e) {
        res.writeHead(500, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: String(e && e.message || e) }));
      }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, pending: inboxCount() }));
    });
  }
  if (url.pathname === "/api/inbox") {
    return json(res, () => ({ pending: inboxCount() }));
  }

  if (url.pathname === "/api/state") {
    return json(res, () => getState(root));
  }
  if (url.pathname === "/api/spec") {
    return json(res, () => getSpec(root, url.searchParams.get("unit")) || { error: "not found" });
  }
  if (url.pathname === "/api/feed") {
    const n = Math.min(Number(url.searchParams.get("n")) || 200, 1000);
    return json(res, () => readFeed(n, METRICS_FILE));
  }
  if (url.pathname === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(`event: hello\ndata: {}\n\n`);
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }

  // static
  let file = url.pathname === "/" ? "/index.html" : url.pathname;
  file = path.normalize(file).replace(/^(\.\.[/\\])+/, "");
  const full = path.join(PUBLIC, file);
  if (!full.startsWith(PUBLIC) || !fs.existsSync(full) || !fs.statSync(full).isFile()) {
    res.writeHead(404); return res.end("not found");
  }
  res.writeHead(200, { "Content-Type": MIME[path.extname(full)] || "application/octet-stream" });
  fs.createReadStream(full).pipe(res);
});

function json(res, fn) {
  try {
    const body = JSON.stringify(fn());
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-cache" });
    res.end(body);
  } catch (e) {
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: String(e && e.message || e) }));
  }
}

server.listen(PORT, HOST, () => {
  console.log(`forge-office → http://${HOST}:${PORT}  (project: ${root})`);
  console.log("project-safe: never writes to the project (chat/assign go to ~/.claude/forge-office/inbox)");
});
