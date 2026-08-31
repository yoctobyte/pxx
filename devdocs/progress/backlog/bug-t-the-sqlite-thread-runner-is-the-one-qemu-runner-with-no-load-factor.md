---
track: T
prio: 55
type: bug
status: new
owner: ""
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
