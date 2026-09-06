---
slug: bug-t-the-full-matrix-switches-itself-off-when-the-fleet-is-busy
type: bug
track: T
prio: 60
status: open
owner: frankH
---

## summary

The full tier's breadth is inversely coupled to the fleet's push rate, with a
threshold at roughly **one push per 60 seconds** — and above it breadth degrades
**silently**, because the native tier keeps publishing green.

## the mechanism, measured 2026-09-06

`twatch.py`'s phase ladder is priority-ordered and step 1 (new push -> fast
tier) preempts everything below. The idle full backfill has a commitment point,
`full_commit_secs = 60` (`CONF_DEFAULTS`, used at the backfill and at the
request queue): a push inside the first 60s aborts the run and it publishes
nothing; after 60s it is allowed to finish. So a full needs **60 contiguous
push-free seconds to become uninterruptible.**

```
commits/15min on origin/master, 2026-09-06:
  15:00-18:30   5..17        full tiers completing every ~15-25 min (13 that day)
  18:45         26           <- last full was 18:37Z; none for the next 40+ min
  19:00         20
```

26 per 15 min is a push every ~35s. Natives (~170s wall, every ~4.5 min) keep
landing green throughout, so every visible signal says healthy.

The pre-18:37 fulls were COMPLETE, not truncated — `timed_out: False`,
`unreached: 0`, deadline 4547s never approached. They read ~601s because
partial-resume carries decided jobs forward; the cold cost is 1867s (the
16:16:30Z run). A commit touching `compiler/**` invalidates the partial
(`load_resume()` keeps it only if the compiler rebuilds byte-identical), so a
busy fleet also raises the price of each attempt.

## why it is not just "ask for one"

The request queue (`--request <sha> --request-tier full`) is drained FIRST among
idle phases and is the documented escape hatch — but it carries the **same 60s
commitment requirement**, so it jumps the queue without escaping the starvation.
`twatch.py` records exactly this, 2026-08-27: *"a `full` request sat undrained
while the log showed the phase being ENTERED and then 'preempted by a push —
will resume', 15 times. The queue's position was never the problem — it is
reached fine and cannot FINISH."*

## why this is a decision and not a patch

Every piece behaves as designed and the design is documented and reasoned. What
is new is FLEET SIZE: enough concurrent workers and the repo never goes quiet
for 60s, so the fleet switches off its own cross-target coverage by working
normally, and nothing reports that it has.

CLAUDE.md's breadth guarantee — *"T samples the tip every ~8 commits, a
persistent regression is caught within ~8"* — is being satisfied by the NATIVE
tier while the full matrix falls behind. Those are different claims and the
rule does not distinguish them.

Options, none taken: raise `full_commit_secs`; reserve a periodic full slot that
pushes may not preempt; make breadth age a reported signal that goes RED on its
own; or accept it and treat a landing hold as the standing procedure before any
tier that matters. **The last is what worked on 2026-09-06** — but it needs a
human to call it, which is the part that does not scale.

## not claimed

Measured on seven, on one day, at one fleet size. The threshold is derived from
`full_commit_secs` and the observed push rate, not from an experiment that
varied the rate.
