---
type: bug
track: A
prio: 3
summary: test_tthread failed once as test-threads#08 in a full tier and cannot be reproduced in isolation — 0 failures in 8 runs — so it is load-dependent, not a regression
tags: [threading, flaky]
---

Seen in a `--tier full` run on 2026-09-01 (frankB), which was RED with exactly
two failures: `test-core#244` (a real regression, mine, fixed by `a584e8fef`)
and this one.

    [2454/3617] FAIL test-threads#08     -> test/test_tthread.pas

**Not reproducible standing alone.** Built exactly as the Makefile does
(`--threadsafe`, no `-O`) and run 8 times, comparing against the tier's own
expectation `counter=400000 expected=400000 / TTHREAD OK`:

    failures: 0 / 8        (also 3/3 clean at -O2)

So the difference is the environment, not the binary: a full tier runs 3617
cases on a loaded box, and this is a 400k-increment contention test across
threads. That is the shape of a real race that only widens under scheduling
pressure — it is not evidence of a correct program, and "passes in isolation"
is exactly what a race looks like from here.

**Filed rather than dismissed** because the exculpation only covers the commits
in that run: I checked that it is not my element-kind work (that failure was
`test-core#244` and is separately fixed), which leaves "then what?" unowned.
This ticket owns it.

Next step for whoever takes it: reproduce under load rather than in isolation —
run it in a loop with the box deliberately busy, or under `--tier full`
concurrency — before reading any of TThread's synchronisation. A single
observation is not yet a located bug, and the counter value from the failing run
was not captured, so the first job is to get one that is.

## Re-measured 2026-09-16 at `7addc40f08af` (frankS, Track A) — 92 runs, three regimes, 0 failures

**Expectation recorded BEFORE the re-run**, because a null row is only
information to someone who said what they expected: I expected this to
reproduce under a constrained CPU. It is a 400k-increment contention test and
that technique had just surfaced two other load-dependent thread rows in the
same session. It did not reproduce.

| regime | runs | failures |
| --- | --- | --- |
| isolation, 12 cores | 10 | 0 |
| `taskset -c 0` (four threads time-sliced onto one CPU) | 10 | 0 |
| 24 concurrent instances x 3 waves, 2x oversubscription on 12 cores | 72 | 0 |

**NOT CLOSED AS FIXED, because nothing here proves the 2026-09-01 failure is
gone** — an unreproducible race that stays unreproducible is the same
observation the ticket already recorded, just with a larger N. What HAS changed
is the population of candidate causes, and it drained substantially:

- `bc3ab775e` (2026-09-13) — object refcounts were NOT ATOMIC on x86-64
  `--threadsafe`.
- `02b7f7250` (2026-09-14) — the allocator spinlock guarding FreeList/HeapPtr/
  HeapEnd inside PXXAlloc/PXXFree was gated `PXX_TS_SOFTLOCK` while x86-64
  selects `PXX_TS_HARDLOCK`, so it compiled out entirely on the default target.

Both are real `--threadsafe` races that widen under exactly the scheduling
pressure this ticket describes, and both postdate the failure. Either is a
plausible cause; neither is provable against a run from 2026-09-01.

Moved to `low-prio/` rather than `done/` or `rejected/`. The report was not
wrong — it really did fail once — so `rejected/` would misfile it, and `done/`
would claim a fix nobody made. It is real, probably no longer live, and has no
remaining actionable content: if it recurs, Track T files it fresh with a sha
that can actually be bisected. Leaving it ranked at prio 3 is the failure mode
the handbook names — an item that sits in the ranker forever at zero value.
