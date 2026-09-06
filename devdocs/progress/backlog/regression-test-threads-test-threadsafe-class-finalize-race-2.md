---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_tscfr26 "$(/tmp/test_tscfr26)" "$(printf 'errors=0\nRACE OK')"`. The job's own `src` (`test/test_threadsafe_class_finalize_race.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_class_finalize_race.pas at e678b743d3bb in step 2/2, `tools/expect_same.sh test_tscfr26 "$(/tmp/test_tscfr26)" "$(printf 'errors=0\nRACE OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T13:07:03Z
- **Test source:** test/test_threadsafe_class_finalize_race.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_tscfr26 "$(/tmp/test_tscfr26)" "$(printf 'errors=0\nRACE OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_threadsafe_class_finalize_race.pas'` at e678b743d3bb472df6f8266723925cef6eadf1d3

## Range
> **The named sha `e678b743d3bb` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e678b743d3bb`, last good `918842a5fd43`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1292648/test_tscfr26  [code=175896B  data=9076B  bss=52020B  procs=613]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_tscfr26]
--- expected
+++ actual
@@ -1,2 +1 @@
-errors=0
-RACE OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
