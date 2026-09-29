---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_open_array_of_variant26 "$(/tmp/test_open_array_of_variant26)" "$(printf '35\n7\n9')"`. The job's own `src` (`test/test_open_array_of_variant.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_open_array_of_variant`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_open_array_of_variant.pas at a69c18a0208e in step 2/2, `tools/expect_same.sh test_open_array_of_variant26 "$(/tmp/test_open_array_of_variant26)" "$(printf '35\n7\n9')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T03:10:02Z
- **Test source:** test/test_open_array_of_variant.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_open_array_of_variant26 "$(/tmp/test_open_array_of_variant26)" "$(printf '35\n7\n9')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_open_array_of_variant.pas'` at a69c18a0208eb10268a2642c7c6bd258880f104b

## Range
> **The named sha `a69c18a0208e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a69c18a0208e`, last good `fc6f76591258`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1768741/test_open_array_of_variant26  [code=29721B  data=7288B  bss=56324B  procs=616  codeseg=32480B]
expect_same: MISMATCH [test_open_array_of_variant26]
--- expected
+++ actual
@@ -1,3 +1,3 @@
-35
-7
+30
+1
 9

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-29 — auto-closed by the borg watcher: `test-core#src:test/test_open_array_of_variant.pas` passes at f499d25ded91 (tier native); it was red at a69c18a0208e. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
