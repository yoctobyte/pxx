---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_dotted_package_import.npy /tmp/test_nilpy_dottedimport26`, which names `test/test_nilpy_dotted_package_import.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dotted_package_import.npy@1 at 6d04b14cd88d in step 1/2, `./compiler/pascal26 test/test_nilpy_dotted_package_import.npy /tmp/test_nilpy_dottedimport26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T18:37:29Z
- **Test source:** test/test_nilpy_dotted_package_import.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_dotted_package_import.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_dotted_package_import.npy /tmp/test_nilpy_dottedimport26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dotted_package_import.npy@1'` at 6d04b14cd88dfc50f1fe0b20cfa558ea14fd2671

## Range
> **The named sha `6d04b14cd88d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6d04b14cd88d`, last good `c69b52b6ea35`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:16: error: duplicate identifier "letter": Pascal is case-insensitive, so it is the same identifier as "LETTER", already declared in this scope
(tail)
pascal26:79: warning: C declaration of 'pow' disagrees with the Pascal routine 'pow' on parameter 1 (float vs non-float) — binding to the C declaration
note: reportlab_pdfgen -> mimic_reportlab_pdfgen (shim, subset)
note: reportlab_lib_colors -> mimic_reportlab_lib_colors (shim, subset)
pascal26:16: error: duplicate identifier "letter": Pascal is case-insensitive, so it is the same identifier as "LETTER", already declared in this scope
  in: /tmp/testmgr-scratch-1957527/compiler/../lib/pcl/mimic_reportlab_lib_pagesizes.pas
  near: : TPyList ; letter : TPyList >>> ; landscape_A4 : 
note: reportlab_lib_pagesizes -> mimic_reportlab_lib_pagesizes (shim, subset)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
