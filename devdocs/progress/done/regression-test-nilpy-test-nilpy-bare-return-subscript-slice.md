---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 3 is `tools/expect_same.sh test_nilpy_bare_ret_subslice26 "$(/tmp/test_nilpy_bare_ret_subslice26)" "$(printf 'a\na\nab\nprefix`. The job's own `src` (`test/test_nilpy_bare_return_subscript_slice.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_bare_return_subscript_slice`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_bare_return_subscript_slice.npy at ec4b9c6a1f22 in step 2/3, `tools/expect_same.sh test_nilpy_bare_ret_subslice26 "$(/tmp/test_nilpy_bare_ret_subslice26)" "$(printf 'a\na\nab\nprefi…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T05:57:21Z
- **Test source:** test/test_nilpy_bare_return_subscript_slice.npy tools/expect_same.sh
- **Failing step:** line 2 of 3 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_bare_ret_subslice26 "$(/tmp/test_nilpy_bare_ret_subslice26)" "$(printf 'a\na\nab\nprefix_\na\n1.5\nTrue\n[1]\na\n1\nv\n[1, 2]\nhello world')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_bare_return_subscript_slice.npy'` at ec4b9c6a1f2292d225e145fdb3965c838ee1bf02

## Range
> **The named sha `ec4b9c6a1f22` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ec4b9c6a1f22`, last good `881fdee59b6f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-641762/test_nilpy_bare_ret_subslice26  [code=1359640B  data=87062B  bss=54740B  procs=2204]
expect_same: MISMATCH [test_nilpy_bare_ret_subslice26]
--- expected
+++ actual
@@ -1,5 +1,5 @@
 a
-a
+H
 ab
 prefix_
 a

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_bare_return_subscript_slice.npy` passes at 4fb3ec5b5d7b (tier full); it was red at ec4b9c6a1f22. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
