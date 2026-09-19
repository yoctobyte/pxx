---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 4 of 5, `/tmp/test_nilpy_linecont26 | diff -u test/test_nilpy_line_continuation.expected -`, which names `test/test_nilpy_line_continuation.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_nilpy_str_line_continuation`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_nilpy_line_continuation`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_str_line_continuation.npy at 11e0c581c80d in step 4/5, `/tmp/test_nilpy_linecont26 | diff -u test/test_nilpy_line_continuation.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T14:32:38Z
- **Test source:** test/test_nilpy_str_line_continuation.npy test/test_nilpy_str_line_continuation.expected +2
- **Failing step:** line 4 of 5 of the job's recipe; it names `test/test_nilpy_line_continuation.expected`.
  ```
  /tmp/test_nilpy_linecont26 | diff -u test/test_nilpy_line_continuation.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_str_line_continuation.npy'` at 11e0c581c80df63643f79a9209eade08c166685d

## Range
> **The named sha `11e0c581c80d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `11e0c581c80d`, last good `50195b7f1e27`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1903405/test_nilpy_linecont26  [code=1360378B  data=87788B  bss=62828B  procs=2210  codeseg=1363680B]
ok: /tmp/testmgr-scratch-1903405/test_nilpy_linecont26  [code=1367419B  data=90162B  bss=63484B  procs=2217  codeseg=1367776B]
Segmentation fault (core dumped)
--- test/test_nilpy_line_continuation.expected	2026-09-11 21:30:22.013070641 +0200
+++ -	2026-09-19 16:26:45.574586968 +0200
@@ -6,6 +6,3 @@
 infn 10 cls 2
 indent-free 2
 after 4
-obj 3 8 9
-isinst True True
-paren 3 [1, 2]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-19 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_str_line_continuation.npy` passes at b4104386ae9c (tier full); it was red at 11e0c581c80d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
