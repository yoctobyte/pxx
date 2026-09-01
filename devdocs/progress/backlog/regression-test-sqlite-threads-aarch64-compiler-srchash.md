---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_sqlite_thread_test.sh aarch64 ./compiler/pascal26 library_candidates/sqlite`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 15 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh at fc9139c264df in step 2/2, `tools/run_sqlite_thread_test.sh aarch64 ./compiler/pasca` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T14:21:18Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_sqlite_thread_test.sh`.
  ```
  tools/run_sqlite_thread_test.sh aarch64 ./compiler/pascal26 library_candidates/sqlite
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh'` at fc9139c264df5ee5023b903fc8b5856dcfb33126

## Range
> **The named sha `fc9139c264df` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fc9139c264df`, last good `04f5b94624b3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
self-host fixedpoint: verified — 1 round(s), f1636ca270a8 (stamp read back; sources match it)
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: /tmp/testmgr-scratch-3561145/cstt_aarch64.u1xvFf/csqlite_thread_test26_aarch64  [code=7208728B  data=84504B  bss=118128B  procs=4398]
test-sqlite-threads: FAIL aarch64 (TIMED OUT after 200s; TESTMGR_TIME_SCALE=1.00 TESTMGR_LOAD_SCALE=2.00 cap=200s)
  partial output: []

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — the seven watcher saw `test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh` GREEN at 46dddae58485 (tier full) and did NOT close this: the job FAILED and passed on a retry in this very run, so this green is the race firing rather than evidence against it. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
