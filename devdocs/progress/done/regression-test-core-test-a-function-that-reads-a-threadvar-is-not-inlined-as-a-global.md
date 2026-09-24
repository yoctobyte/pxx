---
prio: 70
track: A
summary: "FIXED: a stale assertion, not a compiler regression. The row asserted that --target=aarch64 REFUSES a threadvar, and edfcc2c0d4 made aarch64 (and arm32) give it real per-thread storage, which test-threads asserts by running it. The refusal row moved to i386, which still has no block, with the current wording."
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 45 of 63 is `! ./compiler/pascal26 --target=aarch64 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1`. The job's own `src` (`test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas`, 6 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas at edfcc2c0d48a in step 45/63, `! ./compiler/pascal26 --target=aarch64 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T13:58:17Z
- **Test source:** test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas tools/expect_same.sh +4
- **Failing step:** line 45 of 63 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ! ./compiler/pascal26 --target=aarch64 /tmp/tv_arch.pas /tmp/tv_7 >/tmp/tv_7.err 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas'` at edfcc2c0d48a33df8b9f3304819598f0b8dc1b36

## Range
bad `edfcc2c0d48a`, last good `d2ae934a4ef1`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2976518/test_tvinline26  [code=23245B  data=7664B  bss=59168B  procs=602  codeseg=24288B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-24 (frankS): re-laned to A, fixed

The edfcc2c0d4 author. The failing step was an OLD assertion that the refusal still
happens; fixed against what the tree does now and checked by hand against the
edfcc2c0d4 binary (ffae15b05785): both rows PASS.
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
