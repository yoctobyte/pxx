---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 36 of 63 is `grep -q 'error: __thread counter: the per-thread variable area is full' /tmp/ctls_full.log || { echo "FAIL ctls: area-fu`. The job's own `src` (`test/c_thread_local_is_per_thread.c`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_thread_local_is_per_thread.c at 5e9c8da7481e in step 36/63, `grep -q 'error: __thread counter: the per-thread variable area is full' /tmp/ctls_full.log || { echo "FAIL ctls: area-f…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T10:43:37Z
- **Test source:** test/c_thread_local_is_per_thread.c test/c_errno_is_per_thread.c +2
- **Failing step:** line 36 of 63 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  grep -q 'error: __thread counter: the per-thread variable area is full' /tmp/ctls_full.log || { echo "FAIL ctls: area-full did not report as an error naming the declaration"; cat /tmp/ctls_full.log; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_thread_local_is_per_thread.c'` at 5e9c8da7481e6e9e62afed990d1847f1c7d91588

## Range
> **The named sha `5e9c8da7481e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5e9c8da7481e`, last good `2f7bee67cc0a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
(tail)
ok: /tmp/testmgr-scratch-418715/c_thread_local26  [code=362537B  data=15808B  bss=92476B  procs=992  codeseg=364256B]
ok: /tmp/testmgr-scratch-418715/c_errno_per_thread26  [code=361545B  data=15776B  bss=92420B  procs=993  codeseg=364256B]
FAIL ctls: area-full did not report as an error naming the declaration
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
  in: /tmp/testmgr-scratch-418715/compiler/../lib/crtl/include/errno.h
  near: extern __thread  errno >>>  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
