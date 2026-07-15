# Loop contract (shared reference)

The canonical rules for when an agent may loop on its own work: what counts as
done, who is allowed to say so, and what a retry must carry. Used by `forge-build`,
`forge-build-all`, `forge-verify`, `forge-fix`, and `forge-debug`. If the loop
rules change, change them HERE only.

The premise: **models fail confidently.** Broken code throws and stops the loop;
a wrong model returns a convincing answer and keeps going. So the source of truth
must sit outside the model — the model is never a legitimate judge of its own work.

## 1. Completion is external

A unit/fix is done when external conditions say so — test exit codes, build/lint
exit codes, the spec's checklist — never when the model feels finished or stops
asking for tools. "The code looks correct" is not a completion condition; `exit 0`
is.

## 2. Claims require evidence

Every "passes" on a checklist item must cite its external evidence:

- mechanical items → the command and its exit code / summary line
  (`npm test → exit 0, 84 passed`)
- inspectable items → file:line or concrete observed output
- items with **no obtainable external evidence** → marked `UNVERIFIED — needs
  human check`, never silently self-attested. An honest UNVERIFIED beats a
  confident lie.

Verification must be **fresh**: re-run the command, re-read the file — never cite
memory of an earlier run (that run predates your latest change). Where a clean
context is affordable, use one: deterministic tools always; the `forge-reviewer`
subagent per the risk tiering. Self-review in the same transcript is the weakest
form of verification — evidence citation is what keeps it honest.

## 3. Retries add information — the attempt log

A retry that knows nothing about the last failure is a coin flip. On every failed
verification attempt, append one line to the unit's **In Progress** entry in
`context/progress-tracker.md` (a file — so it survives compaction and session
loss):

```
attempt N: [failing check] — tried: [approach] — result: [error/symptom]
```

Rules:

- **Before retrying, read the attempt log.** The next attempt must differ
  materially from every logged approach — rewording the same fix is not a retry.
- Carry into the retry: the exact failing check, the specific error, and the
  contract it violates (spec line / rule / invariant).
- **After 2 failed attempts on the same check: stop.** Escalate to `forge-debug`
  and hand over the attempt log — the diagnosis starts from what is already known
  to not work, never from zero.
- When the unit closes, the attempt log is cleared from the tracker (the close-unit
  procedure); a recurring root cause becomes a lesson first.

## 4. State survives compaction

Progress lives in files, not in the transcript: the tracker (with the attempt
log), specs, lessons, `.last-session.md`. Anything the loop needs to resume must
be re-derivable from disk — assume the transcript can be truncated at any moment.

## The one-line version

Done means external evidence says done; claims cite their evidence or say
UNVERIFIED; retries read the attempt log and differ; two failures hand the log to
the diagnostician; everything that matters is on disk.
