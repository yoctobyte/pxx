---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 15 is `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"`. The job's own `src` (`test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas at af0e5a0ad099 in step 2/15, `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T14:40:10Z
- **Test source:** test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas tools/expect_same.sh
- **Failing step:** line 2 of 15 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas'` at af0e5a0ad09916b0563d12739a9410322bbc7611

## Range
> **The named sha `af0e5a0ad099` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `af0e5a0ad099`, last good `15de9cd799fd`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2533959/test_bracketdoor26  [code=339736B  data=35120B  bss=88452B  procs=881]
expect_same: MISMATCH [test_bracketdoor26]
--- expected
+++ actual
@@ -1,2 +1,2 @@
-fails=0
-BRACKETDOOR OK
+FAIL constructor, open array of scalar: got 10 want 60
+fails=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
