---
name: forge-prompt
description: >
  This skill should be used to sharpen a rough or vague request into a high-quality,
  context-aligned prompt before acting on it — phrases like "forge-prompt", "optimize
  this prompt", "refine my request", "make this prompt better", "turn this into a proper
  prompt", or "what's the best way to ask for this". It clarifies intent, grounds the
  request in the project's context files, and outputs a sharp prompt or spec the user
  confirms — it never silently changes what the user meant.
metadata:
  version: "0.1.0"
---

# forge-prompt

Turn a rough request into a precise, buildable instruction. The goal is to improve the
*quality of the thinking* behind the prompt — not to wordsmith. Output a sharpened prompt
the user approves, never a silent reinterpretation.

## Principle

The user owns intent. This skill makes intent explicit and complete; it does not invent
goals, change scope, or assume requirements. When something is ambiguous, ask — don't
guess.

## Steps

### 1. Read the raw request and the project context

Take the user's rough request. If the project uses the methodology (a `context/` folder
exists), read `project-overview.md` and `architecture.md` for scope and invariants, and
the build plan / specs if relevant. This grounds the optimized prompt in the real system
instead of generic advice.

### 2. Detect gaps

Identify what's missing for a high-quality prompt:

- **Goal** — is the concrete outcome clear?
- **Scope** — which unit / boundary / files does this touch? Anything explicitly out of scope?
- **Constraints** — invariants, tech choices, patterns from the context files that apply.
- **Acceptance** — how will "done" be verified?

### 3. Ask only what's necessary

If critical gaps exist, ask 1–2 focused clarifying questions. Do not interrogate — ask the
fewest questions that remove real ambiguity. If the request is already clear, skip this.

### 4. Produce the optimized prompt

Output a sharpened version using this shape (adapt length to the task):

```
Goal: <one concrete sentence>
Scope: <what to change; what NOT to touch>
Constraints: <relevant invariants / standards / tech>
Acceptance: <how done is verified>
```

For a feature-sized request, recommend producing a full spec via `forge-spec` /
`forge-feature` instead, and hand off.

### 5. Confirm, then hand off

Show the optimized prompt and ask the user to confirm or adjust. On approval, either act
on it directly or route to the right skill (`forge-build` to implement, `forge-spec`
to write a spec, `forge-debug` when stuck).

## Rules

- Never replace the user's intent — clarify and structure it.
- Prefer asking over assuming when a gap is material.
- Keep the optimized prompt proportional: a one-line fix doesn't need a full spec.
- Ground constraints in the project's context files when they exist; don't invent rules.
