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
