---
prio: 70
---

# regression: test-c-conformance-aarch64#shard3/6 red at 90ae846bda82 (auto-filed by twatch)

- **Type:** NOT a regression — a false RED from the per-test timeout under load.
- **Status:** done — closed 2026-07-13 as a duplicate of [[bug-t-qemu-conformance-false-timeout-under-load]].
- **Found:** 2026-07-13T00:11:15Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard3/6'` at 90ae846bda8224968b0d18ea8e0fb46a7af35133

## Range
bad `90ae846bda82`, last good `90ae846bda82`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00040.c — exit code 124 (want 0)
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00040.c(exit=124)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## CLOSED 2026-07-13 — false RED, not a miscompile

Read the failure the watcher itself captured:

```
FAIL 00040.c — exit code 124 (want 0)
```

**124 is the shell's TIMEOUT status**, not a wrong answer. `run_c_conformance.sh` allows 10s
per program; `00040.c` takes **2.56 s** standalone under qemu-aarch64 on an idle box. When
the full tier saturates the machine (16 concurrent jobs, several of them qemu), that 2.56 s
stretches past 10 s and the job is killed.

Confirmed: the job PASSES on rerun, and the same tree is GREEN at `--jobs 4` with the
DEFAULT budget. The failing shard also WANDERS between runs (aarch64#1, aarch64#3,
arm32#3) — a load effect does that; a miscompile does not.

Already filed with the analysis and the fix options:
[[bug-t-qemu-conformance-false-timeout-under-load]]. Closing this one as its duplicate
rather than re-triaging the same thing under a new SHA.

**This will keep re-filing itself under a new SHA every night until the timeout is scaled by
concurrency.** That is the actual cost of leaving it: not a red square, but a steady drip of
untriaged regression tickets pointing at innocent commits. A timeout (124) should also not be
reported in the same shape as an output mismatch — it reads as a miscompile and it is not.
