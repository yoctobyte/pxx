---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_nilpy_to_bytes26 "$(/tmp/test_nilpy_to_bytes26)" "$(printf '8\n10\n0\n10\n254\n255\n-2\n255\n0`. The job's own `src` (`test/test_nilpy_to_bytes.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_to_bytes`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_to_bytes.npy at 5dbee723e228 in step 2/4, `tools/expect_same.sh test_nilpy_to_bytes26 "$(/tmp/test_nilpy_to_bytes26)" "$(printf '8\n10\n0\n10\n254\n255\n-2\n255\n…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:17:27Z
- **Test source:** test/test_nilpy_to_bytes.npy tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_to_bytes26 "$(/tmp/test_nilpy_to_bytes26)" "$(printf '8\n10\n0\n10\n254\n255\n-2\n255\n0\n255\n-1\n255\n8\n44\n1\n300\n300\n4\n258\n-2\n6\n8 0 4\n1 2 2\n71\n70\n71\n201\n10\n8 101\n9\n8 0 1\n1 70\n9\n[1, 2, 8]')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_to_bytes.npy'` at 5dbee723e228cfb986a5561e78ccffb7e9a153ec

## Range
bad `5dbee723e228`, last good `1704e17de6f3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3707340/test_nilpy_to_bytes26  [code=1445656B  data=87338B  bss=56740B  procs=2432]
expect_same: MISMATCH [test_nilpy_to_bytes26]
--- expected
+++ actual
@@ -26,7 +26,7 @@
 71
 201
 10
-8 101
+8 0
 9
 8 0 1
 1 70

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
