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
