---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 13 is `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ too`. The job's own `src` (`test/test_threadsafe_heap_lock_deadlock_diag.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_threadsafe_heap_lock_deadlock_diag`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas at aa43f495ab87 in step 2/13, `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ to…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T00:36:34Z
- **Test source:** test/test_threadsafe_heap_lock_deadlock_diag.pas tools/expect_same.sh
- **Failing step:** line 2 of 13 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ tools/expect_same.sh test_ts_hl_diag26_control "$(printf '%s\n' "$out" | sed -n 1p)" "contention-workers-finished=12" && \ tools/expect_same.sh test_ts_hl_diag26_named "$(printf '%s\n
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas'` at aa43f495ab8788a6f3fbef0485a902310cf29d7c

## Range
bad `aa43f495ab87`, last good `1e3e9a0b95d0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2383160/test_ts_hl_diag26  [code=179992B  data=9664B  bss=55676B  procs=640]
expect_same: MISMATCH [test_ts_hl_diag26_exit]
--- expected
+++ actual
@@ -1 +1 @@
-212
+124

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 369f962af9e5 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 8eec0021138c (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at b44571a727b2 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at cf374e381b5d (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at accb99f3c59b (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 1fa5bc5e334c (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at f09f6bcde929 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 582545aef690 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at a2861701f1a0 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 32a0a421a292 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 2dc0d6878b27 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at f7a745e876ef (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
