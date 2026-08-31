---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"`. The job's own `src` (`test/test_setlen_in_parallel_for_body.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_setlen_in_parallel_for_body.pas at 456361785e34 in step 2/2, `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_s` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T06:26:52Z
- **Test source:** test/test_setlen_in_parallel_for_body.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_setlen_in_parallel_for_body.pas'` at 456361785e3489b2a7ddd800bc216b5ec2bbe51f

## Range
> **The named sha `456361785e34` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `456361785e34`, last good `d28b77ce5d88`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2782012/test_setlen_parfor26  [code=126744B  data=5728B  bss=42612B  procs=277]
expect_same: MISMATCH [test_setlen_parfor26]
--- expected
+++ actual
@@ -1 +1 @@
-PARALLEL SETLEN OK total=8000
+PARALLEL SETLEN OK total=7944

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at d7aad6cd14a3 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 373deddb700b (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at d74c7fbe9ffe (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at afb7aa9da9c9 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 2812ffacbe69 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at b8f7e6f2bb11 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 86126be99600 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
