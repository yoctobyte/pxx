---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26`, which names `test/test_nilpy_c_pointer.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_c_pointer.npy at 25b8325d4b83 in step 1/2, `./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T11:23:25Z
- **Test source:** test/test_nilpy_c_pointer.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_c_pointer.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_c_pointer.npy'` at 25b8325d4b832de70e4ff573533882edd95e0dca

## Range
> **The named sha `25b8325d4b83` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `25b8325d4b83`, last good `cdae8cf6580b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: C #if: expected ':' in conditional expression
(tail)
pascal26:7: warning: #include <bits/libc-header-start.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:7: warning: #include <bits/floatn.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:7: error: C #if: expected ':' in conditional expression
  near: import stdlib >>>  p = 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
