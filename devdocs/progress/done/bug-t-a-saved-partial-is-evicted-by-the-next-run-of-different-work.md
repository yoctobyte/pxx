---
slug: bug-t-a-saved-partial-is-evicted-by-the-next-run-of-different-work
track: T
type: bug
prio: 60
status: done
blocked-by: []
summary: "Shape 2 (resumable aborted runs) has never once delivered: 9 partials saved, 1420 jobs saved, 0 carried, 9 superseded. There is ONE partial slot (.testmgr/resume.json) and every gate run claims it, so any interleaved run of different work evicts it. Since the whole point is to finish a 21-minute pin verify across 5-minute idle slices, and a push-driven native run lands in between every time, the partial is destroyed before it can ever be used. resume_health() was built to detect exactly this and its numbers say it is happening."
owner: plexus-T
---

# A saved partial is evicted by the next run of different work

## The finding

`resume_health()`'s own docstring names this failure shape: *"`saved` partials
that never become `carried` runs is the exact silent-degradation shape: every
individual log line reads fine and the mechanism does nothing."* Its numbers now
say that is what is happening. From the watcher clone, 2026-08-19T20:23:12Z:

    saved_partials : 9
    saved_jobs     : 1420
    carried_runs   : 0      <- absent from the file, i.e. never incremented
    superseded     : 9
    discarded      : 0
    no_report_on_abort : 0

**Nine saves, nine supersedes, zero carries.** 1420 decided jobs preserved and
then thrown away, at a 100% loss rate. Shape 2 has never delivered once since it
landed (`e2449adc5`).

## The mechanism

`RESUME_REL` is a single path — `.testmgr/resume.json` — and *every* gate run
passes a `resume_key=(sha, tier)` and calls `resume_arg()`. On a key mismatch
that function does not merely decline to use the partial; it **deletes** it:

    if (part.get("sha"), part.get("tier")) != key:
        ...
        bump_resume_stats(clone, superseded=1)
        drop_partial(clone)
        return None

So the observed cycle is:

1. pin verify on `cabb5d598`/`full` gets an idle slice, aborts partway, saves a
   partial worth a few hundred jobs;
2. a push arrives — the fast verdict runs `newHEAD`/`native`, calls
   `resume_arg()` with a different key, and **drops the pin-verify partial**;
3. the next idle slice restarts pin verify from zero.

Step 2 is not an edge case. It is the normal operation of the watcher, and it is
guaranteed to happen between any two idle slices, because idle slices are
*separated by* the pushes that end them.

## Why the eviction looked right

The comment argues the drop is sound: *"the watcher moved on to different work,
and the old partial can never become valid again."*

That is true for a HEAD-progression `full` tier — HEAD moves on and that exact
sha is never tested again — and **false for the case shape 2 was built for.**
Pin verify targets the PIN's sha, which does not move when HEAD does; it moves
only when a pin lands. The ladder returns to that same `(sha, tier)` on every
subsequent idle slice, which is precisely why a partial for it is worth keeping.

One true statement about HEAD progression, applied to a target that does not
progress. The eviction is correct for the case it was written against and wrong
for the case that motivated the feature.

## Why it matters

This is the load-bearing half of `bug-t-the-push-rate-starves-breadth-coverage-entirely`.
That ticket's re-measurement concluded breadth is queued behind an unfinishable
pin verify — 21 contiguous minutes wanted, ~5-minute slices available, 100% of
work discarded per abort — and recommended shapes **2 + 4**. Shape 4 shipped and
works (`idle_yield` yields the slot after 3 aborts; the live tstate shows it
counting). Shape 2 shipped and does nothing, so the "with shape 2 it does" half
of that recommendation is not in force. A 21-minute job still cannot complete in
5-minute slices.

## The shape of a fix

Keep partials in a small keyed store rather than one slot: `.testmgr/resume/`
with a file per `(sha, tier)`, or a single file holding a dict keyed the same
way. A run then reads *its own* partial and leaves everyone else's alone.

Constraints:

- **Bounded.** Partials carry every decided job's dict; 1420 jobs is not small.
  Cap the count and evict oldest-first, and *say* what was evicted.
- **The compiler-sha256 guard stays.** `load_resume()` refuses a partial whose
  binary does not match, which is what makes a carried result attributable. That
  check is orthogonal to this and must not be relaxed to make carries happen.
- **Genuinely dead partials should still go.** A HEAD-progression sha really is
  never revisited, so its partial is garbage — but it should be evicted by age
  or capacity, not by "some other run started".
- **`carried_runs` becoming non-zero is the acceptance test.** The rate is the
  measurement, not the individual save (see the standing rule about reporting
  resume-stats rates rather than the one-off save).

## The fix

`.testmgr/resume.json` (one slot) became `.testmgr/resume/` (one file per key),
via a new `partial_path(clone, key)` = `<sha[:12]>-<tier>.json`.

- **`resume_arg()` is now read-only.** It opens *its own* key's file and returns
  the path or None. The mismatch branch that called `drop_partial()` is gone —
  that branch was the bug, and its comment ("the watcher moved on to different
  work") was a true statement about HEAD progression applied to pin verify,
  whose target sha does not move. What survives of it is a payload check: a file
  whose contents disagree with its filename is declined, because the name is a
  convenience and the payload is the authority.
- **`drop_partial(clone, key)` takes a key.** The post-run call at the end of
  `run_gate` passes `resume_key`, so a finished run still clears its own partial
  — the retry-after-INFRA case the original comment was right about — and only
  its own. `key=None` still targets the legacy slot, which `save_partial` also
  unlinks on first write so it cannot shadow the store.
- **`gc_partials()` bounds it at `PARTIAL_CAP = 4`,** newest kept, oldest evicted
  by mtime, and it prints what it dropped. Four covers the live interleave (a pin
  verify, a breadth backfill, and the fast verdicts landing between their slices).
  An aged-out partial still bumps `superseded`: it is the same lost work an
  eviction was, and a silent GC would hide a regression behind a healthy-looking
  `saved` count.
- **`load_resume()`'s compiler-sha256 guard is untouched.** Nothing here relaxes
  attributability to manufacture a carry.

Guarded in `tools/twatch_resume_devtest.py`. The headline check is
`"A RUN OF DIFFERENT WORK DOES NOT EVICT IT — it is still there"`; the rest cover
coexistence of two partials, self-only drop, the payload-vs-filename check, the
cap, newest-survive, and that an aged-out partial is counted. Non-vacuity proved
by restoring the evict-before-read behaviour in a scratch copy: **4 checks go
red**, including the headline. `PXX_TRACK=T make tools-devtest`: 48 guards green.

**What is proved and what is not.** The devtest proves a partial now survives an
interleaved run of different work — the mechanism that caused the 100% loss rate.
It does not prove a carry: `carried_runs` can only be observed to leave zero by
the live watcher completing a resumed slice. That number is the follow-up
measurement, and it stays the acceptance test.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
