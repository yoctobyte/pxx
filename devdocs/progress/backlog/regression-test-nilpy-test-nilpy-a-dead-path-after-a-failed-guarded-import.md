---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 14 of 24 is `out=$(./compiler/pascal26 /tmp/nilpy_deadctl_hit.npy /tmp/test_nilpy_deadhit26 2>&1); \ rc=$?; \ test "$rc" = "1" \ && p`. The job's own `src` (`test/test_nilpy_a_dead_path_after_a_failed_guarded_import.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_a_dead_path_after_a_failed_guarded_import.npy at c3e2fbfaa1ae in step 14/24, `out=$(./compiler/pascal26 /tmp/nilpy_deadctl_hit.npy /tmp/test_nilpy_deadhit26 2>&1); \ rc=$?; \ test "$rc" = "1" \ && …` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-25T17:48:11Z
- **Test source:** test/test_nilpy_a_dead_path_after_a_failed_guarded_import.npy tools/expect_same.sh
- **Failing step:** line 14 of 24 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  out=$(./compiler/pascal26 /tmp/nilpy_deadctl_hit.npy /tmp/test_nilpy_deadhit26 2>&1); \ rc=$?; \ test "$rc" = "1" \ && printf '%s\n' "$out" | grep -q 'no unit named also_no_such_module_9f2a' \ || { echo "test_nilpy_dead_path_control_guard_resolves: FAIL - rc=$rc (want 1: the guarded import RESOLVED,
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_a_dead_path_after_a_failed_guarded_import.npy'` at c3e2fbfaa1ae2490e7a7a890cc6a6e1c7fe25bcb

## Range
> **The named sha `c3e2fbfaa1ae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c3e2fbfaa1ae`, last good `1ab5960d4d65`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1691133/test_nilpy_deadimp26  [code=416878B  data=103845B  bss=65564B  procs=2519  codeseg=417504B]
test_nilpy_dead_path_control_guard_resolves: FAIL - rc=0 (want 1: the guarded import RESOLVED, so the tail is the live branch and its missing import must still be an error)
pascal26:6: warning: import: no module named also_no_such_module_9f2a -- this function raises ModuleNotFoundError when it reaches the import
ok: /tmp/testmgr-scratch-1691133/test_nilpy_deadhit26  [code=372604B  data=103176B  bss=65380B  procs=2515  codeseg=376544B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
