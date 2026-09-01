---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 53 of 47 is `/tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"`. The job's own `src` (`test/test_exception_unhandled.pas`, 13 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_exception_unhandled.pas@3 at f9e495823dce in step 53/47, `/tmp/next-test_multithreading26 | grep -q "multithreadin` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T17:49:05Z
- **Test source:** test/test_exception_unhandled.pas compiler/compiler.pas +11
- **Failing step:** line 53 of 47 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  /tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_exception_unhandled.pas@3'` at f9e495823dcec87ce8840b5a11d61f7c4b9ac7d9

## Range
bad `f9e495823dce`, last good `5d983997a05a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
134]
ok: /tmp/testmgr-scratch-1182204/self-records26  [code=69400B  data=2792B  bss=43540B  procs=134]
ok: /tmp/testmgr-scratch-1182204/self-procs26  [code=69400B  data=2888B  bss=43496B  procs=137]
ok: /tmp/testmgr-scratch-1182204/self-string_compare26  [code=69400B  data=2960B  bss=43500B  procs=136]
ok: /tmp/testmgr-scratch-1182204/self_record_string_field26  [code=69400B  data=2900B  bss=43524B  procs=135]
ok: /tmp/testmgr-scratch-1182204/self-test_heap26  [code=69400B  data=2792B  bss=43504B  procs=134]
ok: /tmp/testmgr-scratch-1182204/self-test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
ok: /tmp/testmgr-scratch-1182204/self-test_math_unit26  [code=224936B  data=6648B  bss=43576B  procs=665]
ok: /tmp/testmgr-scratch-1182204/self-fileio26  [code=110360B  data=5032B  bss=43788B  procs=248]
pascal26:5675: warning: bare own name 'TargetDisplayName' reads the result of parameterless function TargetDisplayName; write TargetDisplayName() for a recursive call, or Result to read the result
ok: /tmp/testmgr-scratch-1182204/pascal26-next.1183106.tmp  [code=9768728B  data=478392B  bss=103282260B  procs=3932]
ok: /tmp/testmgr-scratch-1182204/next-hello26  [code=65304B  data=2840B  bss=43492B  procs=134]
ok: /tmp/testmgr-scratch-1182204/next-bootstrap_features26  [code=69400B  data=2920B  bss=43508B  procs=134]
ok: /tmp/testmgr-scratch-1182204/next-records26  [code=69400B  data=2792B  bss=43540B  procs=134]
ok: /tmp/testmgr-scratch-1182204/next-procs26  [code=69400B  data=2888B  bss=43496B  procs=137]
ok: /tmp/testmgr-scratch-1182204/next-string_compare26  [code=69400B  data=2960B  bss=43500B  procs=136]
ok: /tmp/testmgr-scratch-1182204/next_record_string_field26  [code=69400B  data=2900B  bss=43524B  procs=135]
ok: /tmp/testmgr-scratch-1182204/next-test_heap26  [code=69400B  data=2792B  bss=43504B  procs=134]
ok: /tmp/testmgr-scratch-1182204/next-test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 370170edaffe (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 5cf6d533b9ed (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 23f98b550f03 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 673fee7c2bd7 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 039be8b4aa97 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-01 — the seven watcher saw `test-core#src:test/test_exception_unhandled.pas@3` GREEN at 9ea2dbbd05fe (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-exception-unhandled-2`, not `regression-test-core-test-exception-unhandled`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## VERIFIED FIXED 2026-09-01 (frankC) — no longer reproduces at HEAD

Swept as part of "which of the 12 open auto-filed regressions still
reproduce?". Re-ran this ticket's OWN job recipe at `2d9878ac8`, compiler
`6afb21f66d10` (built from the pin, self-host fixedpoint converged):

```
PXX_ALLOW_FULL_SUITE=1 tools/testmgr.py --tier native --job 'test-core#src:test/test_exception_unhandled.pas@3'
```

**GREEN, twice.** Run a second time deliberately: a single green run on a
regression that may be intermittent proves nothing, and this test's population
includes at least one known race. Two independent runs, both green.

**Cause NOT bisected, and this ticket does not claim one.** It no longer
reproduces; which commit fixed it is unestablished. Recorded that way on purpose
— an invented cause is worse than an absent one, and the bisect range in this
ticket dates the window it was FILED in, not the window it was fixed in.
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
