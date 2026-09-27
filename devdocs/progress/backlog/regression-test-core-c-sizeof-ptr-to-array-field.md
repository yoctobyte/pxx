---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh c_szfldptrarr26 "$(/tmp/c_szfldptrarr26)" "FIELD PTRARR OK 16 32 7 24"`. The job's own `src` (`test/c_sizeof_ptr_to_array_field.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `c_sizeof_ptr_to_array_field`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_sizeof_ptr_to_array_field.c at e4203b5aeed9 in step 2/2, `tools/expect_same.sh c_szfldptrarr26 "$(/tmp/c_szfldptrarr26)" "FIELD PTRARR OK 16 32 7 24"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T17:44:17Z
- **Test source:** test/c_sizeof_ptr_to_array_field.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh c_szfldptrarr26 "$(/tmp/c_szfldptrarr26)" "FIELD PTRARR OK 16 32 7 24"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_sizeof_ptr_to_array_field.c'` at e4203b5aeed98355595175e6d2fed5c765740952

## Range
> **The named sha `e4203b5aeed9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e4203b5aeed9`, last good `6bfc726d5677`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3837299/c_szfldptrarr26  [code=63951B  data=13312B  bss=72488B  procs=919  codeseg=65248B]
expect_same: MISMATCH [c_szfldptrarr26]
--- expected
+++ actual
@@ -1 +1,4 @@
-FIELD PTRARR OK 16 32 7 24
+FAIL ip size 8 vs stride 16
+FAIL dp size 8 vs stride 32
+FAIL cp size 8 vs stride 7
+FAIL ip2 size 8 vs stride 24

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
