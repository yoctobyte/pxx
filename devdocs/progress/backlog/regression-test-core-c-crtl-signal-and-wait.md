---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh c_sigwait26 "$(/tmp/c_sigwait26)" "$(printf '1 0\n2 0\n3 1\n4 0\n5 0\n6 10\n7 -1 1\n8 0\n9 0 10\n10`. The job's own `src` (`test/c_crtl_signal_and_wait.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_crtl_signal_and_wait.c at 0affa5fa87f4 in step 2/2, `tools/expect_same.sh c_sigwait26 "$(/tmp/c_sigwait26)" "$(printf '1 0\n2 0\n3 1\n4 0\n5 0\n6 10\n7 -1 1\n8 0\n9 0 10\n1…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T02:07:43Z
- **Test source:** test/c_crtl_signal_and_wait.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh c_sigwait26 "$(/tmp/c_sigwait26)" "$(printf '1 0\n2 0\n3 1\n4 0\n5 0\n6 10\n7 -1 1\n8 0\n9 0 10\n10 0\n11 0\n12 0\n13 -1 1\n14 1\n15 1\n16 1\n17 7\n18 1\n19 1\n20 1\n21 3\n22 -1 1')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_crtl_signal_and_wait.c'` at 0affa5fa87f4f09ab29cd3d30db695d05bb93f9b

## Range
> **The named sha `0affa5fa87f4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0affa5fa87f4`, last good `6a084d56931a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-792792/c_sigwait26  [code=343832B  data=15600B  bss=81484B  procs=884]
expect_same: MISMATCH [c_sigwait26]
--- expected
+++ actual
@@ -15,7 +15,7 @@
 15 1
 16 1
 17 7
-18 1
+18 0
 19 1
 20 1
 21 3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
