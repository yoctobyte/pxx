---
prio: 70
track: A
summary: "FIXED: a stale assertion, not a compiler regression. edfcc2c0d4 reworded the thread-local target refusal to 'needs a per-thread block' when aarch64/arm32 gained a block; the riscv32 row still grepped the old 'is x86-64 only' text. riscv32 still degrades and warns. The row now greps the wording from TryAssignThreadVarStorage."
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 70 of 76 is `grep -q 'warning: __thread is x86-64 only' /tmp/ctls_rv.log || { echo "FAIL ctls: riscv32 degraded SILENTLY -- no warnin`. The job's own `src` (`test/c_thread_local_is_per_thread.c`, 5 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_thread_local_is_per_thread.c at edfcc2c0d48a in step 70/76, `grep -q 'warning: __thread is x86-64 only' /tmp/ctls_rv.log || { echo "FAIL ctls: riscv32 degraded SILENTLY -- no warni…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T13:58:17Z
- **Test source:** test/c_thread_local_is_per_thread.c test/c_errno_is_per_thread.c +3
- **Failing step:** line 70 of 76 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  grep -q 'warning: __thread is x86-64 only' /tmp/ctls_rv.log || { echo "FAIL ctls: riscv32 degraded SILENTLY -- no warning"; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_thread_local_is_per_thread.c'` at edfcc2c0d48a33df8b9f3304819598f0b8dc1b36

## Range
bad `edfcc2c0d48a`, last good `d2ae934a4ef1`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2976518/c_thread_local26  [code=72747B  data=15808B  bss=92484B  procs=1005  codeseg=73440B]
ok: /tmp/testmgr-scratch-2976518/c_errno_per_thread26  [code=73053B  data=15776B  bss=92428B  procs=1006  codeseg=73440B]
FAIL ctls: riscv32 degraded SILENTLY -- no warning

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-24 (frankS): re-laned to A, fixed

The edfcc2c0d4 author. The failing step was an OLD assertion that the refusal still
happens; fixed against what the tree does now and checked by hand against the
edfcc2c0d4 binary (ffae15b05785): both rows PASS.
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
