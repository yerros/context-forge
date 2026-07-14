---
name: forge-brainstorm
description: >
  This skill should be used for grounded ideation in a Six-File Context Methodology
  project — phrases like "forge-brainstorm", "brainstorm ideas for X", "what should
  we build next", "I have a vague idea", "explore options for", "which approach is
  better", or "help me think this through". It diverges into options, stress-tests
  each against the project's scope, invariants, and lessons, converges on a
  recommendation, and routes the outcome (forge-feature / forge-decision / the
  context/ideas.md parking lot) so good ideas never evaporate. Planning only — it
  never writes code.
metadata:
  version: "0.19.0"
---

# forge-brainstorm

The fuzzy front-end of the methodology: turn a vague idea or open question into
either a routed next step or a consciously parked idea. What makes this different
from generic brainstorming is grounding — every option is tested against what the
project actually is, so the output is options that survive contact with reality.

## Argument

Text after the command is the topic (e.g. `/forge-brainstorm cara monetisasi app
ini` or `/forge-brainstorm offline mode: worth it?`). No argument → ask what to
think about.

## Load (cheap)

Tier 1 (digest) plus `context/project-overview.md` (goals, scope, **out of scope**)
and `context/lessons.md`. Read `architecture.md` only when an option's feasibility
hinges on it. Everything stays in-session — brainstorming is a dialogue with the
user, not a subagent job.

## 1. Diverge

Generate genuinely different options across axes (build/buy/integrate, big/small,
now/later, different user segments or mechanisms — whatever fits the topic).
**Always include "don't build it" as the baseline** with an honest account of what
that costs. Aim for 3–6 options; quantity is not the goal, spread is.

## 2. Stress-test (this is the grounded part)

Run every option against:

- **Scope** — does it conflict with project-overview.md's goals or land in Out of
  Scope? Say so; the user may still choose it, but then scope must change first.
- **Invariants** — would it require breaking an architecture.md invariant? Label it
  expensive and name the invariant.
- **Lessons** — does it rhyme with a recorded mistake in lessons.md? Quote the
  lesson.
- **Effort** — rough size in build units (peanut / a unit / several units / a
  phase), and whether it would carry a `[complexity: high]` marker.

Drop options that die here, and say why they died — a killed option with a clear
reason is a useful result.

## 3. Converge

Recommend 1–2 survivors with honest trade-offs (what you gain, what it costs, what
it forecloses). Present the comparison compactly; ask the user to pick, adjust, or
park.

## 4. Route — ideas must not evaporate

For the chosen outcome, exactly one of:

- **Build it** → hand off to `forge-feature` with the converged description (it
  will update scope and have `forge-architect` write the spec).
- **Architectural choice** → hand off to `forge-decision` (ADR).
- **Not now** → park it in `context/ideas.md` (create from
  `${CLAUDE_PLUGIN_ROOT}/skills/forge-init/templates/context/ideas.md` if absent):
  **one line per idea** — `- [topic] idea → why parked / wake condition`. Show the
  line before writing. Budget ~1.5 KB (~10–12 ideas); when full, drop dead ideas
  first (with approval), promote ripe ones via `forge-feature`.
- **Dead end** → say so and write nothing. A brainstorm that concludes "no" is a
  success, not a failure.

## Rules

- Planning only: never write or modify code, specs, or context files other than
  `ideas.md` (and that only with the line shown first).
- Ground claims in the context files; label anything else as opinion.
- Don't flatter ideas — the stress-test exists to kill weak options early, which
  is the cheapest place to kill them.
- Ideas parked in `ideas.md` are re-surfaced by `forge-resume`/`forge-feature` only
  when the user asks ("apa ide yang kita parkir?") — never auto-read.
