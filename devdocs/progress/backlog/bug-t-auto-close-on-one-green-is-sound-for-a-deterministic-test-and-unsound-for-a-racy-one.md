---
track: T
prio: 50
type: bug
status: backlog
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
