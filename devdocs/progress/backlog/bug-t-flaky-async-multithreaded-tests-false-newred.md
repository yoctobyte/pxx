---
summary: "Flaky async/multithreaded run-tests emit false NEW-REDs — reap() fails on first nonzero exit, no confirm-retry"
type: bug
prio: 45
---

# Flaky async/multithreaded run-tests produce false NEW-REDs (no confirm-retry in reap())

- **Type:** bug (Track T — the harness/tooling; `tools/testmgr.py`). Not a compiler
  bug: the tests pass on re-run, so there is nothing to fix in the owning lane. The
  defect is that the harness turns a *transient* failure into a *permanent* verdict.
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-17, from a tstate recheck. `twatch --status` showed a NEW-RED
  `test-aarch64#src:test/test_asyncecho.pas` pinned to SHA `88986014` — a commit that
  touched **only** `tools/pasmith.py` + the fuzz `LEDGER.json`, i.e. structurally
  incapable of regressing an aarch64 async test. Re-ran the exact repro
  (`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_asyncecho.pas'`)
  **3× → 3× PASS** (0.5s each). Transient QEMU flake, not a regression.
- **Related:** [[bug-t-qemu-conformance-false-timeout-under-load]],
  [[regression-testmgr-conformance-shard-timeout-under-load]],
  [[bug-testmgr-aarch64-conformance-shard3-timeout-flake]],
  [[bug-lib-test-console-solitaire-flaky]] — the *timeout*-under-load flake class,
  already hardened. This is the sibling **exit-code** flake class for async/threaded
  run-tests, which those fixes did not cover.

## Symptom

`tstate`/borg intermittently reports `0-in-range` NEW-REDs for **async / multithreaded
run-tests under QEMU**, always self-clearing on the next tick:

- `test-aarch64#src:test/test_asyncecho.pas` — verified flaky here (3/3 PASS on re-run)
- `test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh` — STILL-RED,
  0-in-range, same profile (threaded sqlite under QEMU)
- `optdiff#shard4/6` — 0-in-range, same profile

`0-in-range` (empty bisect window) + self-clearing + a run-test whose *compile* step is
`ok:` and whose *runtime* is async/threaded under emulation is the signature of a
scheduling/timing race in the emulated run, not a code defect.

## Root cause

`Scheduler.reap()` (`tools/testmgr.py:965`) sets the verdict on the **first** process
exit, with no retry:

```python
rc = job.proc.poll()
if rc is not None:
    job.status = "pass" if rc == 0 else "fail"   # one shot — a single transient
                                                 # nonzero exit is permanent
```

The **bench** path already knows better: `BENCH_EXTRA_TRIES = 5`
(`tools/testmgr.py:1408`) re-runs a bench that lost its sample to contention. Regular
pass/fail run-tests get **no** equivalent — so a job that spuriously exits nonzero once
(descheduled thread, socket timing, QEMU scheduling jitter under a loaded full-matrix
run) is declared RED, turns the whole run RED, and lands in `tstate` as a NEW-RED tied
to whatever SHA happened to be under test. Triage cost is real even though it
self-clears: every false NEW-RED is a bisect + a manual re-run + this exact
investigation.

## Fix direction (decide at pickup — do not mask real reds)

The invariant to preserve: **a real red must stay red.** A genuine failure reproduces
every attempt; only a flake passes on retry. So confirm-on-failure is safe by
construction — it costs re-runs only on jobs that were going to be RED anyway.

1. **Confirm-retry a failing run-test before declaring RED** (preferred, narrow). On a
   nonzero exit, re-run *that one job* up to N times (N≈2–3); RED only if it fails
   every attempt; PASS the moment one attempt passes. Cheap — retries fire only on the
   already-failing minority, and a real red pays N× on one job, not on the suite. This
   is the exit-code analogue of `BENCH_EXTRA_TRIES`.
2. **Tag known-nondeterministic jobs** (`asyncecho`, `sqlite-threads-*`, `optdiff`
   shards) as flake-prone and apply the retry only to them — smaller blast radius, but
   needs a maintained list and misses the next new async test.
3. **Report `flaky` as a distinct verdict** (retried, passed-on-retry) so `tstate`
   records "flaked+recovered" instead of either hiding it or crying RED — keeps the
   signal without the false alarm. Compose with (1).

Recommendation: **(1) + (3)** — confirm-retry for correctness, a `flaky` verdict so the
noise is still *visible* (a test that flakes 1-in-3 is worth knowing about) without
being *actionable-red*. Keep it general (all run-tests), not a hand-maintained tag list.

## Non-goals

- **Not** raising per-test timeouts (that's the *timeout* flake class, already handled
  by the related tickets). This is about **nonzero-exit** transients.
- **Not** silencing the tests. A job that flakes >50% of runs is a genuine test-quality
  problem and should surface (the `flaky` verdict is exactly so it can).
- **Not** touching the compiler/RTL. If confirm-retry ever shows a job failing *every*
  attempt, that's a real bug → file into the owning lane (async/threading runtime →
  Track A), not here.

## Acceptance

- A run-test that exits nonzero once but passes on re-run is reported **green (or
  `flaky`)**, not RED, and does not create a `tstate` NEW-RED.
- A run-test that fails **every** retry is still RED (real reds preserved — verify with
  a deliberately-broken test).
- `test-aarch64#asyncecho` and `test-sqlite-threads-aarch64` stop generating
  0-in-range NEW-REDs across a few full-matrix ticks.
- Gate: `tools/testmgr.py --tier full` green; exercise the retry path with a scratch
  test that fails once then passes.

## Log
- 2026-07-17 — filed. Found during a tstate recheck: asyncecho NEW-RED on a
  compiler-inert SHA, 3/3 PASS on manual re-run. Root-caused to `reap()`'s
  first-exit-is-final verdict vs the bench path's `BENCH_EXTRA_TRIES` retry. T owns the
  harness, so this is a T bug (the false NEW-RED is a *tooling* artifact); the async
  tests themselves are not broken.
