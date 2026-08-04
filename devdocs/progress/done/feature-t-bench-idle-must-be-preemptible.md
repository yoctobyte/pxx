---
summary: "Every idle phase yields to a new push except bench — so worst-case time-to-verdict is ~2-3 min of benchmarking, an order of magnitude above the poll interval anyone would tune"
type: feature
track: T
prio: 55
status: done
owner: claude@xeon
---

# The bench phase is the one idle job a push cannot interrupt

- **Type:** feature (Track T tooling — verdict latency)
- **Opened:** 2026-08-02 by `claude@xeon`, while recording
  [[decide-t-notification-transport-poll-not-webhooks]]. Part of
  [[meta-t-dev-throughput-and-track-a-t-integration]], whose whole premise is
  that **T's report latency is now the product**.

## The gap

`twatch`'s idle chain, in order, below a fully-tested head:

| phase | preemptible on a new push? | rough cost |
|---|---|---|
| full-matrix backfill | yes (`make_preempted`, ~30s granularity) | ~10 min |
| opt differential sweep | yes | minutes |
| **bench** | **NO** | **~2-3 min** |
| bisect step | short by construction | seconds-minutes |
| fuzz (endless) | yes | unbounded |

`run_bench_idle()` takes no `abort_check` and says so:

```python
"""... Not preemptible — ~2-3 min, shorter than a full backfill."""
```

That reasoning was sound when the alternative was a 10-minute backfill. It is
no longer, because everything *around* it got preemptible and the dev loop got
fast: a push that lands during bench waits out the whole bench run plus the
20s debounce before the daemon even fetches it. Nothing else in the system
costs anywhere near that.

## Why it is worth fixing rather than accepting

The measured dev cycle is ~12-15s (`make compiler/pascal26`, which is itself
the byte-identical fixedpoint). Against that, 2-3 minutes of invisible wait is
10x the work it is delaying, and it lands *unpredictably* — you only hit it if
your push happens to arrive during bench, so the same action has a wildly
different latency depending on nothing the agent can see or control. Erratic
latency is worse than uniformly slower latency: it is what makes an agent
start polling "is it done yet", which is the exact behaviour the offload model
exists to stop.

It also interacts badly with the decision above: with webhooks off the table
by design, every consumer's responsiveness is bounded by when the daemon
notices. Making the daemon's blind spot the largest number in the system
undercuts the transport we chose.

## Asked for

1. Thread the same `abort_check=make_preempted(clone, tested)` through
   `run_bench_idle()` that the backfill, opt sweep and fuzzer already use.
2. **Discard, never publish, a partial bench run.** The rows are a time series
   keyed by sha; a truncated set would look like a workload got faster because
   half of it never ran. On abort: drop the temp TSV, record nothing, leave
   `last_bench` unset so the sha is re-benched next time the box is idle.
3. Keep the existing checkout discipline exactly as-is — bench runs detached at
   the sha, writes to a temp TSV, and appends only after
   `clone_head_back()`. An abort path must not leave the clone detached or
   dirty; a dirty clone makes every following cycle hit the dirty-pause and the
   watcher wedges (observed 2026-07-11, noted in the code).
4. Same for the FPC conformance sub-run inside the same phase — it is a second
   subprocess after `--bench` and must honour the same abort.

## Gate

With the daemon in `bench` (visible in `.testmgr/watch.json` and
`trackt health`), push a trivial commit and confirm: the bench run is torn down
within one abort poll, no partial rows appear in `tstate/bench.tsv`, the clone
returns to its branch clean, the new sha gets its fast-tier verdict promptly,
and the skipped bench is picked up on the next idle pass rather than lost.
Check `bench.tsv` row counts per sha before and after to prove nothing partial
landed.

## Log
- 2026-08-04 (`claude@xeon`) — done alongside
  [[bug-t-bench-timings-recorded-under-co-tenancy]]; the two are the same design
  point from opposite sides (bench wants the box to itself AND must give it
  back), so they were settled together rather than one at a time.

  Bench now takes the same `make_preempted` abort-check every other idle phase
  takes, polled every 15s, and a preempting push kills the run and discards its
  rows. The one wrinkle worth recording: the abandon path returns `did_work=True`
  ONLY for a preemption, because the daemon's loop skips its sleep when work was
  done — a push must be tested immediately, while a load-skip must fall through
  to the sleep instead of spinning the cycle as fast as the CPU allows (which
  would itself be load).

- 2026-08-04 — resolved, commit 713269e96.
