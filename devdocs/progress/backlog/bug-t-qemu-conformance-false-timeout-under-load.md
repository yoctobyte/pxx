---
prio: 55
---

# c-conformance cross shards false-RED on a 10s per-test timeout under full load

- **Type:** bug (test infra — false RED, wastes a bisect)
- **Track:** T — testing infra (`tools/run_c_conformance.sh`)
- **Status:** backlog — opened 2026-07-13.
- **Found by:** a Track A/C session whose own full-tier runs had just been GREEN four
  times in a row.

## Symptom
`tools/testmgr.py --tier full` intermittently reports ONE failing
`test-c-conformance-<cross-target>#shard<N>` with **exit code 124** — the shell's
timeout status, not a test failure. The shard that fails MOVES between runs
(observed: aarch64 shard1, then aarch64 shard3), and every shard passes when run on
its own.

That moving target is the tell: a real miscompile does not wander between shards.

## Root cause
`run_c_conformance.sh` sets a per-program budget of **10 seconds**:

```sh
TIMEOUT_S="$(awk -v s="${TESTMGR_TIME_SCALE:-1}" 'BEGIN { t=10*s; ... }')"
```

Some c-testsuite programs are genuinely slow under qemu — `00040.c` on aarch64 takes
**2.56 s** standalone on an unloaded box. When the full tier saturates the machine
(16 concurrent jobs, several of them qemu), that 2.56 s stretches past 10 s and the
job is killed.

Proof: the same tree is `1203/1203 GREEN` with `TESTMGR_TIME_SCALE=4`, and RED at the
default scale — with no code change in between.

## Why it matters
This is a **false RED on a green tree**. tstate publishes it as a regression against
whatever SHA happened to be current, so the next agent bisects a bug that does not
exist. (This session already hit the sibling trap: seven real regressions had been
attributed to a prose-only ticket commit.) Cf.
[[project_borg_red_harness_race_not_regression]].

## Shape of the fix (Track T's call)
The budget is per-PROGRAM but the pressure is per-MACHINE, so scaling only by
hardware calibration misses it. Options:
- give qemu/cross targets a larger base budget than native (they are ~10-30x slower);
- scale the budget by the actual job concurrency, not just TESTMGR_TIME_SCALE;
- or retry a timed-out program once, serially, before calling it a failure — cheap,
  and it distinguishes "slow under load" from "hangs" exactly.

Whatever the fix: a timeout (124) should not be reported as an output/correctness
failure. It reads as a miscompile in the report and it is not one.

## Repro — and the decisive one
```
tools/testmgr.py --tier full                      # RED, ONE cross shard, exit 124
tools/testmgr.py --tier full --job '<that shard>' # PASS alone
TESTMGR_TIME_SCALE=8 tools/testmgr.py --tier full # still RED sometimes (load-dependent)
tools/testmgr.py --tier full --jobs 4             # GREEN, 1205/1205, DEFAULT timeout
```
The last line is the one that settles it: at low concurrency the SAME tree passes with
the SAME 10s budget. So the budget is not too small in absolute terms — it is too small
*for the concurrency the tier itself creates*. Raising TESTMGR_TIME_SCALE only papers
over it (and on a loaded box even scale 8 still tripped), because the pressure scales
with the job count, not with the hardware.

That points at the fix: derive the per-program budget from the ACTUAL concurrency cap
(or retry a timed-out program once, serially). Observed failing shards across runs:
aarch64#shard1, aarch64#shard3, arm32#shard3 — it wanders, as a load effect does and a
miscompile does not.

## Log
- 2026-07-13 — opened by a Track A/C session; not fixed here (Track T owns
  `run_c_conformance.sh` and the report format).
