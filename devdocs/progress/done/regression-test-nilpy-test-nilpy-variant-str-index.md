---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_nilpy_variant_str_index26 "$(/tmp/test_nilpy_variant_str_index26)" "$(printf 'a\na\nb\na d\nc\`. The job's own `src` (`test/test_nilpy_variant_str_index.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_variant_str_index`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_variant_str_index.npy at ec4b9c6a1f22 in step 2/4, `tools/expect_same.sh test_nilpy_variant_str_index26 "$(/tmp/test_nilpy_variant_str_index26)" "$(printf 'a\na\nb\na d\nc…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T05:57:21Z
- **Test source:** test/test_nilpy_variant_str_index.npy tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_variant_str_index26 "$(/tmp/test_nilpy_variant_str_index26)" "$(printf 'a\na\nb\na d\nc\ncaught index\nTrue False\na [\047apple\047, \047avocado\047]\nb [\047banana\047, \047blueberry\047]\n7 5')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_variant_str_index.npy'` at ec4b9c6a1f2292d225e145fdb3965c838ee1bf02

## Range
> **The named sha `ec4b9c6a1f22` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ec4b9c6a1f22`, last good `881fdee59b6f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-641762/test_nilpy_variant_str_index26  [code=1355544B  data=86892B  bss=55500B  procs=2197]
expect_same: MISMATCH [test_nilpy_variant_str_index26]
--- expected
+++ actual
@@ -1,8 +1,8 @@
-a
+ 
 a
 b
 a d
-c
+P
 caught index
 True False
 a ['apple', 'avocado']

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_variant_str_index.npy` passes at 4fb3ec5b5d7b (tier full); it was red at ec4b9c6a1f22. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
