---
prio: 60
---

# One test-core job needs ~6.8 GB and flakes under load (the recurring `Terminated`)

- **Type:** bug (test-suite job composition / resource footprint).
  **Track A** owns the Makefile recipe; Track T filed it.
- **Found:** 2026-07-20, root-causing recurring `Terminated` kills.

## What
A single `test-core` job bundles a trivial 36-line interface test with several
deliberately enormous compiler stress tests. Measured footprint (fresh sample,
stable key, no metric blending):

```
test-core#src:test/test_interface_mainbody_ascast_temp.pas
  dur = 80.56s   mem = 7,297,589,248 (6.8 GB)
```

The recipe runs, in one job:
- `test_interface_mainbody_ascast_temp.pas` — 36 lines, 36 KB binary
- a generated body lowering to **>340k IR nodes** (`bug-pascal-ir-node-hard-limit-max-ir`)
- `test_token_growth` — 12000 procedures
- `test_sym_growth` — 20000 variables
- `test_ufield_growth` — a struct with 20000 fields
- `test_ir_overflow_large` (1.7 MB code), `test_ast_overflow_large` (3.3 MB code)

Those stress tests exist to blow past fixed compiler table caps, so the memory
is *by design*. The problem is that they share one job with an unrelated tiny
test.

## Why it matters
1. **It flakes.** On a 16 GB box with swap exhausted, a 6.8 GB job sits right at
   the edge. Under concurrent load it gets killed — the bare `Terminated` after
   a few `ok:` lines that has now been triaged at least three times
   (2026-07-18 `regression-test-core-test-interface-mainbody-ascast-temp`,
   closed 07-19 as "harness race"; again 2026-07-20 at `67e88622`). It is not a
   race in the usual sense: the job genuinely does not fit alongside other work.
2. **It serializes the whole run.** Admission correctly refuses a 6.8 GB job
   when `MemAvailable - est_mem` falls under `MEM_FLOOR`; with nothing else
   runnable the scheduler forces jobs through one at a time (degraded/serial),
   which is what a full native tier looked like for much of 2026-07-20.
3. **It is misattributed.** `extract_src()` names a job after its FIRST source,
   so all 6.8 GB is reported against the innocent 36-line interface test. Every
   ticket this has generated names the wrong test — the reason it kept being
   closed as unreproducible ("passes natively at HEAD", which it does, alone).

## Suggested fix
Split the stress tests out of this job. They are a different *class* of test
(deliberate resource exhaustion) from a semantics unit test, and they want:
- their own job(s), so the name reports what actually consumed the memory;
- ideally an exclusive/serialized resource tag, so the scheduler runs them
  alone by intent rather than by starvation;
- possibly their own class with a realistic `est_mem`, instead of inheriting
  `corpus` (1400 MB) and being learned the hard way.

## Note for whoever picks this up
Do NOT "fix" this by loosening the memory gates. The scheduler's refusal is
correct — 6.8 GB genuinely does not fit next to other jobs here. Track T
briefly mistook the scheduler's correct backpressure for a bug; see the
correction in 5db3c5b6.

Secondary, environmental: borg's 4 GB swap has been fully consumed by
long-lived desktop processes all day, so there is no cushion at all for a job
this size. Freeing swap makes the flake less likely but does not address the
job composition.

## Failure rate and what has been RULED OUT (Track T, 2026-07-20)

Observed outcomes for this job, same box, same day:

```
FAIL   33.5s
FAIL   92.0s
PASS  177.8s     <- the only pass; ran alone in degraded/serial mode
FAIL  100.4s
```

It needs ~178s uninterrupted and is killed before finishing most runs. The
job log always ends the same way — three `ok:` compiles, then a bare
`Terminated` (SIGTERM), at the point the recipe moves on to the 12000-proc
token-growth test.

**Ruled out** (checked, not assumed):
- **Not the OOM killer.** `memory.events` on the user slice reports
  `oom_kill 0`, `oom_group_kill 0`. Nothing has been OOM-killed.
- **Not testmgr's memory watchdog.** It has never fired on this box
  (0 occurrences in the daemon log), and it returns early when
  `len(self.running) <= 1`, so a job running alone can never be its victim.
- **Not a timeout.** The job's class is `corpus` (1200s) and it has no
  learned `exp_dur` yet, so the class timeout applies. Failures at 33–100s
  are nowhere near it, and no "timed out" line is ever logged.
- **Not a `/tmp` collision between checkouts.** `RUN_TMP` is
  `/tmp/testmgr-scratch-<pid>`, and recipes' literal `/tmp/` paths are
  rewritten into it per run, so concurrent runs cannot share those files.

**Relevant context:** this box runs at least two testmgr instances
concurrently — the Track T watcher out of `~/trackt-watch`, and a second
clone of this repo at `~/frankonpiler` (Track N/NilPy work) running
`--tier quick` gates. Plus a desktop session holding ~4 GB of swap. So real
concurrent memory pressure exists even though nothing is OOM-killing.

**Still unexplained:** what actually sends the SIGTERM. Whoever picks this
up should start there rather than re-deriving the above. Splitting the
stress tests into their own job (main suggestion) very likely makes the
question moot, since the job would stop being a 6.8 GB / 178s outlier.

## ROOT CAUSE FOUND — it is a compiler bug, not "big by design" (2026-07-20)

`bug-a-token-growth-test-is-slow-and-times-out` measured the token-growth
test's scaling curve and found **peak RSS quadratic in PROCEDURE COUNT**:

| n procs | wall | peak RSS |
| --- | --- | --- |
| 1500 | 0.58s | 103 MB |
| 3000 | 2.55s | 436 MB |
| 6000 | 13.0s | 1743 MB |
| 12000 | 67.6s | 4484 MB |

The recipe's token-growth step uses **12000 procedures** — so ~4.5 GB and ~68s
of this job's ~6.8 GB / ~178s is that one step, and it is a genuine defect
(~100 bytes allocated per already-registered proc, per body compiled), not the
test being legitimately large.

**This supersedes the framing above.** The chain is:

```
quadratic per-body allocation (compiler bug)
  -> 12000-proc token-growth step costs 4.5 GB / 68s
  -> the whole job costs 6.8 GB / 178s (est_mem 9.7 GB with the 1.4x factor)
  -> cannot pass admission on a 16 GB box -> 90s starvation tax every run
  -> forced through serially, killed before finishing -> intermittent RED
```

So fixing `bug-a-token-growth-test-is-slow-and-times-out` very likely dissolves
this ticket entirely: the flake, the per-run starvation tax, and the
unexplained SIGTERM together. **Fix that first; splitting the job is the
fallback if the quadratic behaviour turns out to be hard to remove.**

Splitting still has independent merit (a job should not be named after an
unrelated 36-line test — see the `extract_src` note above), but it is no longer
the primary recommendation.

## Log
- 2026-07-22 — resolved, commit 06219176.
