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
    width: 960, height: 680,
  };
}

const SAMPLE_STATE = {
  project: "demo", contextDir: ".forge", schema: "1", generatedAt: new Date().toISOString(),
  tracker: {
    phase: "Phase X",
    inProgress: [{ text: "unit 12: thing", attempts: ["a1", "a2"] }],
    nextUp: ["unit 13: next"], completed: ["unit 11: done"], notes: ["note"], openQuestions: [],
  },
  plan: { pending: [{ text: "13 next", unit: 13, high: true }], completed: [] },
  claims: [{ unit: "12", mode: "build" }], locks: [{ name: "tracker", ageMin: 2, stale: false }],
  sessions: [
    { session: "s1", skillState: "active", skill: "forge-build",
      agents: [{ agent: "forge-reviewer", since: 1 }, { agent: "forge-tester", since: 2 },
               { agent: "forge-typer", since: 3 }] },
  ],
};
const SAMPLE_FEED = [{ ts: "2026-07-18T10:00:00", event: "skill_invoked", project: "demo", skill: "forge-build" }];

test("inline UI script runs headlessly: refresh + 30 animation frames, no errors", async () => {
  const ops = [];
  const frames = [];
  const ctxGlobal = {
    document: { getElementById: () => makeEl(ops), createElement: () => makeEl(ops) },
    fetch: async (url) => ({
      json: async () => (String(url).includes("feed") ? SAMPLE_FEED : SAMPLE_STATE),
    }),
    EventSource: class { constructor(){} addEventListener(){} set onopen(v){ v && v(); } set onerror(_){} },
    requestAnimationFrame: (cb) => { frames.push(cb); },
    setInterval: () => 0,
    console,
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
});
