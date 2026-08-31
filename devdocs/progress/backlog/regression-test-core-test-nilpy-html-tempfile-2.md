---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_html_tempfile.npy red at ef59aaf72b5d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-31T00:11:41Z
- **Test source:** test/test_nilpy_html_tempfile.npy tools/expect_same.sh

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/test_nilpy_html_tempfile.npy'` at ef59aaf72b5d0236501a2a666ac9d142a7c25bfc

## Range
> **The named sha `ef59aaf72b5d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ef59aaf72b5d`, last good `f419f8052369`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3639091/test_nilpy_htmltmp26  [code=1425176B  data=102468B  bss=83452B  procs=2163]
Unhandled exception: FileNotFoundError: [Errno 2] No such file or directory: '/tmp/tmp36717.pdf'
expect_same: MISMATCH [test_nilpy_htmltmp26.2]
--- expected
+++ actual
@@ -4,4 +4,3 @@
 True
 .pdf
 True
-False

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
