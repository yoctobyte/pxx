---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance#shard2/6 at 4a8f843f2ba5 in step 2/2, `tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T05:36:00Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_c_conformance.sh`.
  ```
  tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance#shard2/6'` at 4a8f843f2ba55c41ff892867fa34d434d10f7a0b

## Range
> **The named sha `4a8f843f2ba5` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4a8f843f2ba5`, last good `fc388171aa43`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00213.c — compile error:
pascal26:156: error: invalid IR conditional jump target (label not defined)
(tail)
self-host fixedpoint: verified — 1 round(s), 8f5aa9306a71 (stamp read back; sources match it) --shard 2/6
FAIL 00213.c — compile error:
    pascal26:156: error: invalid IR conditional jump target (label not defined)
      near:       >>>  unit builtinheap 
test-c-conformance: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance: FAILURES: 00213.c(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-c-conformance#shard2/6` GREEN at 9037ea5d8471 (tier full) and did NOT close this: this is a repeat stub (`regression-test-c-conformance-shard2-6-2`, not `regression-test-c-conformance-shard2-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
