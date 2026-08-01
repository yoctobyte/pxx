---
summary: "optdiff jobs are identified by shard index, so adding one test file moves a failure to a new shard and manufactures a fresh NEW-RED + ticket"
type: bug
track: T
prio: 75
---

# optdiff shard identity is positional — one new test file re-files the same bug

- **Type:** bug (Track T watcher/testmgr job identity) — filed by `claude@borg`
  2026-08-01
- **Sibling:** [[bug-t-full-tier-wipes-other-tiers-job-status]] (they interact,
  see below)

## Evidence

Two consecutive opt runs, **the same failing program**:

| run | job reported | failure |
|---|---|---|
| 22:00:12Z `f9396231e2e1` | `optdiff#shard5/6` | `OPT DIFF -O3: test/crtl_libc_oracle.c` + segfault |
| 22:25:45Z `0ceeeaa004dc` | `optdiff#shard0/6` | `OPT DIFF -O3: test/crtl_libc_oracle.c` + segfault |

What changed between them, in full:

```
A	test/test_arr_of_ptr_elemrec_b354.pas      <- one file added
```

Adding a single test file shifted `crtl_libc_oracle.c` from shard 5 to shard 0.
The watcher saw a job it had never seen fail before and announced **NEW-RED**,
and `autoticket` filed a **second ticket for the same bug**:
`regression-optdiff-shard0-6` alongside `regression-optdiff-shard5-6`. An older
`regression-optdiff-shard4-6` exists too — so this has almost certainly happened
before and been absorbed as noise.

## It recurred twice more within the hour

| opt run | job reported | test files added since previous run |
|---|---|---|
| 22:00Z `f9396231e2e1` | `optdiff#shard5/6` | — |
| 22:25Z `0ceeeaa004dc` | `optdiff#shard0/6` | 1 (`test_arr_of_ptr_elemrec_b354.pas`) |
| 22:5xZ `d87301219197` | `optdiff#shard2/6` | 2 (`test_uses_order_pylib_exception_{a,b}.pas`) |

Same program every time — `test/crtl_libc_oracle.c` at `-O3`. **Three tickets
now exist for one bug** (`regression-optdiff-shard{0,2,5}-6`), plus the historic
`shard4-6` in `done/`. The rate is set by how often anyone adds a test file,
which on an active night is roughly every opt cycle — so this does not
self-limit, it accumulates.

## This is the exact class `job_key()` was written to prevent

From `twatch.py`:

> Not `j["name"]`: `test-core#665` is a positional index into the target's
> recipe lines, so inserting one test renumbers every job after it — and then
> this dict silently compares yesterday's #665 against a different test today,
> **manufacturing NEW-RED/FIXED pairs out of nothing**. testmgr publishes `sel`
> (`test-core#src:test/foo.pas`), which names the job by the source it compiles.

The fix was `sel`. **optdiff never got one**: its `src` is `tools/optdiff.sh`
for every shard, so `job_key()` falls back to the name — `optdiff#shard5/6` —
which is a positional index over a file list that changes whenever anyone adds
a test. Same bug, same file, still open for this job family.

## Interaction with the sibling bug

The old shard was **not** reported FIXED, because
[[bug-t-full-tier-wipes-other-tiers-job-status]] had already erased optdiff
entries from the jobs map. So the two bugs compose into: *a persistent
single-program failure that re-announces itself as new, under a rotating name,
filing a fresh ticket each time, and never closes the old one.*

## Fix direction

Give optdiff a per-file identity, so a job is named by what it tests rather than
where it landed:

- have `optdiff.sh` report the **failing source** and testmgr publish it as
  `sel` — e.g. `optdiff#src:test/crtl_libc_oracle.c` — matching what
  `test-core` already does; or
- shard by a stable hash of the filename (`hash(path) % N`) instead of position,
  so adding a file cannot move existing ones.

The first is strictly better: it survives changing `OPT_SHARDS`, and it makes a
bisect range meaningful, which a shard index never can be.

## Cleanup owed once fixed

`regression-optdiff-shard0-6` and `regression-optdiff-shard5-6` are one bug —
the `-O3` segfault on `test/crtl_libc_oracle.c`. They should be merged, not
worked twice. The underlying compiler defect is triaged in
[[regression-optdiff-shard5-6]].

---

## FIXED — `6ba5d0e9e` (claude@xeon, 2026-08-01)

Shard membership is now a **hash of the basename**, not position in the glob.

### Verified by measurement, not argument

The failure mode is "adding a test file migrates other files", so the test is:
add one file, count how many others move.

| sharding | files that change shard when ONE is added |
|---|---|
| positional (before) | **~1063** |
| hash (after) | **0** |

The partition is exact: the shards sum to 1276 with no duplicates and nothing
missing. One `awk` pass builds the list — 1276 files × NSHARD would otherwise be
thousands of forks.

### It also unblocked a 2× speedup, which is why it was worth doing now

The opt tier was structurally capped at **6-way parallelism on a 12-core box**:

```
work 1483s, wall 281s, longest single shard 280.6s
```

The wall *equalled* the longest shard — scheduling was already optimal, there
was simply nothing else to run. `OPT_SHARDS` is now 12 (84–128 programs per
shard, mean 106).

Raising it reshuffles every program, which renames jobs — exactly the phantom
NEW-RED/FIXED pair this ticket is about. Done **while the matrix was 100%
green**, so no red migrated and no phantom pair was produced. That ordering is
the whole reason the two changes shipped together, in this sequence.

`OPT_SHARDS` is deliberately a **constant, not `os.cpu_count()`**: the shard
index is part of the job name and tstate is shared between hosts, so a 12-core
box publishing `optdiff#shard0/12` against a 4-core box's `shard0/6` would make
every cross-host comparison meaningless and manufacture a NEW-RED/FIXED pair on
every handover.

### The ticket's preferred option is NOT what shipped

> **Preferred — give optdiff real selectors.** Report the failing *program*…

Not implemented. optdiff sweeps **1276 programs**, so per-program jobs would add
~1276 jobs to the tier — a real cost for identity that hash-sharding already
makes stable under the case that actually recurs (test files being added).

What the preferred option would still buy, and this remains open as an ideal: a
red would name the *program* rather than a shard, so a bisect could target one
program and autoticket could dedupe on it. Worth revisiting if optdiff failures
ever become frequent enough that "which shard" is a real triage cost. Today the
DIFF line already prints the program, so the information is in the report even
though it is not the job key.

Changing `NSHARD` still reshuffles — unavoidable for any pure function of the
name. The rule is now written into the constant: **only change it when the
matrix is green.**

## Log
- 2026-08-01 — resolved, commit 6ba5d0e9e.
