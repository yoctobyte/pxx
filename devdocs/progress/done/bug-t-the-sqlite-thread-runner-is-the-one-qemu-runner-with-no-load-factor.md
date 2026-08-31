---
track: T
prio: 55
type: bug
status: done
owner: frankT
blocked-by: []
summary: "`tools/run_sqlite_thread_test.sh` scales its inner timeout by TESTMGR_TIME_SCALE but NOT by TESTMGR_LOAD_SCALE. All three sibling qemu runners use both (`t=20*s*l`). Consequence, measured: test-sqlite-threads-aarch64 has been RED since 2026-08-29 purely as a TIMEOUT under sweep concurrency -- `FAIL aarch64 (TIMED OUT after 120s; TESTMGR_TIME_SCALE=1.00)` at bebac33366f5, tier full, host seven, wall 592.5s. Time scale was 1.00 because seven is not slow, it is BUSY, which is exactly what the load factor exists to express. Plexus runs the same job in 37s idle and 62s under a 12-way load. This is a dup of regression-testmgr-conformance-shard-timeout-under-load (done) in the one runner that never got that fix."
---

# The sqlite-thread runner is the only qemu runner with no load factor

- **Filed:** 2026-08-31 by frankA (Track A), from the other end — it is the
  standing cause of an open Track A regression. **Track T's file, not edited:**
  the size of an inner timeout is a claim about sweep economics (a longer budget
  slows every full tier), and that is T's to price.

## The gap

| runner | budget |
| --- | --- |
| `run_c_conformance.sh` | `TIME_SCALE` **and** `LOAD_SCALE` |
| `run_fgl_corpus.sh` | `t=20*s*l`, both |
| `run_pascal_conformance.sh` | both |
| **`run_sqlite_thread_test.sh`** | **`TIME_SCALE` only** — `run_to=120` at :32, scaled at :63 |

`run_c_conformance.sh:55-60` documents this failure for its own shards and names
`regression-testmgr-conformance-shard-timeout-under-load` "and dups". This is
another dup.

## Read this before looking at the code — the obvious diagnosis is wrong

`SCALE` is **not** merely printed in the failure message. Line 63,
`run_to="${CSTT_RUN_TIMEOUT:-$(scaled "$run_to")}"`, genuinely applies it. I had
it as "assigned and only used in the message" and that is false. What is missing
is specifically **`TESTMGR_LOAD_SCALE`**, the live concurrency factor
(`cap/cores`) that testmgr exports.

## Suggested shape, T's call

```sh
scaled() { awk -v t="$1" -v s="$SCALE" -v l="${TESTMGR_LOAD_SCALE:-1}" \
  'BEGIN { v=t*s*l; printf "%d", (v < t ? t : v) }'; }
```

Keeps the existing floor and leaves `CSTT_RUN_TIMEOUT` as the override.

## The check that must come with it

If the job **still** times out with the budget stretched, the timeout is real
and there is something to chase — so the fix is not self-verifying and should
not be closed on a green alone. Two days of reds cannot be re-read to tell
timeout from wrong answer, because the runner that produced them printed one
line for both; that is what `fc5762a2f` fixed and why this is now legible at all.

## Related

- `regression-test-sqlite-threads-aarch64-output-mismatch-untracked-since-08-29`
  — the Track A regression this blocks; carries the full report evidence.
- `regression-testmgr-conformance-shard-timeout-under-load` (done) — same bug,
  different runner.

---

## FIXED 2026-08-31 by frankT — with a cap, because the sibling formula alone COLLIDES

Applied `t * TESTMGR_TIME_SCALE * TESTMGR_LOAD_SCALE` as the siblings do, and
then capped it, because the obvious fix lands exactly on a wall:

**testmgr classes this job as `qemu`, whose OUTER per-job timeout is 240s**
(`CLASSES` in `tools/testmgr.py`). `TESTMGR_LOAD_SCALE` is **~2.00** at default
width (`hard_cap = nproc*2`). So the sibling formula gives
`120 * 1.00 * 2.00 = 240` — **precisely the outer.** The outer would then
pre-empt the inner, and a job-level kill reports only `TIMED OUT`, discarding
the elapsed/budget/scale line this runner exists to print. **We would have spent
the diagnostic in order to buy the budget** — and that diagnostic is the only
reason anyone knows this was a timeout rather than a miscompile.

frankS predicted this collision when declining to apply the fix
(*"doubling the inner one can push past the outer"*). It was not merely
directionally right, it was **numerically exact**.

So `INNER_CAP=200`: 1.67x the old budget under a sweep, 40s clear of the outer,
and a serial `make` run is unchanged at 120s (both scales neutral).

**`tools/run_sqlite_inner_budget_devtest.py` reads BOTH constants from their real
files** — the cap out of the runner, the `qemu` timeout out of `testmgr.py` — and
fails if the gap ever closes. Changing either one alone cannot silently recreate
the collision. Its positive control is the collision itself: it asserts that
*uncapped*, the sibling formula does reach the outer, so the cap is load-bearing
rather than decorative. It also asserts the budget still STRETCHES (a cap that
pinned it to the base would be no fix) and that `$LOAD` reaches the awk
expression rather than only the failure message — the exact misread frankA
flagged.

Both branches exercised for real, not just fixtured:
`CSTT_RUN_TIMEOUT=5` prints
`FAIL aarch64 (TIMED OUT after 5s; TESTMGR_TIME_SCALE=1 TESTMGR_LOAD_SCALE=1 cap=200s)`,
and `x86_64` still prints `PASS x86_64 (libc-free, shared+per-thread) 2s/60s`.

## What this does NOT establish, and it is the honest limit

**A timeout tells you the budget was too small. It never tells you by how much.**
Seven died at 120s; nothing says whether it needed 130s or 400s, and that number
cannot be measured from plexus — plexus runs the job in 37s idle and 62s under a
12-way load, so it cannot reproduce seven's concurrency. If the next full sweep
still times out, the message now names the cap, which **raises the known lower
bound to 200s** and is the datum needed to price the next move. That next move
is a `qemu` class change (outer up, or timeouts excluded from
`RUN_RETRY_CLASSES` — a deterministic budget exhaustion retried three times
costs 3x and buys nothing), and it should be made on that measurement rather
than tonight's guess.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
