---
summary: "twatch publishes only when a whole tier finishes, so a self-host fixedpoint break — the one red that blocks every track — waits behind the entire native tier before anyone hears about it"
type: feature
track: T
prio: 75
---

# Run the self-host fixedpoint first and publish its RED immediately

- **Type:** feature (Track T, turnaround latency) — **Track T**
- **Opened:** 2026-08-01. Filed from A+P+C+N as part of a deliberate shift:
  dev tracks stop running suites locally and rely on T for breadth, so **T's
  report latency becomes the dev loop's latency**. Fast reports are now the
  product.

## Measured today (why this matters more than it used to)

| step | time |
| --- | --- |
| one self-compile | **5.74 s** |
| `make compiler/pascal26` (build + byte-identical verify = the fixedpoint) | **~12 s** |
| `testmgr --tier quick` | 2–14 s |
| `make test-nilpy` | **554 s** |

The dev loop is becoming: build (12s) → run the repro (~1s) → push. At that
cadence an agent can land several commits before T says anything, so the cost of
a late report is now measured in *commits to unwind*, not minutes.

## Current behaviour

`twatch.test_sha()` calls `run_gate()`, which runs **an entire testmgr tier** and
only then gets `--report-json` back; publication (`write_report_md` + `publish`)
and `file_stub_tickets` all happen after that returns. There is a fast phase
already (`fast_tier: "native"` then `tier: "full"`), but the granularity is still
one whole tier.

So the self-host fixedpoint — which testmgr does carry as its own job class
(`selfhost`, `CLASS_WEIGHT` 60) — is reported at the same time as everything
else in its tier, despite being the one result that invalidates every other
track's ground.

## Asked for

1. **Schedule the `selfhost` job first** within any tier that carries it.
2. **On self-host failure, publish immediately** — write the tstate RED and file
   the ticket without waiting for the rest of the tier — and ideally abort the
   remainder of that tier, since every other verdict at that sha is suspect
   anyway.
3. Keep the existing end-of-tier publish for everything else.

A `phase`/heartbeat marker for "self-host RED at <sha>" would let an agent-side
watcher (see [[feature-t-agent-side-tstate-watch]]) surface it within a poll
interval instead of a cycle.

## Why self-host specifically, and not "publish every job as it lands"

Per-job publishing would push a commit per job and thrash the tstate history —
`twatch`'s own publish path already has hard-won conflict/rebase handling
(`_drop_to_origin`, the stranded-commit incident at ~line 300) that gets harder
the more often it runs. Self-host is the one job whose failure means *stop and
look now*; the rest can keep batching.

## Gate

Break the self-host fixedpoint deliberately, push, and confirm the tstate RED and
the ticket appear without waiting for the tier to finish — and that a
green self-host leaves current timing unchanged.
