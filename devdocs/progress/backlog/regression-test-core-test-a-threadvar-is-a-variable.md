---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 29 of 57 is `grep -q 'only ordinal, pointer and floating-point threadvars' /tmp/tv_4.err`. The job's own `src` (`test/test_a_threadvar_is_a_variable.pas`, 6 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_threadvar_is_a_variable.pas at 59afeadbceaa in step 29/57, `grep -q 'only ordinal, pointer and floating-point threadvars' /tmp/tv_4.err` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T08:51:39Z
- **Test source:** test/test_a_threadvar_is_a_variable.pas tools/expect_same.sh +4
- **Failing step:** line 29 of 57 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  grep -q 'only ordinal, pointer and floating-point threadvars' /tmp/tv_4.err
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_threadvar_is_a_variable.pas'` at 59afeadbceaa89554256c49780729285f94080fd

## Range
> **The named sha `59afeadbceaa` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `59afeadbceaa`, last good `16b33723f41f`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2021481/test_threadvar_var26  [code=331544B  data=34788B  bss=88148B  procs=874]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
