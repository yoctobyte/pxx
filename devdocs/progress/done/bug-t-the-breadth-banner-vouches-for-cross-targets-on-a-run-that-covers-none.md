---
slug: bug-t-the-breadth-banner-vouches-for-cross-targets-on-a-run-that-covers-none
title: "The breadth banner reads last_full — the last REPLACING run, not the last `full` tier — so enabling mid_tier would make it vouch for cross-target coverage that never ran"
track: T
type: bug
prio: 40
blocked-by: []
status: done
found: 2026-08-29
found-by: pxx-a5
owner: pxx-a5
---

# The breadth banner vouches on a run that covers nothing

Latent today, and it arms itself the moment anyone does what
[[chore-t-the-tier-ladder-ratio-is-stale-by-its-own-criterion]] proposes. That
ticket recorded the interaction from the other side and said the banner should
be moved onto `last_by_tier` **before** any `mid_tier` experiment, not after.
This is that, split out so the ratio ticket can wait for a quiet box without
holding a correctness fix behind it.

## The defect

```python
lf = st.get("last_full") or {}
...
print("tstate:   breadth — newest full tier is %s old ...")
```

`last_full` is **the last REPLACING run** (`full=True`) — not the last `full`
TIER. The name is a historical accident and the file already says so in three
other places. Under the shipped default (`mid_tier == deep_tier == full`) the
two coincide, which is the only reason this read has been correct.

Set `mid_tier` to `limited` and they diverge:

- a `limited` run **replaces**, so it refreshes `last_full`;
- a `limited` run covers **no cross target at all**;
- the banner resets its clock on it and stops saying `[STALE]`.

The line whose entire job is to say *"no cross-target verdict on this tree;
native GREEN does NOT cover i386/arm32/riscv32/aarch64"* would go quiet on
evidence that does not support it. **That is the failure direction with no
output to notice** — the same shape as the comment-counts-as-wiring bug earlier
today, and the reason it is worth fixing before rather than after.

## The fix

`breadth_full_run(st)`, beside `last_run_at_tier()`, which answers the question
exactly: the newest COMPLETE run at that tier, exact match, never
`covered_tiers`.

The fallback is the part that needed care. State published before
`last_by_tier` existed carries no per-tier map, so a naive "no map, no verdict"
would report a coverage hole that is not there. It falls back to `last_full`
**only when `last_full` says it was a full tier** — so it can promote a true
full run that predates the map and can never promote a `limited` one. That
asymmetry is guarded in both directions.

## And the absence is now reported

Previously the banner printed only when `last_full` had a date. A host that had
run something to completion but never a `full` tier printed **nothing**, which
reads as "breadth is fine". It now says so:

> breadth — NO `full` tier recorded on <host> (newest complete run is
> `<tier>`): nothing here vouches for i386/arm32/riscv32/aarch64

Same rule as everywhere else in this file: absence is a fact, and a banner that
goes silent when it has nothing is indistinguishable from one that has checked.

## Guards

4 appended to `tools/twatch_opt_coverage_devtest.py` (16 total), which already
owns `last_run_at_tier`. They pin the divergent case (an older *real* full tier
must beat a newer `limited` run), the pre-`last_by_tier` fallback, that the
fallback refuses to promote a non-full run, and that no-full-tier returns empty
rather than substituting a lesser one.

Two mutations, each confirmed to parse and apply before its result was read:
restoring the plain `last_full` read fired 2 of 4; dropping the tier check from
the fallback fired 2.

## Not fixed here

The ratio measurement itself — three rungs, one sha, one core budget, on an
idle box. Still open on
[[chore-t-the-tier-ladder-ratio-is-stale-by-its-own-criterion]], and still
waiting on a box that is not the owner's workstation under load.

## Log
- 2026-08-29 — fixed with guards; resolved.
