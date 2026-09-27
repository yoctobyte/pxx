---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 47 of 70 is `! ./compiler/pascal26 --target=i386 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1`. The job's own `src` (`test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas`, 7 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas at 80e96e1c23cf in step 47/70, `! ./compiler/pascal26 --target=i386 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T21:19:44Z
- **Test source:** test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas tools/expect_same.sh +5
- **Failing step:** line 47 of 70 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ! ./compiler/pascal26 --target=i386 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas'` at 80e96e1c23cf7782f2f6c4d587c581f9794cfb69

## Range
> **The named sha `80e96e1c23cf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `80e96e1c23cf`, last good `98facdd35ac7`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1202493/test_tvinline26  [code=23451B  data=7704B  bss=62240B  procs=609  codeseg=24288B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
