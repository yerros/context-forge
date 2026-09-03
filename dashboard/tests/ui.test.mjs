// UI smoke test: run the page's inline script headlessly (stub DOM + canvas)
// and verify the render pipeline and the office animation execute cleanly.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(__dirname, "..", "public", "index.html"), "utf8");
const script = html.match(/<script>([\s\S]*)<\/script>/)[1];

function makeCtx(ops) {
  return new Proxy({}, {
    get(_, prop) {
      if (prop === "canvas") return {};
      return (...args) => { ops.push(String(prop)); return undefined; };
    },
    set() { return true; },
  });
}

function makeEl(ops) {
  return {
    classList: { add() {}, remove() {} },
    style: {},
    set innerHTML(v) {}, get innerHTML() { return ""; },
    set textContent(v) {}, get textContent() { return ""; },
    getContext: () => makeCtx(ops),
    addEventListener() {}, focus() {},
    value: "", selectedOptions: [{ text: "" }],
    width: 960, height: 680,
  };
}

// Minimal Image stub so the sprite atlas constructs
// cleanly; onload never fires here, so the render stays on the procedural path.
class ImageStub {
  set src(_v) {}
  set onload(_f) {}
}

const SAMPLE_STATE = {
  project: "demo", contextDir: ".forge", schema: "1", generatedAt: new Date().toISOString(),
  tracker: {
    phase: "Phase X",
    inProgress: [{ text: "unit 12: thing", attempts: ["a1", "a2"] }],
    nextUp: ["unit 13: next"], completed: ["unit 11: done"], notes: ["note"], openQuestions: [],
  },
  plan: { pending: [{ text: "13 next", unit: 13, high: true }], completed: [] },
  archivedUnits: [{ unit: 11, name: "done thing" }],
  activeSpecs: [{ unit: 12, name: "thing" }, { unit: 13, name: "next" }],
  repoUrl: "https://github.com/x/y",
  claims: [{ unit: "12", mode: "build" }], locks: [{ name: "tracker", ageMin: 2, stale: false }],
  sessions: [
    { session: "s1", skillState: "active", skill: "forge-build",
      wait: { state: "permission", since: Math.floor(Date.now() / 1000) - 5 },
      agents: [{ agent: "forge-reviewer", since: 1, tool: "Read", detail: "…/auth.ts" },
               { agent: "forge-tester", since: 2, tool: "Bash", detail: "npm test" },
               { agent: "forge-typer", since: 3, description: "types lens" },
               { agent: "silent-failure-hunter", since: 4, tool: "Grep", detail: "catch" }] },
  ],
};
const SAMPLE_FEED = [{ ts: "2026-07-18T10:00:00", event: "skill_invoked", project: "demo", skill: "forge-build" }];

