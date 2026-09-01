---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_exception_threads_race26 "$(/tmp/test_exception_threads_race26)" "$(printf 'single hits=200000`. The job's own `src` (`test/test_exception_threads_race.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_exception_threads_race.pas at e7be39f9a505 in step 2/4, `tools/expect_same.sh test_exception_threads_race26 "$(/t` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T13:27:20Z
- **Test source:** test/test_exception_threads_race.pas tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_exception_threads_race26 "$(/tmp/test_exception_threads_race26)" "$(printf 'single hits=200000 wrong=0\ntwo hitsA=200000 hitsB=200000 wrongA=0 wrongB=0')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_exception_threads_race.pas'` at e7be39f9a505ba97da11cc237b26d13585cc3d7b

## Range
> **The named sha `e7be39f9a505` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e7be39f9a505`, last good `62e176c3c4e5`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3200146/test_exception_threads_race26  [code=81688B  data=6312B  bss=42628B  procs=194]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_exception_threads_race26]
--- expected
+++ actual
@@ -1,2 +1 @@
-single hits=200000 wrong=0
-two hitsA=200000 hitsB=200000 wrongA=0 wrongB=0
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
