---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 3 is `tools/expect_same.sh test_nilpy_htmltmp26.2 "$(/tmp/test_nilpy_htmltmp26)" "$(printf '%b' '&lt;a href=&quot;x&quot;&gt;&`. The job's own `src` (`test/test_nilpy_html_tempfile.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_html_tempfile`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_html_tempfile.npy at d01a436c1ce9 in step 2/3, `tools/expect_same.sh test_nilpy_htmltmp26.2 "$(/tmp/test_nilpy_htmltmp26)" "$(printf '%b' '&lt;a href=&quot;x&quot;&gt;…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T05:02:24Z
- **Test source:** test/test_nilpy_html_tempfile.npy tools/expect_same.sh
- **Failing step:** line 2 of 3 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_htmltmp26.2 "$(/tmp/test_nilpy_htmltmp26)" "$(printf '%b' '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;\nit\047s\n<b>&\042AB&nope;\nTrue\n.pdf\nTrue\nFalse')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_html_tempfile.npy'` at d01a436c1ce904c5f6fe6f8c7efa2bb4bf24ff86

## Range
> **The named sha `d01a436c1ce9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d01a436c1ce9`, last good `f72168f983fe`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2486834/test_nilpy_htmltmp26  [code=468572B  data=132640B  bss=101196B  procs=2616  codeseg=470752B]
expect_same: MISMATCH [test_nilpy_htmltmp26.2]
--- expected
+++ actual
@@ -3,5 +3,5 @@
 <b>&"AB&nope;
 True
 .pdf
-True
+False
 False

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
