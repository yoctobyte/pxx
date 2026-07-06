---
prio: 45  # auto
---

# feature: run the IR fuzzer automatically whenever the project is otherwise idle

- **Type:** feature (Track A — tooling/automation)
- **Status:** backlog
- **Parent:** [[feature-ir-fuzzer]]
- **Owner:** —
- **Opened:** 2026-07-05

## Motivation

`tools/fuzz.sh` (v1 landed, [[feature-ir-fuzzer]]) only produces value while
it's running. It's cheap and time-boxed by design, but someone has to
remember to kick it off. The obvious answer: **run it automatically whenever
nothing else is happening** — spare cycles otherwise going to waste, on a
project whose actual goal is "prove AST/IR correctness," not "compile any
particular language."

## What "idle" means, concretely, in this repo's workflow

This project already has a live signal for "is anyone actively working right
now": the `devdocs/progress/working/` folder is a **live lock** per
`devdocs/dev/parallel-tracks.md` — a ticket sits there only while an agent is
actively on it. So, conservatively:

**Idle = `working/` is empty (or contains only paused/parked tickets, not
actively-being-worked ones) AND the working tree is clean AND local `master`
is in sync with `origin/master`.**

That's a deliberately conservative bar — the fuzzer competes for CPU
(compiling + QEMU) and touches the same compiler binary other Track A work
might be rebuilding, so it should never run *alongside* real work, only in
the gaps.

## Design

- **Idle-check script** (`tools/fuzz_idle_check.sh` or similar): a fast,
  side-effect-free check implementing the definition above. Exit 0 = idle
  (safe to fuzz), non-zero = not idle (skip this tick). Cheap enough to call
  frequently without cost when it says no.
- **Trigger mechanism — pick one, don't build all three:**
  1. A scheduled cloud agent (see the `schedule`/cron tooling already
     available) that fires periodically, runs the idle-check, and if idle,
     invokes `tools/fuzz.sh --minutes N` for a bounded session.
  2. A `/loop`-driven session (dynamic self-paced loop) doing the same check
     + bounded run, if a human wants it live in an interactive session rather
     than a detached cron.
  3. A plain cron entry on a machine that already has the repo checked out —
     simplest, least infrastructure, if this doesn't need to run in the
     agent-cloud sense at all.
  Pick based on where "idle" is actually meaningful — machine-idle (cron) vs
  agent-fleet-idle (scheduled cloud agent) are different definitions and the
  right one depends on how this project's agents actually get invoked
  day-to-day. Not decided here — first decision when picked up.
- **Findings triage, NOT auto-filed as urgent bug tickets.** A scheduled,
  unattended process finding something should land in a low-noise staging
  spot (e.g. append to a dated log under `devdocs/progress/` or a dedicated
  `fuzz-findings/` scratch area) for a human or agent to triage and minimize
  before it becomes a real `bug-*.md` — avoids ticket-spam from an unattended
  loop and keeps the existing minimize-then-file pipeline
  ([[feature-ir-fuzzer]]'s sub-step 2/3) as the actual gate, not this
  automation.
- **Respect the time-box religiously.** Each triggered run must still exit
  within its budget even if idle persists — this is about using gaps, not
  about running forever once one is detected.

## Explicit non-goals

- Not a CI gate — this never blocks a commit or a PR, purely opportunistic
  background use of idle time.
- Not unattended auto-filing of bug tickets — findings need a triage step
  before becoming a real ticket (see above).
- Not decided yet which trigger mechanism (cron / scheduled agent / `/loop`)
  — that's the first thing to settle when this is picked up, informed by how
  idle time actually manifests in this project's workflow.

## Acceptance

Idle is detected correctly (doesn't fire while `working/` has real
in-progress tickets or the tree is dirty/unsynced); a triggered run is
time-boxed and never overlaps with active Track A/B/C/D work; any finding
lands in a low-noise staging spot rather than immediately becoming a ticket.

## Log
- 2026-07-05 — filed as a direct follow-up to [[feature-ir-fuzzer]] landing;
  user asked for "how to use fuzzing whenever everything else is idle" as its
  own ticket. Not started — trigger mechanism choice deferred to pickup time.
