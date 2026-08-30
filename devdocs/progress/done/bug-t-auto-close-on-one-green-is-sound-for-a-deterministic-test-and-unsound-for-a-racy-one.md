---
track: T
prio: 50
type: bug
status: done
blocked-by: []
found: 2026-08-29
found-by: frankB (measured); filed by frank-coordinator
summary: "The watcher auto-closes a regression ticket on a single green. For a ~12%-failure race that is the EXPECTED outcome with the defect fully present -- and it happened: the reactor-exhaustion ticket was auto-closed while the bug was live. Nothing in the ticket stub tells the closer whether it is holding a deterministic test or a racy one."
---

# Auto-close on one green is sound for a deterministic test and unsound for a racy one

## What happened

frankB fixed a reactor-exhaustion regression on `seven` (`8f0e1a589`): a losing
thread's `Halt` (= `exit_group`) could kill the winner mid-`writeln`, giving
status 216 and an empty log. While chasing it, it found that **the watcher had
already auto-closed that ticket on a single green.**

For a race that fails ~12% of the time, one green is **the expected outcome even
with the defect fully present.** The close was not a misfire — it is what the
rule produces on that input.

## Why the rule cannot see the difference

Auto-close on one pass is correct for a deterministic test: build, run, compare,
and a pass genuinely refutes the red. It is unsound for anything whose failure is
probabilistic — threads, sockets, scheduling, allocator order. **Nothing in the
ticket stub tells the closer which of the two it is holding**, so the rule applies
the deterministic policy universally and silently.

testmgr already draws this exact line elsewhere and could be the source of truth
for it. `RUN_RETRY_CLASSES` exists because `qemu`, `corpus`, `conformance` and
`opt` are runtime-nondeterministic, while `unit` and `selfhost` are deterministic
and stay single-shot — *"a real red fails every attempt, so confirm-retry never
hides one"*. The closer needs the mirror of that judgement and does not have it:
**for a retry-class job, one green should not close a ticket.**

## The asymmetry that makes this expensive

A wrong auto-close is silent and durable. The ticket leaves the queue, the
regression stays in the tree, and the next observation of it reads as a **new**
red rather than a reopened one — so the history that would have identified it as
intermittent is exactly what gets destroyed. Compare a wrong auto-*open*, which
costs one triage and is over.

Same family as the standing rule that a false limit is quieter than a false fix:
a closed ticket is a positive claim that something was checked.

## Suggested shape, not a prescription

The cheap version is to reuse the class the job already carries: **a green closes
a ticket only when the failing job's class is deterministic; a retry-class job
needs N consecutive greens** (N chosen against the observed failure rate — frankB
measured 5/40 at 24 workers on a file, i.e. ~12%, so one green is ~88% likely to
be wrong). The sweep-time tradeoff is **Track T's call** and is why frankB
declined to file this itself; the finding is banked here so the call gets made
rather than inherited.

## The methodology note frankB attached, which is worth as much as the finding

frankB's own first check **falsely cleared** the bug: it probed through a pipe
while the harness redirects to a file. Same binary, **0/12 failures on a pipe vs
5/40 on a file** at 24 workers. The reproduction environment differed from the
harness's in a way that changed the answer, and the direction was toward "fixed".

It also kept both sides of the file rather than overwriting the watcher's entry,
and wrote the disagreement up. That is the right handling of a conflict between a
human-lane finding and an automated verdict: **concatenate, do not resolve in
favour of one side.**

---

## 2026-08-30 — FIXED. The Track T call the ticket asked for, and it goes
## against the ticket's own suggested shape, on arithmetic and one measurement.

### Both proposals in this ticket fail, and saying so is the call

**1. "Reuse `RUN_RETRY_CLASSES`" would not have caught the incident that
produced this ticket.** That set is `{qemu, corpus, conformance, opt}` and is
about runtime variance from the **environment** — emulation, corpora, big
sweeps — not about a test's own concurrency. Measured through `classify()`
rather than assumed:

```
reactor job class      : unit
in RUN_RETRY_CLASSES   : False
```

`test/test_sched_reactor_exhaustion.pas` is a `unit` job. The class rule is
still right about what it covers and is kept as one arm; it is simply not the
arm that matters here.

**2. "N consecutive greens" cannot work at any affordable N**, and the
arithmetic is the entire argument. At the measured ~12% failure rate, three
greens leave a **68%** chance the bug is live (`0.88³`); pushing that under 5%
needs about **24**. No sweep cadence pays that. **Absence of a failure is not
evidence for a race**, so the answer cannot be a bigger N — which is why this
did not ship as "N=3 and hope".

### What does discriminate, and both arms were already in the record

Neither needs new state, and neither is a guess about test semantics:

- **The closing green was itself FLAKY.** The job failed and passed on a retry
  *in this run* — the race firing while we watched, not an inference. This arm
  could not have been written before 2026-08-30: testmgr had always put `flaky`
  in its result JSON and the publisher dropped it
  ([[bug-t-a-testtmp-binary-name-is-shared-by-two-tests-and-by-two-targets]]).
- **The stub is a REPEAT.** `stub_slug_for_filing()` opens `<base>-2`, `-3` only
  when a **resolved predecessor exists**, so a variant suffix is a structural
  record that this job went red, was closed, and came back. That is the
  definition of intermittent-or-never-fixed, and **it is the arm that catches
  the reactor case** — which was auto-closed twice on 2026-08-29, the second
  close being exactly a repeat stub.

### Refusing is not silent, and not a leak

A stub that cannot be closed on one green is **annotated in place**: the green,
its sha and tier, and the reason it did not close, with the note that closing is
a human's call. Re-annotation is suppressed once the sha appears in the body, so
a long-lived stub does not grow a line per sweep. The alternative — leave it and
say nothing — reproduces the ticket's own complaint from the other side: a
ticket that stops moving for an unstated reason reads as forgotten.

The rule stays useful. 82 auto-closes have happened on this repo; a change that
stopped them all would trade a silent wrong close for a silent backlog, so the
first guard asserts a deterministic first-time stub still closes exactly as
before.

### Guards: `tools/twatch_autoclose_race_devtest.py`, 6, each checked against
### its own broken condition

| injected | result |
| --- | --- |
| the REPEAT arm removed (i.e. this ticket's proposal kept alone) | 2 red — *"the reactor case is NOT covered: it classes `unit` (not a retry class), so only the repeat arm can catch it, and that arm is gone"* |
| the FLAKY arm removed | 1 red, naming the retry |
| `twatch.RETRY_CLASSES` drifted from testmgr's | 2 red, printing both sets |
| clean | 6 green |

The first row is the one worth keeping: it is a guard whose failure message
states why the obvious fix is insufficient, so the obvious fix cannot be
re-adopted as sufficient later. `twatch` does not import `testmgr`, so the class
set is duplicated — and guarded against drift rather than left to comment.

One instrument error recorded: the first run of that first control deleted a
line range rather than an exact string and cut into the function, so all six
guards failed with `no attribute one_green_cannot_close` — a control that
destroys its subject proves nothing. Redone as an exact-string removal with the
syntax re-validated and the sha checked on restore; then it said the right
thing.

### Gate

`make compiler/pascal26`: self-host fixedpoint verified, `67f47b5bc540`. Seven
twatch/tstate devtests green plus the new 6. `tools-devtest` collects the file,
and testmgr runs that in the `quick` and `limited` tiers.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
