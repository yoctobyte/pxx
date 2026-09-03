---
prio: 70
track: A
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"`. The job's own `src` (`test/test_nilpy_thread_clone.npy`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_nilpy_thread_clone.npy at 08f7de0715a8 in step 2/6, `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T16:04:12Z
- **Test source:** test/test_nilpy_thread_clone.npy tools/expect_same.sh +2
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_nilpy_thread_clone.npy'` at 08f7de0715a8a9cf5f2e739231b7ac7d2b18177f

## Range
> **The named sha `08f7de0715a8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `08f7de0715a8`, last good `8476a5157557`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2784241/test_npy_clone26  [code=1347352B  data=77376B  bss=51404B  procs=1928]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_npy_clone26]
--- expected
+++ actual
@@ -1,2 +1 @@
 tid nonzero = True
-child ran = 7

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 5ad048c2d9ae (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 9cf9771387c6 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 72184098b614 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at afbc83e5a976 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 7fff15ddc1eb (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 88807c8258fe (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 7c32e3fee9ce (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at c8375f3e76e9 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.


## NOT A REGRESSION — measured on the pin, 2026-09-02 22:2x (frankuser)

**It fails at the same rate on a compiler that predates every commit in the
range, so no bisect of that range can find it.** Interleaved A/B, 45 runs each,
same host, same minute, alternating to control for load:

| binary | commit | failed |
| --- | --- | --- |
| tip `a81084690bac` | `ba90811d3` | **1/45** |
| pinned `1eec4dc5e0a7` | pin v399, predates the range | **1/45** |

Built both with `--threadsafe` (the test refuses without it) from
`test/test_nilpy_thread_clone.npy`; failures are SIGSEGV (rc=139), and the
crash lands **before the first line finishes printing** — output truncates at
`tid nonzero =`.

**So this is a rare intermittent in thread startup, roughly 2%, not a defect
introduced by anything in the bisect range.** Tonight it was re-filed as
`NEW-RED` against `51b80e55be90`, a **docs-only** commit, and the only
compiler-touching files in that 21-commit range were `compiler/ir.inc` and
`compiler/symtab.inc` — the frozen-string fix, which is innocent here. Two
separate auto-filings (16:04 and 20:07) at unrelated shas is itself the
signature of an intermittent rather than a regression.

**Why a single-run watcher cannot see this.** At ~2%, one run per sha passes 49
times in 50, so the test reads as green until it doesn't, and whichever sha
happens to catch it gets blamed. `flaky: 0` in the report means *not classified*
flaky, not *measured* not-flaky.

**Re-laned T → A.** The ticket's own header says the T tag is a fallback because
the failing step named no owner; a SIGSEGV in cloned-thread startup is Track A.
Plausibly related: `feature-a-tls-stack-bounds-for-cloned-threads` and
`bug-a-test-tthread-fails-under-full-tier-load-but-never-in-isolation` — that
last one is the same shape (a threads test failing only under load).

**The bug is real; only the attribution was wrong.** ~2% of `__pxxclone` starts
segfault before the parent completes a write.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 26db8523e829 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at c23dcf1cfd42 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at cd694bdc4de9 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-03 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at a24a521145b0 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
