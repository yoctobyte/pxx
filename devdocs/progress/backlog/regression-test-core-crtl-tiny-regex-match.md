---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh crtl_tiny_regex_match26 "$(/tmp/crtl_tiny_regex_match26)" "tiny-regex: all cases pass"`. The job's own `src` (`test/crtl_tiny_regex_match.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/crtl_tiny_regex_match.c at 6e622be95680 in step 2/2, `tools/expect_same.sh crtl_tiny_regex_match26 "$(/tmp/crt` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T08:20:54Z
- **Test source:** test/crtl_tiny_regex_match.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh crtl_tiny_regex_match26 "$(/tmp/crtl_tiny_regex_match26)" "tiny-regex: all cases pass"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/crtl_tiny_regex_match.c'` at 6e622be956803d7e310994163d5f9e55db4eddc9

## Range
bad `6e622be95680`, last good `4cf1dfec7c6b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1580102/crtl_tiny_regex_match26  [code=249624B  data=11744B  bss=64132B  procs=692]
expect_same: MISMATCH [crtl_tiny_regex_match26]
--- expected
+++ actual
@@ -1 +1,4 @@
-tiny-regex: all cases pass
+FAIL  /[0-9]+/ on "abc123xyz": got idx=-1 len=0 want idx=3 len=3
+FAIL  /^hello/ on "hello world": got idx=-1 len=0 want idx=0 len=5
+FAIL  /\w+@\w+/ on "x me@host y": got idx=-1 len=0 want idx=2 len=7
+FAIL  /a.c/ on "xxabcyy": got idx=-1 len=0 want idx=2 len=3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
