---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 37 is `tools/expect_same.sh hdrstatic_stdio26 "$(/tmp/hdrstatic_stdio26)" "$(printf '4242\n42')"`. The job's own `src` (`test/test_header_static_body_stdio.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_header_static_body_stdio`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_header_static_body_stdio.pas at f33eeb316d43 in step 2/37, `tools/expect_same.sh hdrstatic_stdio26 "$(/tmp/hdrstatic_stdio26)" "$(printf '4242\n42')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-05T04:32:10Z
- **Test source:** test/test_header_static_body_stdio.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 37 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh hdrstatic_stdio26 "$(/tmp/hdrstatic_stdio26)" "$(printf '4242\n42')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_header_static_body_stdio.pas'` at f33eeb316d4362d85006b8b0dae50990f28fcce0

## Range
> **The named sha `f33eeb316d43` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f33eeb316d43`, last good `9f0bfc4a4bd3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2788047/hdrstatic_stdio26  [code=30719B  data=15192B  bss=88620B  procs=1166  codeseg=32480B]
Segmentation fault (core dumped)
expect_same: MISMATCH [hdrstatic_stdio26]
--- expected
+++ actual
@@ -1,2 +1 @@
-4242
-42
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