test("inline UI script runs headlessly: refresh + 30 animation frames, no errors", async () => {
  const ops = [];
  const frames = [];
  const ctxGlobal = {
    document: {
      getElementById: () => makeEl(ops),
      addEventListener: () => {},
      // real-browser-like div used by esc(): innerHTML returns escaped text
      createElement: () => { let t = ""; return {
        set textContent(v) { t = String(v); }, get textContent() { return t; },
        get innerHTML() { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); },
        set innerHTML(_) {}, classList: { add(){}, remove(){} }, style: {},
      }; },
    },
    fetch: async (url) => ({
      json: async () => (String(url).includes("feed") ? SAMPLE_FEED : SAMPLE_STATE),
    }),
    EventSource: class { constructor(){} addEventListener(){} set onopen(v){ v && v(); } set onerror(_){} },
    requestAnimationFrame: (cb) => { frames.push(cb); },
    setInterval: () => 0,
    console,
    location: { search: "" },
    URLSearchParams,
    Image: ImageStub,
    Math, Date, JSON, Object, Array, String, Number, Promise, URL,
  };
  ctxGlobal.window = ctxGlobal;
  vm.createContext(ctxGlobal);
  vm.runInContext(script, ctxGlobal, { filename: "index.inline.js" });

  // let refresh() resolve (fetch stubs)
  await new Promise((r) => setTimeout(r, 20));

  // drive the animation: each frame re-registers the next via requestAnimationFrame
  let t = 0;
  for (let i = 0; i < 30; i++) {
    const cb = frames.shift();
    assert.ok(cb, "animation frame should be scheduled");
    t += 120;
    cb(t);
  }

  // the scene actually drew: thousands of fillRect/fill/stroke calls recorded
  const draws = ops.filter((o) => ["fillRect", "fill", "stroke", "fillText"].includes(o)).length;
  assert.ok(draws > 2000, `expected heavy canvas activity, got ${draws}`);

  // ---- formatToolStatus: shared human vocabulary for tool activity ----
  const fts = ctxGlobal.formatToolStatus;
  assert.equal(fts("Read", "/a/b/auth.ts"), "Reading auth.ts");
  assert.equal(fts("Bash", "npm test"), "Running: npm test");
  assert.equal(fts("Grep", "foo"), "Searching code");
  assert.equal(fts("Agent", "review diff"), "Subtask: review diff");
  assert.equal(fts("Skill", "context-forge:forge-build"), "Skill forge-build");
  assert.equal(fts("Weird", ""), "Using Weird");

  // ---- renderMd: the spec drawer's markdown preview ----
  const md = ctxGlobal.renderMd([
    "# Unit 7: title",
    "",
    "## Goal",
    "Make **bold** work with `inline code` and [a link](https://x.dev/d).",
    "",
    "- [ ] unchecked item",
    "- [x] done item",
    "1. ordered",
    "",
    "| col A | col B |",
    "| ----- | ----- |",
    "| 1     | 2     |",
    "",
    "```",
    "const x = '<script>alert(1)</script>';",
    "```",
    "",
    "> a quote",
    "<img src=x onerror=alert(1)>",
  ].join("\n"));
  assert.match(md, /<h1>Unit 7: title<\/h1>/);
  assert.match(md, /<h2>Goal<\/h2>/);
  assert.match(md, /<b>bold<\/b>/);
  assert.match(md, /<code>inline code<\/code>/);
  assert.match(md, /<a href="https:\/\/x.dev\/d" target="_blank">a link<\/a>/);
  assert.match(md, /checkbox" disabled/);
  assert.match(md, /checkbox" checked disabled/);
  assert.match(md, /<ol><li>ordered<\/li><\/ol>/);
  assert.match(md, /<th>col A<\/th>/);
  assert.match(md, /<td>1<\/td>/);
  assert.match(md, /<blockquote>a quote<\/blockquote>/);
  assert.ok(!md.includes("<script>"), "raw html must be escaped");
  assert.ok(!md.includes("<img"), "raw html must be escaped");
});

test("sprite atlas loaded: agents blit via drawImage", async () => {
  const ops = [];
  const frames = [];
  // an Image whose onload fires immediately, so the sprite path goes live
  class LiveImage {
    set src(_v) {}
    set onload(f) { this._f = f; queueMicrotask(() => f && f()); }
  }
  const ctxGlobal = {
    document: {
      getElementById: () => makeEl(ops),
      addEventListener: () => {},
      createElement: () => ({ set textContent(_v){}, get textContent(){return "";},
        get innerHTML(){return "";}, set innerHTML(_){}, classList:{add(){},remove(){}}, style:{} }),
    },
    fetch: async (url) => ({ json: async () => (String(url).includes("feed") ? SAMPLE_FEED : SAMPLE_STATE) }),
    EventSource: class { addEventListener(){} set onopen(v){ v && v(); } set onerror(_){} },
    requestAnimationFrame: (cb) => { frames.push(cb); },
    setInterval: () => 0,
    console,
    location: { search: "" },
    URLSearchParams, Image: LiveImage,
    queueMicrotask,
    Math, Date, JSON, Object, Array, String, Number, Promise, URL,
  };
  ctxGlobal.window = ctxGlobal;
  vm.createContext(ctxGlobal);
  vm.runInContext(script, ctxGlobal, { filename: "index.inline.js" });
  await new Promise((r) => setTimeout(r, 20));   // let atlas onload + refresh settle

  let t = 0;
  for (let i = 0; i < 30; i++) { const cb = frames.shift(); assert.ok(cb); t += 120; cb(t); }

  // sprite path is exercised: agents drawn with drawImage, no procedural error
  assert.ok(ops.includes("drawImage"), "forge agents should blit from the atlas");
});

// Movement soak: drive the office for ~25 simulated seconds and check the
// three things people notice — working agents reach their seats, nobody
// stands on top of someone else, nobody freezes mid-walk (the one-cell
// corridor shove-fight). Cheap canvas stub: ops are not recorded.
test("office soak: workers get seated, no standing overlap, no stuck walkers", async () => {
  const frames = [];
  const noopCtx = new Proxy({}, { get: (_, p) => p === "canvas" ? {} : () => {}, set: () => true });
  const el = () => ({ ...makeEl([]), getContext: () => noopCtx });
  class LiveImage { set src(_v) {} set onload(f) { queueMicrotask(() => f && f()); } }
  const ctxGlobal = {
    document: { getElementById: el, addEventListener() {}, createElement: () => ({ set textContent(_v){}, get textContent(){return "";}, get innerHTML(){return "";}, set innerHTML(_){}, classList:{add(){},remove(){}}, style:{} }) },
    fetch: async (url) => ({ json: async () => (String(url).includes("feed") ? SAMPLE_FEED : SAMPLE_STATE) }),
    EventSource: class { addEventListener(){} set onopen(v){ v && v(); } set onerror(_){} },
    requestAnimationFrame: (cb) => { frames.push(cb); },
    setInterval: () => 0, console, location: { search: "" }, URLSearchParams, Image: LiveImage, queueMicrotask,
    Math, Date, JSON, Object, Array, String, Number, Promise, URL,
  };
  ctxGlobal.window = ctxGlobal;
  vm.createContext(ctxGlobal);
  vm.runInContext(script, ctxGlobal, { filename: "index.inline.js" });
  await new Promise((r) => setTimeout(r, 20));

  const office = vm.runInContext("office", ctxGlobal);   // const in the script, not a global
  const bodies = () => office._bodies();
  const stuckRun = new Map(); let maxStuck = 0, overlapFrames = 0;
  const prev = new Map();
  let t = 0;
  for (let i = 0; i < 1500; i++) {
    const cb = frames.shift(); assert.ok(cb, "frame scheduled"); t += 16; cb(t);
    if (i < 300) continue;                       // settle-in
    const bs = bodies();
    const standing = (b) => !b.seat && b.path.length === 0 && Math.hypot(b.tx-b.x, b.ty-b.y) <= 2;
    for (let a = 0; a < bs.length; a++) for (let c = a+1; c < bs.length; c++)
      if (standing(bs[a]) && standing(bs[c]) && Math.hypot(bs[a].x-bs[c].x, bs[a].y-bs[c].y) < 8) overlapFrames++;
    for (const b of bs) {
      const p = prev.get(b.id), far = Math.hypot(b.tx-b.x, b.ty-b.y) > 6;
      const run = p && far && Math.hypot(p[0]-b.x, p[1]-b.y) < 0.3 ? (stuckRun.get(b.id) || 0) + 1 : 0;
      stuckRun.set(b.id, run); maxStuck = Math.max(maxStuck, run);
      prev.set(b.id, [b.x, b.y]);
    }
  }
  const seated = bodies().filter(b => b.seat && b.typing).map(b => b.id);
  for (const id of ["forge-reviewer", "forge-tester", "forge-typer", "silent-failure-hunter"])
    assert.ok(seated.includes(id), `${id} should be seated and working, got ${seated}`);
  assert.equal(overlapFrames, 0, "standing characters must not overlap");
  assert.ok(maxStuck < 60, `a walker froze for ${maxStuck} frames`);
});
